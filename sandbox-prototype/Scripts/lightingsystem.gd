# Lighting system.
# Darkens the screen at night and in caves by drawing a grid of black tiles over the view, then lightens the tiles near light sources such as torches.
# The overlay is redrawn only when the camera, the darkness or a light source changes.

extends Node2D

# Size of a world tile in pixels. The lighting itself uses light_detail_tile_size instead.
@export var tile_size: int = 64
# Size in pixels of each square in the lighting grid. Smaller squares give smoother light but cost more.
@export var light_detail_tile_size: int = 32
# How dark the cave is with no light, from 0 to 1.
@export var cave_base_darkness: float = 0.95
# How dark the night is with no light, from 0 to 1.
@export var night_base_darkness: float = 0.95
# How dark the day is, from 0 to 1.
@export var day_base_darkness: float = 0.0
# Strength of the darkness overlay. The settings menu changes this.
@export var min_darkness_alpha: float = 1.0
# Minimum seconds between lighting updates.
@export var update_interval: float = 0.05
# Radius in tiles around a bright light where the light is at full strength.
@export var torch_bright_radius: int = 14.0
# Light level inside that bright radius.
@export var torch_bright_level: float = 1.0

# Light level from 0 to 1 for each lit tile.
var _light_map: Dictionary = {}
# All light sources, stored by ID.
var _sources: Dictionary = {}
# ID given to the next light source that is added.
var _next_source_id: int = 0
# True when the lighting must be recalculated.
var _dirty: bool = true
# Counts down until the next allowed update.
var _timer: float = 0.0
# Darkness for the current time and place.
var _current_darkness: float = 0.0
# Darkness used for the last calculation, to detect changes.
var _last_darkness: float = -1.0
# Rectangles to draw, each paired with its darkness.
var _draw_rects: Array = []
# Node that draws the darkness rectangles.
var _overlay: Node2D
# Tile the camera was over at the last update.
var _last_camera_tile: Vector2i = Vector2i(999999, 999999)
# Screen size at the last update.
var _last_screen_size: Vector2 = Vector2.ZERO
# Tile each moving light source was in at the last update.
var _committed_source_tiles: Dictionary = {}
# The cave generator, which tells us whether the player is in the cave.
var _cave_gen: Node = null
# The weather system, which provides the time of day.
var _weather: Node = null
# The viewport used to find the camera and the screen size.
var _viewport: Viewport = null


# Creates the overlay after the scene has finished loading.
func _ready():
	set_process(true)
	call_deferred("_setup_overlay")


# Creates a canvas layer with a node that draws the darkness, and finds the cave generator, weather system and viewport.
func _setup_overlay():
	var canvas := CanvasLayer.new()
	canvas.layer = 0
	canvas.follow_viewport_enabled = false
	get_tree().root.add_child(canvas)
	# The drawing script is created from text at run time.
	var overlay_script := GDScript.new()
	overlay_script.source_code = _overlay_source()
	overlay_script.reload()
	_overlay = Node2D.new()
	_overlay.set_script(overlay_script)
	canvas.add_child(_overlay)
	_overlay.set("lighting_manager", self)
	_cave_gen = get_tree().root.get_node_or_null("Scene/CaveWorldGen")
	_weather = get_tree().root.get_node_or_null("Scene/Weather")
	_viewport = get_viewport()


# Returns the source code of the overlay script. It draws every rectangle in the lighting manager's list.
func _overlay_source() -> String:
	return """extends Node2D
var lighting_manager: Node


func _draw():
\tif not lighting_manager:
\t\treturn
\tfor entry in lighting_manager._draw_rects:
\t\tdraw_rect(entry[0], Color(0, 0, 0, entry[1]), true)
"""


# Works out the light level of every tile in view, then builds the list of dark rectangles to draw.
func _recalculate_and_build():
	_light_map.clear()
	_draw_rects.clear()

	# Find the tiles that are visible on screen.
	var bounds := _get_visible_tile_bounds()
	if bounds.is_empty():
		return

	var view_min: Vector2i = bounds[0]
	var view_max: Vector2i = bounds[1]
	var tile_size_float: float = float(light_detail_tile_size)
	var darkness: float = _current_darkness
	var min_alpha: float = min_darkness_alpha

	# Spread each light source's light over the tiles around it, keeping the brightest value for each tile.
	for source_id in _sources:
		var light_source = _sources[source_id]
		# Sources attached to a node follow it, and the others use their fixed position.
		var world_pos: Vector2 = light_source["position"]
		if light_source.get("node") != null and is_instance_valid(light_source["node"]):
			world_pos = light_source["node"].global_position + Vector2(0, -16)

		_committed_source_tiles[source_id] = Vector2i(
			floori(world_pos.x / light_detail_tile_size),
			floori(world_pos.y / light_detail_tile_size))

		var radius: int = light_source["radius"]
		var strength: float = light_source["strength"]
		var bright_close: bool = light_source.get("bright_close", false)
		var bright_radius_tiles: float = float(light_source.get("bright_radius", torch_bright_radius))
		var bright_level_value: float = light_source.get("bright_level", torch_bright_level)
		var radius_float: float = float(radius)

		var exact_x: float = world_pos.x / tile_size_float
		var exact_y: float = world_pos.y / tile_size_float
		var src_center := Vector2i(floori(exact_x), floori(exact_y))

		var iter_min := Vector2i(
			max(src_center.x - radius, view_min.x),
			max(src_center.y - radius, view_min.y))
		var iter_max := Vector2i(
			min(src_center.x + radius, view_max.x),
			min(src_center.y + radius, view_max.y))

		if iter_min.x > iter_max.x or iter_min.y > iter_max.y:
			continue

		for tx in range(iter_min.x, iter_max.x + 1):
			var dx: float = exact_x - tx
			var dx2: float = dx * dx
			for ty in range(iter_min.y, iter_max.y + 1):
				var dy: float = exact_y - ty
				var distance_squared: float = dx2 + dy * dy
				if distance_squared > radius_float * radius_float:
					continue
				var distance: float = sqrt(distance_squared)
				# Bright sources are at full strength near the centre. Otherwise the light fades linearly to zero at the edge.
				var level: float
				if bright_close and distance <= bright_radius_tiles:
					level = bright_level_value
				else:
					level = strength * (1.0 - distance / radius_float)
				if level < 0.0:
					level = 0.0
				elif level > 1.0:
					level = 1.0
				var tile_coord := Vector2i(tx, ty)
				if level > _light_map.get(tile_coord, 0.0):
					_light_map[tile_coord] = level

	# Forget tiles for light sources that have been removed.
	for source_id in _committed_source_tiles.keys().duplicate():
		if not _sources.has(source_id):
			_committed_source_tiles.erase(source_id)

	var top_left_world: Vector2 = bounds[2]
	var tile_vec := Vector2(tile_size_float, tile_size_float)
	var full_dark_alpha: float = darkness * min_alpha

	# Create a rectangle for every lit tile. Darkness is lower where the light is stronger.
	var lit_tiles: Dictionary = {}
	for tile_coord in _light_map:
		if tile_coord.x < view_min.x or tile_coord.x > view_max.x or tile_coord.y < view_min.y or tile_coord.y > view_max.y:
			continue
		lit_tiles[tile_coord] = true
		var light_level: float = _light_map[tile_coord]
		var alpha: float
		if light_level >= darkness:
			alpha = 0.0
		else:
			alpha = (1.0 - light_level / darkness) * darkness * min_alpha
		if alpha > 1.0:
			alpha = 1.0
		_draw_rects.append([
			Rect2(Vector2(tile_coord.x * tile_size_float - top_left_world.x, tile_coord.y * tile_size_float - top_left_world.y), tile_vec),
			alpha
		])

	# Cover every remaining tile in view with full darkness.
	if full_dark_alpha > 0.01:
		for tx in range(view_min.x, view_max.x + 1):
			for ty in range(view_min.y, view_max.y + 1):
				var tile_coord := Vector2i(tx, ty)
				if lit_tiles.has(tile_coord):
					continue
				_draw_rects.append([
					Rect2(Vector2(tile_coord.x * tile_size_float - top_left_world.x, tile_coord.y * tile_size_float - top_left_world.y), tile_vec),
					full_dark_alpha
				])


# Chooses the base darkness: the cave value in the cave, otherwise a blend between day and night based on the time of day.
func _update_darkness_base():
	if _cave_gen and is_instance_valid(_cave_gen) and _cave_gen.get("in_cave"):
		_current_darkness = cave_base_darkness
		return
	if _weather and is_instance_valid(_weather):
		var t: float = _weather.time_of_day
		# Full night.
		if t >= 0.92 or t < 0.20:
			_current_darkness = night_base_darkness
		# Dusk and dawn fade smoothly between day and night.
		elif (t >= 0.82 and t < 0.92) or (t >= 0.20 and t < 0.35):
			var blend: float
			if t >= 0.82 and t < 0.92:
				blend = inverse_lerp(0.82, 0.92, t)
			else:
				blend = 1.0 - inverse_lerp(0.20, 0.35, t)
			_current_darkness = lerp(day_base_darkness, night_base_darkness, blend)
		else:
			_current_darkness = day_base_darkness
		# An aurora makes the night brighter.
		if _weather.aurora_active:
			_current_darkness = lerp(_current_darkness, 0.0, 0.6)
	else:
		_current_darkness = day_base_darkness


# Recalculates the lighting only when something has changed.
func _process(delta):
	_timer -= delta
	if _timer > 0.0 and not _dirty:
		return

	_update_darkness_base()

	# In full daylight there is nothing to draw, so clear everything once.
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

	# Work out whether the darkness, the camera or a moving light has changed since the last update.
	var darkness_changed: bool = absf(_current_darkness - _last_darkness) > 0.01
	var camera_moved: bool = _camera_view_changed()
	var sources_moved: bool = _sources_moved_tiles_cheap()

	if not _dirty and not darkness_changed and not camera_moved and not sources_moved:
		_timer = update_interval
		return

	_timer = update_interval
	_dirty = false
	_last_darkness = _current_darkness

	_recalculate_and_build()
	if _overlay:
		_overlay.queue_redraw()


# Returns true if any light source has moved to a new tile or been removed.
func _sources_moved_tiles_cheap() -> bool:
	for source_id in _sources:
		var light_source = _sources[source_id]
		if light_source.get("node") == null or not is_instance_valid(light_source["node"]):
			continue
		var world_pos: Vector2 = light_source["node"].global_position + Vector2(0, -16)
		var tile_coord := Vector2i(
			floori(world_pos.x / light_detail_tile_size),
			floori(world_pos.y / light_detail_tile_size))
		if _committed_source_tiles.get(source_id, Vector2i(999999, 999999)) != tile_coord:
			return true
	for source_id in _committed_source_tiles:
		if not _sources.has(source_id):
			return true
	return false


# Returns true if the camera has moved to a new tile or the screen size has changed.
func _camera_view_changed() -> bool:
	if not _viewport or not is_instance_valid(_viewport):
		_viewport = get_viewport()
		if not _viewport:
			return false
	var camera := _viewport.get_camera_2d()
	if not camera:
		return false
	var screen_size := _viewport.get_visible_rect().size
	var cam_tile := Vector2i(
		floori(camera.global_position.x / light_detail_tile_size),
		floori(camera.global_position.y / light_detail_tile_size))
	if cam_tile != _last_camera_tile or screen_size != _last_screen_size:
		_last_camera_tile = cam_tile
		_last_screen_size = screen_size
		return true
	return false


# Returns the smallest and largest visible tile, plus the world position of the top left of the screen. It adds a small border.
func _get_visible_tile_bounds() -> Array:
	if not _viewport:
		return []
	var camera := _viewport.get_camera_2d()
	if not camera:
		return []
	var screen_size := _viewport.get_visible_rect().size
	var top_left_world := camera.global_position - screen_size / 2.0
	var tile_padding := 4
	var min_tc := Vector2i(
		floori(top_left_world.x / light_detail_tile_size) - tile_padding,
		floori(top_left_world.y / light_detail_tile_size) - tile_padding)
	var max_tc := Vector2i(
		min_tc.x + int(ceil(screen_size.x / light_detail_tile_size)) + tile_padding * 2,
		min_tc.y + int(ceil(screen_size.y / light_detail_tile_size)) + tile_padding * 2)
	return [min_tc, max_tc, top_left_world]


# Adds a light that follows a node, and returns its ID.
func add_light_source(
	node: Node2D,
	radius: int,
	strength: float,
	bright_close: bool = false,
) -> int:
	var light_id := _next_source_id
	_next_source_id += 1
	_sources[light_id] = {
		"node": node,
		"position": Vector2.ZERO,
		"radius": radius,
		"strength": strength,
		"bright_close": bright_close,
		"bright_radius": torch_bright_radius,
		"bright_level": torch_bright_level,
	}
	_dirty = true
	return light_id


# Adds a light at a fixed position, and returns its ID.
func add_static_light(
	world_pos: Vector2,
	radius: int,
	strength: float,
	bright_close: bool = false,
) -> int:
	var light_id := _next_source_id
	_next_source_id += 1
	_sources[light_id] = {
		"node": null,
		"position": world_pos,
		"radius": radius,
		"strength": strength,
		"bright_close": bright_close,
		"bright_radius": torch_bright_radius,
		"bright_level": torch_bright_level,
	}
	_dirty = true
	return light_id


# Removes the light with the given ID.
func remove_light_source(light_id: int):
	_sources.erase(light_id)
	_committed_source_tiles.erase(light_id)
	_dirty = true


# Returns the light level from 0 to 1 at a world position.
func get_light_level_at(world_pos: Vector2) -> float:
	var tile := Vector2i(
		floori(world_pos.x / light_detail_tile_size),
		floori(world_pos.y / light_detail_tile_size))
	return _light_map.get(tile, 0.0)


# Forces the lighting to be recalculated on the next update.
func mark_dirty():
	_dirty = true
