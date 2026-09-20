extends Node

signal volume_changed(value)
signal darkness_changed(value)
signal render_distance_changed(value)

const DEFAULT_VOLUME := 70.0
const DEFAULT_DARKNESS := 100.0
const DEFAULT_RENDER_DISTANCE := 3

var master_volume: float = DEFAULT_VOLUME
var darkness: float = DEFAULT_DARKNESS
var render_distance: int = DEFAULT_RENDER_DISTANCE


func _ready():
	set_master_volume(master_volume)
	set_darkness(darkness)
	set_render_distance(render_distance)


func set_master_volume(value: float):
	master_volume = clampf(value, 0.0, 100.0)
	var bus_index := AudioServer.get_bus_index("Master")
	if bus_index != -1:
		if master_volume <= 0.0:
			AudioServer.set_bus_mute(bus_index, true)
		else:
			AudioServer.set_bus_mute(bus_index, false)
			AudioServer.set_bus_volume_db(bus_index, linear_to_db(master_volume / 100.0))
	volume_changed.emit(master_volume)


func set_darkness(value: float):
	darkness = clampf(value, 0.0, 100.0)
	var lighting := get_tree().root.get_node_or_null("Scene/LightingSystem")
	if lighting:
		lighting.min_darkness_alpha = darkness / 100.0
		lighting.mark_dirty()
	darkness_changed.emit(darkness)


func set_render_distance(value: int):
	render_distance = clampi(value, 1, 5)

	var env_gen := get_tree().root.get_node_or_null("Scene/EnvironmentGen")
	if env_gen:
		env_gen.render_distance_chunks = render_distance
		env_gen.unload_distance_chunks = render_distance + 1

	var world_gen := get_tree().root.get_node_or_null("Scene/WorldGen")
	if world_gen:
		world_gen.chunk_view_distance = render_distance
		world_gen.chunk_unload_distance = render_distance + 2

	var cave_gen := get_tree().root.get_node_or_null("Scene/CaveWorldGen")
	if cave_gen:
		cave_gen.chunk_view_distance = render_distance
		cave_gen.chunk_unload_distance = render_distance + 2

	render_distance_changed.emit(render_distance)
