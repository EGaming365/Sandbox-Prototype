extends Control
@onready var weather_icon: TextureRect = $WeatherIcon
@onready var hunger_bar: ProgressBar = $HBoxContainer/HungerBar
@onready var thirst_bar: ProgressBar = $HBoxContainer/ThirstBar
@onready var time_icon: TextureRect = $TimeIcon
@onready var event_icon: TextureRect = $EventIcon
@onready var season_icon: TextureRect = $SeasonIcon
@onready var season_info: Label = $SeasonInfo
@onready var event_info: Label = $EventInfo
@onready var weather_info: Label = $WeatherInfo

var tex_clear = preload("res://Assets/Weather_Clear.png")
var tex_rain = preload("res://Assets/Weather_Rain.png")
var tex_thunder = preload("res://Assets/Weather_Thunder.png")
var tex_thunderstorm = preload("res://Assets/Weather_Thunderstorm.png")
var tex_day = preload("res://Assets/Time_Day.png")
var tex_night = preload("res://Assets/Time_Night.png")
var tex_morning = preload("res://Assets/Time_Morning.png")
var tex_evening = preload("res://Assets/Time_Evening.png")
var tex_aurora_borealis = preload("res://Assets/Event_Aurora_Borealis.png")
var tex_spring = preload("res://Assets/Season_Spring.png")
var tex_summer = preload("res://Assets/Season_Summer.png")
var tex_autumn = preload("res://Assets/Season_Autumn.png")
var tex_winter = preload("res://Assets/Season_Winter.png")

var hunger: float = 100.0
var thirst: float = 100.0
var hunger_drain: float = 0.2
var thirst_drain: float = 0.25
var damage_timer: float = 0.0
var damage_interval: float = 3.0
var thirst_refill_rate: float = 18.0
var death_message_sent: bool = false
var regen_interval: float = 5.0
var regen_amount: int = 1
var regen_hunger_min: float = 30.0
var regen_thirst_min: float = 20.0
var regen_timer: float = 0.0
var regen_max_health: float = 10.0
var idle_drain_multiplier: float = 0.1
var healing_drain_multiplier: float = 10.0
var aurora_glow_rect: ColorRect
var _aurora_glow_phase: float = 0.0

func _ready():
	hunger_bar.max_value = 100
	hunger_bar.value = 100
	thirst_bar.max_value = 100
	thirst_bar.value = 100
	aurora_glow_rect = null
	season_info.visible = false
	event_info.visible = false
	weather_info.visible = false
	$EventDisplay.visible = false
	_setup_icon_hover()
	await get_tree().process_frame
	var weather = get_tree().root.get_node_or_null("Scene/Weather")
	if weather:
		set_season_icon(weather.current_season)
	season_info.add_theme_color_override("font_outline_color", Color.BLACK)
	season_info.add_theme_constant_override("outline_size", 5)
	event_info.add_theme_color_override("font_outline_color", Color.BLACK)
	event_info.add_theme_constant_override("outline_size", 5)
	weather_info.add_theme_color_override("font_outline_color", Color.BLACK)
	weather_info.add_theme_constant_override("outline_size", 5)
	$EffectLabel.add_theme_color_override("font_color", Color.GREEN)
	$EffectLabel.add_theme_color_override("font_outline_color", Color.BLACK)
	$EffectLabel.add_theme_constant_override("outline_size", 5)
	$EffectLabel.visible = false

func _setup_icon_hover():
	weather_icon.mouse_filter = Control.MOUSE_FILTER_PASS
	time_icon.mouse_filter = Control.MOUSE_FILTER_PASS
	event_icon.mouse_filter = Control.MOUSE_FILTER_PASS
	season_icon.mouse_filter = Control.MOUSE_FILTER_PASS

	weather_icon.mouse_entered.connect(func(): _show_info(weather_info, _get_weather_text()))
	weather_icon.mouse_exited.connect(func(): weather_info.visible = false)
	event_icon.mouse_entered.connect(func(): _show_info(event_info, _get_event_text()))
	event_icon.mouse_exited.connect(func(): event_info.visible = false)
	season_icon.mouse_entered.connect(func(): _show_info(season_info, _get_season_text()))
	season_icon.mouse_exited.connect(func(): season_info.visible = false)
	$WeatherDispay.mouse_entered.connect(func(): _show_info(weather_info, _get_weather_text()))
	$WeatherDispay.mouse_exited.connect(func(): weather_info.visible = false)
	$EventDisplay.mouse_entered.connect(func(): _show_info(event_info, _get_event_text()))
	$EventDisplay.mouse_exited.connect(func(): event_info.visible = false)
	$SeasonDisplay.mouse_entered.connect(func(): _show_info(season_info, _get_season_text()))
	$SeasonDisplay.mouse_exited.connect(func(): season_info.visible = false)

func _show_info(label: Label, text: String):
	if text == "":
		label.visible = false
		return
	label.text = text
	label.visible = true

func _get_weather_text() -> String:
	var weather = get_tree().root.get_node_or_null("Scene/Weather")
	if not weather:
		return ""
	match weather.current_weather:
		0: return "Clear"
		1: return "Rain"
		2: return "Thunder"
		3: return "Thunderstorm"
	return ""

func _get_time_text() -> String:
	var weather = get_tree().root.get_node_or_null("Scene/Weather")
	if not weather:
		return ""
	var t = weather.time_of_day
	if t >= 0.65 and t < 0.82:
		return "Evening"
	elif t >= 0.35 and t < 0.65:
		return "Day"
	elif t >= 0.2 and t < 0.35:
		return "Morning"
	return "Night"

func _get_event_text() -> String:
	var weather = get_tree().root.get_node_or_null("Scene/Weather")
	if weather and weather.aurora_active:
		return "Aurora Borealis"
	return ""

func _get_season_text() -> String:
	var weather = get_tree().root.get_node_or_null("Scene/Weather")
	if not weather:
		return ""
	match weather.current_season:
		0: return "Spring"
		1: return "Summer"
		2: return "Autumn"
		3: return "Winter"
	return ""

func _process(delta):
	var weather_node = get_tree().root.get_node_or_null("Scene/Weather")
	if weather_node:
		match weather_node.current_weather:
			0: weather_icon.texture = tex_clear
			1: weather_icon.texture = tex_rain
			2: weather_icon.texture = tex_thunder
			3: weather_icon.texture = tex_thunderstorm
		var t = weather_node.time_of_day
		if t >= 0.65 and t < 0.82:
			time_icon.texture = tex_evening
		elif t >= 0.35 and t < 0.65:
			time_icon.texture = tex_day
		elif t >= 0.2 and t < 0.35:
			time_icon.texture = tex_morning
		else:
			time_icon.texture = tex_night
	var event_display = $EventDisplay
	if event_display:
		var weather = get_tree().root.get_node_or_null("Scene/Weather")
		event_display.visible = weather != null and weather.aurora_active

	var world_gen = get_tree().root.get_node_or_null("Scene/WorldGen")
	var in_water = false
	var player: CharacterBody2D = null
	for p in get_tree().get_nodes_in_group("players"):
		if p is CharacterBody2D:
			if not multiplayer.has_multiplayer_peer() or p.is_multiplayer_authority():
				player = p
				break

	if player and world_gen and world_gen.has_method("is_water_at"):
		in_water = world_gen.is_water_at(player.global_position)

	var is_moving = player != null and player.velocity.length() > 0
	var is_healing = player != null and hunger >= regen_hunger_min and thirst >= regen_thirst_min and player.synced_health < player.max_health

	var drain_multiplier: float
	if is_healing:
		drain_multiplier = healing_drain_multiplier
	elif is_moving:
		drain_multiplier = 1.0
	else:
		drain_multiplier = idle_drain_multiplier

	hunger -= hunger_drain * drain_multiplier * delta
	if in_water:
		thirst += thirst_refill_rate * delta
	else:
		thirst -= thirst_drain * drain_multiplier * delta
	hunger = clamp(hunger, 0.0, 100.0)
	thirst = clamp(thirst, 0.0, 100.0)

	if is_instance_valid(hunger_bar):
		hunger_bar.value = hunger
	if is_instance_valid(thirst_bar):
		thirst_bar.value = thirst

	# luck block goes here, before the early return
	var luck_multi: float = 1.0
	var w = get_tree().root.get_node_or_null("Scene/Weather")
	if w:
		if w.aurora_active:
			luck_multi *= 9.0
		if w.current_weather == w.WeatherType.RAIN or \
		   w.current_weather == w.WeatherType.THUNDER or \
		   w.current_weather == w.WeatherType.THUNDERSTORM:
			luck_multi *= 1.5
	if luck_multi > 1.0:
		var luck_str: String
		if luck_multi == float(int(luck_multi)):
			luck_str = str(int(luck_multi))
		else:
			luck_str = str(snappedf(luck_multi, 0.1))
		$EffectLabel.text = "Luck: " + luck_str + "x"
		$EffectLabel.visible = true
	else:
		$EffectLabel.visible = false

	if hunger >= regen_hunger_min and thirst >= regen_thirst_min:
		regen_timer += delta
		if regen_timer >= regen_interval:
			regen_timer = 0.0
			if player:
				player.heal(regen_amount)
	else:
		regen_timer = 0.0

	if hunger > 0.0 and thirst > 0.0:
		damage_timer = 0.0
		death_message_sent = false
		return

	if player == null:
		return

	damage_timer += delta
	if damage_timer < damage_interval:
		return

	damage_timer = 0.0
	var death_cause := ""
	if hunger <= 0.0 and thirst <= 0.0:
		death_cause = "hunger and thirst"
	elif thirst <= 0.0:
		death_cause = "thirst"
	else:
		death_cause = "hunger"

	var prev_health = player.synced_health
	player.take_damage(1)
	if not death_message_sent and (player.synced_health <= 0 or prev_health <= 1):
		death_message_sent = true
		_send_death_message(death_cause)

	if aurora_glow_rect:
		var weather = get_tree().root.get_node_or_null("Scene/Weather")
		var aurora_on = weather and weather.aurora_active
		if aurora_on:
			_aurora_glow_phase += delta * 0.8
			var glow_tints = [
				Color(0.18, 0.85, 0.65, 0.5),
				Color(0.45, 0.0, 0.9, 0.5),
				Color(0.0, 0.7, 0.6, 0.5),
				Color(0.5, 0.0, 1.0, 0.5),
			]
			var idx_a = int(_aurora_glow_phase) % glow_tints.size()
			var idx_b = (idx_a + 1) % glow_tints.size()
			var t = fmod(_aurora_glow_phase, 1.0)
			var pulse = 0.3 + 0.2 * sin(_aurora_glow_phase * 3.0)
			var blended = glow_tints[idx_a].lerp(glow_tints[idx_b], t)
			aurora_glow_rect.color = Color(blended.r, blended.g, blended.b, pulse)
		else:
			aurora_glow_rect.color = aurora_glow_rect.color.lerp(Color(0, 0, 0, 0), delta * 2.0)
			

func _send_death_message(cause: String):
	var chat = get_tree().root.get_node_or_null("Scene/CanvasLayer/Chat_Box")
	if not chat:
		return
	var player_name = Steam.getFriendPersonaName(Steam.getSteamID()) if (multiplayer.has_multiplayer_peer() and Steam != null) else "Player"
	var msg = player_name + " died of " + cause
	if multiplayer.has_multiplayer_peer():
		chat._broadcast_message.rpc(msg)
	else:
		chat._add_message(msg)

func reset_stats():
	hunger = 100.0
	thirst = 100.0
	hunger_bar.value = 100.0
	thirst_bar.value = 100.0

func _create_aurora_glow():
	aurora_glow_rect = ColorRect.new()
	aurora_glow_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	aurora_glow_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	var event_display = $EventDisplay
	var glow_parent = event_display.get_parent()
	glow_parent.add_child(aurora_glow_rect)
	glow_parent.move_child(aurora_glow_rect, event_display.get_index())
	aurora_glow_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func set_aurora_icon(active: bool):
	event_icon.texture = tex_aurora_borealis if active else null
	if active and not aurora_glow_rect:
		_create_aurora_glow()

func set_season_icon(season: int):
	match season:
		0: season_icon.texture = tex_spring
		1: season_icon.texture = tex_summer
		2: season_icon.texture = tex_autumn
		3: season_icon.texture = tex_winter
