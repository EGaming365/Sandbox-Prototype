extends Control

# Node references
@onready var fish_zone = $HBoxContainer/CatchBar/FishZone
@onready var player_bar = $HBoxContainer/CatchBar/PlayerBar
@onready var progress_fill = $HBoxContainer/ProgressBar/ProgressFill
@onready var fish_label = $FishLabel
@onready var hold_button = $HoldButton

const TRACK_HEIGHT = 280.0
const PLAYER_H = 36.0

var holding := false
var player_y := 0.5       # 0 = top, 1 = bottom (normalized)
var fish_zone_y := 0.3    # normalized
var fish_vel := 0.0
var progress := 0.0

# These get set externally when you spawn the minigame
var fish_zone_height := 80.0
var fish_speed := 1.0
var progress_rate := 1.0
var escape_rate := 1.0

signal fish_caught
signal fish_escaped

func setup(fish_data: Dictionary):
	fish_label.text = fish_data.name + "  [" + fish_data.rarity + "]"
	fish_zone_height = fish_data.zone_height
	fish_speed = fish_data.speed
	progress_rate = fish_data.progress_rate
	escape_rate = fish_data.escape_rate
	fish_zone.size.y = fish_zone_height

func _on_hold_button_button_down():
	holding = true

func _on_hold_button_button_up():
	holding = false

func _process(delta):
	_update_fish_zone(delta)
	_update_player(delta)
	_update_progress(delta)
	_apply_visuals()

func _update_fish_zone(delta):
	fish_vel += (randf() - 0.48) * fish_speed * delta * 3.5
	fish_vel *= pow(0.88, delta * 60)
	fish_vel = clamp(fish_vel, -fish_speed * 0.6, fish_speed * 0.6)
	fish_zone_y += fish_vel * delta
	var max_y = 1.0 - fish_zone_height / TRACK_HEIGHT
	fish_zone_y = clamp(fish_zone_y, 0.0, max_y)

func _update_player(delta):
	var gravity = -1.8 if holding else 2.5
	player_y += gravity * delta
	player_y = clamp(player_y, 0.0, 1.0 - PLAYER_H / TRACK_HEIGHT)

func _update_progress(delta):
	var p_top = player_y
	var p_bot = player_y + PLAYER_H / TRACK_HEIGHT
	var f_top = fish_zone_y
	var f_bot = fish_zone_y + fish_zone_height / TRACK_HEIGHT
	var overlap = max(0.0, min(p_bot, f_bot) - max(p_top, f_top))
	var in_zone = overlap > 0.3

	if in_zone:
		progress += progress_rate * delta * 35
	else:
		progress -= escape_rate * delta * 25

	progress = clamp(progress, 0.0, 100.0)

	if progress >= 100.0:
		emit_signal("fish_caught")
		queue_free()
	elif progress <= 0.0:
		emit_signal("fish_escaped")
		queue_free()

func _apply_visuals():
	fish_zone.position.y = fish_zone_y * TRACK_HEIGHT
	player_bar.position.y = player_y * TRACK_HEIGHT
	progress_fill.size.y = (progress / 100.0) * TRACK_HEIGHT
	# anchor progress fill to the bottom
	progress_fill.position.y = TRACK_HEIGHT - progress_fill.size.y
	
