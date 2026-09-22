# Fishing minigame.
# The player holds a bar to keep it over a moving fish zone. Progress fills while they overlap and drains when they do not.
# Emits fish_caught when the bar is full and fish_escaped when it is empty.

extends Control

# Coloured area that moves up and down. The player must keep their bar over it.
var fish_zone: Control
# Bar the player controls.
var player_bar: Control
# Filled part of the progress bar.
# Catch progress from 0 to 100. It starts half full.
var progress_fill: Control
# Label showing the fish being caught.
var fish_label: Label
# On screen button that acts like holding the fish key.
var hold_button: Button

# Height of the catch bar track in pixels.
const TRACK_HEIGHT = 400.0
# Default height of the player's bar in pixels.
const PLAYER_H = 48.0

# True while the player is holding the reel key or button.
var holding := false
# Top of the player's bar as a fraction of the track (0 is the top).
var player_y := 0.5
# Top of the fish zone as a fraction of the track.
var fish_zone_y := 0.5
# Current speed of the player's bar.
var player_vel := 0.0
# Unused speed value for the fish zone.
var fish_vel := 0.0
# Height of the fish zone in pixels.
var fish_zone_height := 80.0
# How fast and how far the fish zone moves. Higher is harder.
var fish_speed := 1.0
# How quickly progress fills while the bars overlap.
var progress_rate := 1.0
# How quickly progress drains while the bars do not overlap.
var escape_rate := 1.0
# How quickly the player's bar moves.
var bar_speed := 1.0
# Height of the player's bar for this fish.
var effective_player_h: float = PLAYER_H

# Emitted when the progress bar fills completely.
signal fish_caught
# Emitted when the progress bar empties.
signal fish_escaped

var progress := 50.0
# Stays false until setup has been called with the fish's details.
var _ready_to_process: bool = false


# Finds the child nodes and connects the hold button.
func _ready():
	fish_zone = $HBoxContainer/Catchbar/FishZone
	player_bar = $HBoxContainer/Catchbar/PlayerBar
	progress_fill = $HBoxContainer/ProgressBar/ProgressFill
	fish_label = $FishLabel
	hold_button = $HoldButton
	hold_button.button_down.connect(_on_hold_button_button_down)
	hold_button.button_up.connect(_on_hold_button_button_up)
	$HBoxContainer/ProgressBar/Panel.visible = false
	$HBoxContainer/Catchbar/Panel.visible = false


# Configures the minigame for a fish from its data: size, speed, mutations and weight.
func setup(fish_data: Dictionary):
	var display_name: String = fish_data.name
	effective_player_h = fish_data.get("player_bar", 48.0)
	player_bar.size.y = effective_player_h
	var mutations: Array = fish_data.get("mutations", [])
	# Mutated fish change the colour of the bars.
	if "Albino" in mutations:
		display_name = "Albino " + display_name
		fish_zone.modulate = Color(0.78, 0.78, 0.78)
	if "Shiny" in mutations:
		display_name = "Shiny " + display_name
		fish_zone.modulate = Color(1.6, 1.35, 0.2)  # Golden bar
		player_bar.modulate = Color(1.4, 1.2, 0.15)  # Golden player bar too
	elif "Silver" in mutations:
		fish_zone.modulate = Color(0.72, 0.85, 1.0)  # Cool silver-blue
		player_bar.modulate = Color(0.8, 0.9, 1.0)
	elif "Darkened" in mutations:
		fish_zone.modulate = Color(0.25, 0.25, 0.35)  # Very dark, slightly purple

	# Work out a size label such as giant or tiny by comparing the weight with the fish's usual weight.
	var weight: float = fish_data.get("weight_kg", 0.0)
	var base_kg: float = fish_data.get("base_weight_kg", 1.0)
	var size_tag := ""
	if weight > 0.0 and base_kg > 0.0:
		var ratio := weight / base_kg
		if ratio >= 2.5:
			size_tag = " (giant)"
		elif ratio >= 1.8:
			size_tag = " (large)"
		elif ratio >= 1.4:
			size_tag = " (big)"
		elif ratio <= 0.15:
			size_tag = " (tiny)"
		elif ratio <= 0.35:
			size_tag = " (small)"
	# Format the weight in grams below 1 kg, otherwise in kilograms.
	var weight_str := ""
	if weight > 0.0:
		if weight < 1.0:
			weight_str = "  •  " + str(int(weight * 1000)) + "g"
		else:
			weight_str = "  •  " + str(snappedf(weight, 0.01)) + "kg"
	# Copy the difficulty values from the fish data and start both bars in the middle.
	fish_zone_height = fish_data.zone_height
	fish_speed = fish_data.speed
	progress_rate = fish_data.progress_rate
	escape_rate = fish_data.escape_rate
	fish_zone.size.y = fish_zone_height
	fish_zone_y = 0.5 - (fish_zone_height / TRACK_HEIGHT) / 2.0
	player_y = 0.5 - (effective_player_h / TRACK_HEIGHT) / 2.0
	bar_speed = fish_data.get("bar_speed", 1.0)
	_ready_to_process = true


# The on screen button was pressed.
func _on_hold_button_button_down():
	holding = true


# The on screen button was released.
func _on_hold_button_button_up():
	holding = false


# Runs the minigame each frame once it has been set up.
func _process(delta):
	if not _ready_to_process:
		return
	holding = Input.is_action_pressed("fish")
	_update_fish_zone(delta)
	_update_player(delta)
	_update_progress(delta)
	_apply_visuals()

# Where the fish zone is currently drifting to.
var fish_target_y := 0.3
# Time until the fish picks a new target.
var fish_move_timer: float = 0.0
# Seconds between target changes.
var fish_move_interval: float = 1.5


# Moves the fish zone towards a random target and picks a new target every so often.
func _update_fish_zone(delta):
	fish_move_timer -= delta
	if fish_move_timer <= 0.0:
		var max_y = 1.0 - fish_zone_height / TRACK_HEIGHT
		var range_size = max_y * (0.4 + fish_speed * 0.35)
		var center = clamp(fish_zone_y, range_size * 0.5, max_y - range_size * 0.5)
		fish_target_y = clamp(center + randf_range(-range_size, range_size), 0.0, max_y)
		fish_move_interval = randf_range(0.8, 2.2) / fish_speed
		fish_move_timer = fish_move_interval
	var max_y = 1.0 - fish_zone_height / TRACK_HEIGHT
	fish_zone_y = move_toward(fish_zone_y, fish_target_y, fish_speed * 0.18 * delta)
	fish_zone_y = clamp(fish_zone_y, 0.0, max_y)


# Moves the player's bar up while holding and lets it fall when released.
func _update_player(delta):
	var target_vel: float = -0.35 * bar_speed if holding else 0.5 * bar_speed
	player_vel = lerp(player_vel, target_vel, delta * 6.0 * bar_speed)
	player_y += player_vel * delta
	player_y = clamp(player_y, 0.0, 1.0 - effective_player_h / TRACK_HEIGHT)


# Fills or drains progress depending on whether the bars overlap, and finishes the minigame at either end.
func _update_progress(delta):
	var player_top := player_y
	var player_bottom := player_y + effective_player_h / TRACK_HEIGHT
	var fish_top := fish_zone_y
	var fish_bottom := fish_zone_y + fish_zone_height / TRACK_HEIGHT
	# Amount by which the two bars overlap, as a fraction of the track.
	var overlap: float = max(0.0, min(player_bottom, fish_bottom) - max(player_top, fish_top))
	var in_zone: bool = overlap > 0.01
	if in_zone:
		progress += progress_rate * delta * 15.0
	else:
		progress -= escape_rate * delta * 12.0
	progress = clamp(progress, 0.0, 100.0)
	if progress >= 100.0:
		emit_signal("fish_caught")
		queue_free()
	elif progress <= 0.0:
		emit_signal("fish_escaped")
		queue_free()


# Moves the bars and progress fill on screen to match the values.
func _apply_visuals():
	fish_zone.position.y = fish_zone_y * TRACK_HEIGHT
	player_bar.position.y = player_y * TRACK_HEIGHT
	progress_fill.size.y = (progress / 100.0) * TRACK_HEIGHT
	progress_fill.position.y = TRACK_HEIGHT - progress_fill.size.y
