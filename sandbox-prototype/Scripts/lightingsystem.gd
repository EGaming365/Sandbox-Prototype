extends Node2D

@export var tile_size: int = 64
@export var light_detail_tile_size: int = 32
@export var cave_base_darkness: float = 0.82
@export var night_base_darkness: float = 0.82
@export var day_base_darkness: float = 0.0
@export var min_darkness_alpha: float = 1.0
@export var update_interval: float = 0.25
@export var torch_bright_radius: int = 6
@export var torch_bright_level: float = 1.0

var _light_map: Dictionary = {}
var _sources: Dictionary = {}
var _next_source_id: int = 0
var _dirty: bool = true
var _timer: float = 0.0
var _current_darkness: float = 0.0
var _last_darkness: float = -1.0
var _draw_rects: Array = []
var _overlay: Node2D
var _last_camera_tile: Vector2i = Vector2i(999999, 999999)
var _last_screen_size: Vector2 = Vector2.ZERO
var _committed_source_tiles: Dictionary = {}

func _ready():
	set_process(true)
	call_deferred("_setup_overlay")

func _setup_overlay():
	var canvas := CanvasLayer.new()
	canvas.layer = 0
	canvas.follow_viewport_enabled = false
	get_tree().root.add_child(canvas)
	var overlay_script := GDScript.new()
	overlay_script.source_code = _overlay_source()
	overlay_script.reload()
	_overlay = Node2D.new()
	_overlay.set_script(overlay_script)
	canvas.add_child(_overlay)
	_overlay.set("lighting_manager", self)

func _overlay_source() -> String:
	return """extends Node2D
var lighting_manager: Node
func _draw():
\tif not lighting_manager:
\t\treturn
\tvar vp := get_viewport()
\tif not vp:
\t\treturn
\tvar screen_size := vp.get_visible_rect().size
\tvar base_alpha: float = lighting_manager._current_darkness * lighting_manager.min_darkness_alpha
\tif base_alpha > 0.01:
\t\tdraw_rect(Rect2(Vector2.ZERO, screen_size), Color(0, 0, 0, base_alpha), true)
\tfor entry in lighting_manager._draw_rects:
\t\tdraw_rect(entry["rect"], Color(0, 0, 0, entry["alpha"]), true)
"""

func _update_darkness_base():
	var cave_gen = get_tree().root.get_node_or_null("Scene/CaveWorldGen")
	if cave_gen and cave_gen.get("in_cave"):
		_current_darkness = cave_base_darkness
		return
	var weather = get_tree().root.get_node_or_null("Scene/Weather")
	if weather:
		var t: float = weather.time_of_day
		var is_night: bool = t >= 0.92 or t < 0.20
		var is_dusk_dawn: bool = (t >= 0.82 and t < 0.92) or (t >= 0.20 and t < 0.35)
		if is_night:
			_current_darkness = night_base_darkness
		elif is_dusk_dawn:
			var blend: float
			if t >= 0.82 and t < 0.92:
				blend = inverse_lerp(0.82, 0.92, t)
			else:
				blend = 1.0 - inverse_lerp(0.20, 0.35, t)
			_current_darkness = lerp(day_base_darkness, night_base_darkness, blend)
		else:
			_current_darkness = day_base_darkness
		if weather.aurora_active:
			_current_darkness = lerp(_current_darkness, 0.0, 0.6)
	else:
		_current_darkness = day_base_darkness

func _process(delta):
	_timer -= delta
	if _timer > 0.0 and not _dirty:
		return

	_update_darkness_base()

	if _current_darkness <= 0.0:
		if _last_darkness != 0.0:
			_last_darkness = 0.0
			_light_map.clear()
			_draw_rects.clear()
			if _overlay:
				_overlay.queue_redraw()
		_timer = update_interval
		_dirty = false
		return

	var darkness_changed: bool = absf(_current_darkness - _last_darkness) > 0.01
	var camera_moved: bool = _camera_view_changed()
	var sources_moved: bool = _sources_moved_tiles_cheap()

	if not _dirty and not darkness_changed and not camera_moved and not sources_moved:
		_timer = update_interval
		return

	_timer = update_interval
	_dirty = false
	_last_darkness = _current_darkness

	_recalculate()
	_rebuild_draw_rects()
	if _overlay:
		_overlay.queue_redraw()

func _sources_moved_tiles_cheap() -> bool:
	for source_id in _sources:
		var src = _sources[source_id]
		if src.get("node") == null or not is_instance_valid(src["node"]):
			continue
		var world_pos: Vector2 = src["node"].global_position + Vector2(0, -16)
		var tc := Vector2i(
			floori(world_pos.x / light_detail_tile_size),
			floori(world_pos.y / light_detail_tile_size))
		if _committed_source_tiles.get(source_id, Vector2i(999999, 999999)) != tc:
			return true
	for source_id in _committed_source_tiles:
		if not _sources.has(source_id):
			return true
	return false

func _camera_view_changed() -> bool:
	var vp := get_viewport()
	if not vp:
		return false
	var camera := vp.get_camera_2d()
	if not camera:
		return false
	var screen_size := vp.get_visible_rect().size
	var cam_tile := Vector2i(
		floori(camera.global_position.x / light_detail_tile_size),
		floori(camera.global_position.y / light_detail_tile_size))
	if cam_tile != _last_camera_tile or screen_size != _last_screen_size:
		_last_camera_tile = cam_tile
		_last_screen_size = screen_size
		return true
	return false

func _get_visible_tile_bounds() -> Array:
	var vp := get_viewport()
	var camera := vp.get_camera_2d() if vp else null
	if not camera or not vp:
		return []
	var screen_size := vp.get_visible_rect().size
	var top_left_world := camera.global_position - screen_size / 2.0
	var pad := 4
	var min_tc := Vector2i(
		floori(top_left_world.x / light_detail_tile_size) - pad,
		floori(top_left_world.y / light_detail_tile_size) - pad)
	var max_tc := Vector2i(
		min_tc.x + int(ceil(screen_size.x / light_detail_tile_size)) + pad * 2,
		min_tc.y + int(ceil(screen_size.y / light_detail_tile_size)) + pad * 2)
	return [min_tc, max_tc, top_left_world]

func _recalculate():
	_light_map.clear()

	var bounds := _get_visible_tile_bounds()
	if bounds.is_empty():
		return

	var view_min: Vector2i = bounds[0]
	var view_max: Vector2i = bounds[1]

	for source_id in _sources:
		var src = _sources[source_id]
		var world_pos: Vector2 = src["position"]
		if src.get("node") != null and is_instance_valid(src["node"]):
			world_pos = src["node"].global_position + Vector2(0, -16)

		_committed_source_tiles[source_id] = Vector2i(
			floori(world_pos.x / light_detail_tile_size),
			floori(world_pos.y / light_detail_tile_size))

		var radius: int = src["radius"]
		var strength: float = src["strength"]
		var bright_close: bool = src.get("bright_close", false)
		var bright_r: int = src.get("bright_radius", torch_bright_radius)
		var bright_lvl: float = src.get("bright_level", torch_bright_level)

		var exact_tile := world_pos / float(light_detail_tile_size)
		var src_center := Vector2i(floori(exact_tile.x), floori(exact_tile.y))

		var iter_min := Vector2i(
			max(src_center.x - radius, view_min.x),
			max(src_center.y - radius, view_min.y))
		var iter_max := Vector2i(
			min(src_center.x + radius, view_max.x),
			min(src_center.y + radius, view_max.y))

		if iter_min.x > iter_max.x or iter_min.y > iter_max.y:
			continue

		for tx in range(iter_min.x, iter_max.x + 1):
			for ty in range(iter_min.y, iter_max.y + 1):
				var tc := Vector2i(tx, ty)
				if _light_map.get(tc, 0.0) >= 1.0:
					continue
				var dist: float = Vector2(exact_tile.x - tx, exact_tile.y - ty).length()
				if dist > radius:
					continue
				var level: float
				if bright_close and dist <= bright_r:
					level = bright_lvl
				else:
					level = strength * (1.0 - dist / float(radius))
				level = clamp(level, 0.0, 1.0)
				if level > _light_map.get(tc, 0.0):
					_light_map[tc] = level

	for source_id in _committed_source_tiles.keys().duplicate():
		if not _sources.has(source_id):
			_committed_source_tiles.erase(source_id)

func _rebuild_draw_rects():
	_draw_rects.clear()
	if _current_darkness <= 0.0:
		return

	var bounds := _get_visible_tile_bounds()
	if bounds.is_empty():
		return

	var view_min: Vector2i = bounds[0]
	var view_max: Vector2i = bounds[1]
	var top_left_world: Vector2 = bounds[2]
	var ts: float = float(light_detail_tile_size)

	for tx in range(view_min.x, view_max.x + 1):
		for ty in range(view_min.y, view_max.y + 1):
			var tc := Vector2i(tx, ty)
			var light_level: float = _light_map.get(tc, 0.0)
			var alpha: float = clamp(_current_darkness - light_level, 0.0, 1.0) * min_darkness_alpha
			if alpha <= 0.01:
				continue
			_draw_rects.append({
				"rect": Rect2(
					Vector2(tc.x * ts - top_left_world.x, tc.y * ts - top_left_world.y),
					Vector2(ts, ts)),
				"alpha": alpha
			})

func add_light_source(node: Node2D, radius: int, strength: float, bright_close: bool = false) -> int:
	var id := _next_source_id
	_next_source_id += 1
	_sources[id] = {
		"node": node,
		"position": Vector2.ZERO,
		"radius": radius,
		"strength": strength,
		"bright_close": bright_close,
		"bright_radius": torch_bright_radius,
		"bright_level": torch_bright_level,
	}
	_dirty = true
	return id

func add_static_light(world_pos: Vector2, radius: int, strength: float, bright_close: bool = false) -> int:
	var id := _next_source_id
	_next_source_id += 1
	_sources[id] = {
		"node": null,
		"position": world_pos,
		"radius": radius,
		"strength": strength,
		"bright_close": bright_close,
		"bright_radius": torch_bright_radius,
		"bright_level": torch_bright_level,
	}
	_dirty = true
	return id

func remove_light_source(id: int):
	_sources.erase(id)
	_committed_source_tiles.erase(id)
	_dirty = true

func get_light_level_at(world_pos: Vector2) -> float:
	var tile := Vector2i(
		floori(world_pos.x / light_detail_tile_size),
		floori(world_pos.y / light_detail_tile_size))
	return _light_map.get(tile, 0.0)

func mark_dirty():
	_dirty = true
