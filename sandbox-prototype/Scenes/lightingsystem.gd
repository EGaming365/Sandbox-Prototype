extends Node2D

@export var tile_size: int = 64
@export var cave_base_darkness: float = 0.82
@export var night_base_darkness: float = 0.82
@export var day_base_darkness: float = 0.0
@export var min_darkness_alpha: float = 0.95
@export var update_interval: float = 0.0

var _light_map: Dictionary = {}
var _sources: Dictionary = {}
var _next_source_id: int = 0
var _dirty: bool = true
var _timer: float = 0.0
var _current_darkness: float = 0.0
var _draw_rects: Array = []
var _overlay: Node2D

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

func _process(delta):
	_timer -= delta
	if _timer > 0.0 and not _dirty:
		return
	_timer = update_interval
	_dirty = false
	_update_darkness_base()
	_recalculate()
	_rebuild_draw_rects()
	_overlay.queue_redraw()

func _rebuild_draw_rects():
	_draw_rects.clear()
	if _current_darkness <= 0.0:
		return
	var vp := get_viewport()
	if not vp:
		return
	var camera := vp.get_camera_2d()
	if not camera:
		return
	var screen_size := vp.get_visible_rect().size
	var cam_pos := camera.global_position
	var top_left_world := cam_pos - screen_size / 2.0
	var actual_tile_size: int = 32
	var top_left_tile := Vector2i(
		floori(top_left_world.x / actual_tile_size) - 2,
		floori(top_left_world.y / actual_tile_size) - 2)
	var tiles_x := int(ceil(screen_size.x / actual_tile_size)) + 6
	var tiles_y := int(ceil(screen_size.y / actual_tile_size)) + 6
	for tx in range(top_left_tile.x, top_left_tile.x + tiles_x):
		for ty in range(top_left_tile.y, top_left_tile.y + tiles_y):
			var tc := Vector2i(tx, ty)
			var light_level: float = _light_map.get(tc, 0.0)
			var alpha: float = clamp(_current_darkness - light_level, 0.0, 1.0) * min_darkness_alpha
			if alpha <= 0.01:
				continue
			var screen_x := tc.x * actual_tile_size - top_left_world.x
			var screen_y := tc.y * actual_tile_size - top_left_world.y
			_draw_rects.append({
				"rect": Rect2(Vector2(screen_x, screen_y), Vector2(actual_tile_size, actual_tile_size)),
				"alpha": alpha
			})

func _update_darkness_base():
	var cave_gen = get_tree().root.get_node_or_null("Scene/CaveWorldGen")
	if cave_gen and cave_gen.get("in_cave"):
		_current_darkness = cave_base_darkness
		return
	var weather = get_tree().root.get_node_or_null("Scene/Weather")
	if weather:
		var t = weather.time_of_day
		var is_night = t >= 0.92 or t < 0.20
		var is_dusk_dawn = (t >= 0.82 and t < 0.92) or (t >= 0.20 and t < 0.35)
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

func _recalculate():
	_light_map.clear()
	for source_id in _sources:
		var src = _sources[source_id]
		var world_pos: Vector2 = src["position"]
		if src.get("node") != null and is_instance_valid(src["node"]):
			world_pos = src["node"].global_position + Vector2(0, -16)
		var radius: int = src["radius"]
		var strength: float = src["strength"]
		var exact_tile = world_pos / 32.0
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				var tc := Vector2i(floori(exact_tile.x) + dx, floori(exact_tile.y) + dy)
				var dist := Vector2(
					exact_tile.x - (floori(exact_tile.x) + dx),
					exact_tile.y - (floori(exact_tile.y) + dy)).length()
				if dist > radius:
					continue
				var level := strength * (1.0 - dist / float(radius))
				level = clamp(level, 0.0, 1.0)
				if not _light_map.has(tc) or _light_map[tc] < level:
					_light_map[tc] = level

func add_light_source(node: Node2D, radius: int, strength: float) -> int:
	var id := _next_source_id
	_next_source_id += 1
	_sources[id] = {"node": node, "position": Vector2.ZERO, "radius": radius, "strength": strength}
	_dirty = true
	return id

func add_static_light(world_pos: Vector2, radius: int, strength: float) -> int:
	var id := _next_source_id
	_next_source_id += 1
	_sources[id] = {"node": null, "position": world_pos, "radius": radius, "strength": strength}
	_dirty = true
	return id

func remove_light_source(id: int):
	_sources.erase(id)
	_dirty = true

func mark_dirty():
	_dirty = true
