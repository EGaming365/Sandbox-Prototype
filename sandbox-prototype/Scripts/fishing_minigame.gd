extends Control

var fish_zone: Control
var player_bar: Control
var progress_fill: Control
var fish_label: Label
var hold_button: Button

const TRACK_HEIGHT = 400.0
const PLAYER_H = 48.0

var holding := false
var player_y := 0.5
var player_vel := 0.0
var fish_zone_y := 0.3
var fish_vel := 0.0
var fish_zone_height := 80.0
var fish_speed := 1.0
var progress_rate := 1.0
var escape_rate := 1.0
var bar_speed := 1.0
var effective_player_h: float = PLAYER_H

signal fish_caught
signal fish_escaped

var progress := 50.0
var _ready_to_process: bool = false

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

func setup(fish_data: Dictionary):
	var display_name: String = fish_data.name
	effective_player_h = PLAYER_H * fish_data.get("player_bar", 1.0)
	var mutations: Array = fish_data.get("mutations", [])
	if "Albino" in mutations:
		display_name = "Albino " + display_name
		fish_zone.modulate = Color(0.78, 0.78, 0.78)
	var player_bar_mult: float = fish_data.get("player_bar", 1.0)
	var effective_player_h: float = PLAYER_H * player_bar_mult
	player_bar.size.y = effective_player_h

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
	var weight_str := ""
	if weight > 0.0:
		if weight < 1.0:
			weight_str = "  •  " + str(int(weight * 1000)) + "g"
		else:
			weight_str = "  •  " + str(snappedf(weight, 0.01)) + "kg"
	fish_label.text = display_name + size_tag + "  [" + fish_data.rarity + "]" + weight_str
	fish_zone_height = fish_data.zone_height
	fish_speed = fish_data.speed
	progress_rate = fish_data.progress_rate
	escape_rate = fish_data.escape_rate
	fish_zone.size.y = fish_zone_height
	bar_speed = fish_data.get("bar_speed", 1.0)
	_ready_to_process = true

func _on_hold_button_button_down():
	holding = true

func _on_hold_button_button_up():
	holding = false

func _process(delta):
	if not _ready_to_process:
		return
	holding = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	_update_fish_zone(delta)
	_update_player(delta)
	_update_progress(delta)
	_apply_visuals()

var fish_target_y := 0.3
var fish_move_timer: float = 0.0
var fish_move_interval: float = 1.5

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

func _update_player(delta):
	var target_vel: float = -0.35 * bar_speed if holding else 0.5 * bar_speed
	player_vel = lerp(player_vel, target_vel, delta * 6.0 * bar_speed)
	player_y += player_vel * delta
	player_y = clamp(player_y, 0.0, 1.0 - effective_player_h / TRACK_HEIGHT)

func _update_progress(delta):
	var p_top := player_y
	var p_bot := player_y + effective_player_h / TRACK_HEIGHT
	var f_top := fish_zone_y
	var f_bot := fish_zone_y + fish_zone_height / TRACK_HEIGHT
	var overlap: float = max(0.0, min(p_bot, f_bot) - max(p_top, f_top))
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

func _apply_visuals():
	fish_zone.position.y = fish_zone_y * TRACK_HEIGHT
	player_bar.position.y = player_y * TRACK_HEIGHT
	progress_fill.size.y = (progress / 100.0) * TRACK_HEIGHT
	progress_fill.position.y = TRACK_HEIGHT - progress_fill.size.y
