# Settings manager autoload.
# Stores the volume, darkness and render distance settings and applies them to the audio system, lighting and world generators.

extends Node

# Emitted after the master volume changes, so sliders can stay in sync.
signal volume_changed(new_value)
# Emitted after the night darkness setting changes.
signal darkness_changed(new_value)
# Emitted after the render distance changes.
signal render_distance_changed(new_value)

# Starting master volume from 0 to 100.
const DEFAULT_VOLUME := 70.0
# Starting darkness strength from 0 to 100.
const DEFAULT_DARKNESS := 100.0
# Starting render distance in chunks.
const DEFAULT_RENDER_DISTANCE := 3

# Current master volume from 0 to 100.
var master_volume: float = DEFAULT_VOLUME
# Current darkness setting from 0 to 100.
var darkness: float = DEFAULT_DARKNESS
# Current render distance in chunks.
var render_distance: int = DEFAULT_RENDER_DISTANCE


# Apply the starting values so the game matches the settings from the first frame.
func _ready():
	set_master_volume(master_volume)
	set_darkness(darkness)
	set_render_distance(render_distance)


# Sets the master volume from 0 to 100. A volume of zero mutes the audio completely.
func set_master_volume(new_value: float):
	master_volume = clampf(new_value, 0.0, 100.0)
	# The master audio bus controls the volume of all sound.
	var master_bus_index := AudioServer.get_bus_index("Master")
	if master_bus_index != -1:
		if master_volume <= 0.0:
			AudioServer.set_bus_mute(master_bus_index, true)
		else:
			AudioServer.set_bus_mute(master_bus_index, false)
			# Convert the 0 to 100 slider value to decibels.
			AudioServer.set_bus_volume_db(master_bus_index, linear_to_db(master_volume / 100.0))
	volume_changed.emit(master_volume)


# Sets how dark the night gets, from 0 (no darkness) to 100 (full darkness), and tells the lighting system to redraw.
func set_darkness(new_value: float):
	darkness = clampf(new_value, 0.0, 100.0)
	var lighting_system := get_tree().root.get_node_or_null("Scene/LightingSystem")
	if lighting_system:
		lighting_system.min_darkness_alpha = darkness / 100.0
		lighting_system.mark_dirty()
	darkness_changed.emit(darkness)


# Sets how many chunks are loaded around the player, from 1 to 5, and updates every world generator.
func set_render_distance(new_value: int):
	render_distance = clampi(new_value, 1, 5)

	# The environment generator loads trees and rocks. It unloads one chunk further out than it loads.
	var environment_generator := get_tree().root.get_node_or_null("Scene/EnvironmentGen")
	if environment_generator:
		environment_generator.render_distance_chunks = render_distance
		environment_generator.unload_distance_chunks = render_distance + 1

	# The overworld generator loads terrain chunks and unloads two chunks further out than it loads.
	var world_generator := get_tree().root.get_node_or_null("Scene/WorldGen")
	if world_generator:
		world_generator.chunk_view_distance = render_distance
		world_generator.chunk_unload_distance = render_distance + 2

	# The cave generator uses the same distances as the overworld generator.
	var cave_generator := get_tree().root.get_node_or_null("Scene/CaveWorldGen")
	if cave_generator:
		cave_generator.chunk_view_distance = render_distance
		cave_generator.chunk_unload_distance = render_distance + 2

	render_distance_changed.emit(render_distance)
