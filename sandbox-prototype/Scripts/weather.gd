extends Node2D

enum WeatherType {
	CLEAR,
	RAIN,
	THUNDER,
	THUNDERSTORM
}

@export var lightning_min_seconds: float = 25.0
@export var lightning_max_seconds: float = 60.0
@export var lightning_hit_radius: float = 36.0
@export var lightning_kill_damage: int = 9999
@export var lightning_spawn_radius: float = 2000.0
@export var lightning_bolt_height: float = 2200.0

@export var rain_drop_count: int = 420
@export var rain_min_speed: float = 620.0
@export var rain_max_speed: float = 900.0
@export var rain_slant: float = -12.0
@export var rain_alpha: float = 0.62

@export var day_length_seconds: float = 900.0
@export var weather_min_seconds: float = 450.0
@export var weather_max_seconds: float = 1350.0
@export var initial_weather: WeatherType = WeatherType.CLEAR

var current_weather: WeatherType = WeatherType.CLEAR
var time_of_day: float = 0.5
var weather_timer: float = 0.0
var lightning_timer: float = 0.0
var lightning_alpha: float = 0.0

var rng := RandomNumberGenerator.new()
var canvas_modulate: CanvasModulate
var lightning_flash: ColorRect
var lightning_flash_layer: CanvasLayer
var rain_particles: GPUParticles2D = null

func _ready():
	rng.randomize()
	_create_day_night()
	_create_lightning_flash()
	call_deferred("_create_rain")

	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		_set_weather(initial_weather)
		weather_timer = rng.randf_range(weather_min_seconds, weather_max_seconds)
	else:
		_set_weather(current_weather)

func _process(delta):
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		_update_day_night(delta)
		_update_weather_timer(delta)
		if multiplayer.has_multiplayer_peer():
			sync_weather_state.rpc(current_weather, time_of_day, weather_timer)
	else:
		_apply_day_night_color()

	_update_lightning(delta)

func _create_day_night():
	canvas_modulate = CanvasModulate.new()
	canvas_modulate.name = "DayNightTint"
	get_tree().root.get_node("Scene").add_child.call_deferred(canvas_modulate)

func _create_rain():
	rain_particles = get_tree().root.get_node_or_null("Scene/RainCanvas/RainParticles")
	if not rain_particles:
		print("ERROR: RainParticles not found")
		return
	rain_particles.emitting = current_weather == WeatherType.RAIN or current_weather == WeatherType.THUNDER or current_weather == WeatherType.THUNDERSTORM

func _set_weather(new_weather: WeatherType):
	current_weather = new_weather
	var raining = current_weather == WeatherType.RAIN or current_weather == WeatherType.THUNDER or current_weather == WeatherType.THUNDERSTORM
	if rain_particles:
		rain_particles.emitting = raining
		rain_particles.set_storm_intensity(current_weather == WeatherType.THUNDERSTORM)
	match current_weather:
		WeatherType.CLEAR:
			lightning_timer = 0.0
		WeatherType.RAIN:
			lightning_timer = 0.0
		WeatherType.THUNDER:
			lightning_timer = rng.randf_range(lightning_min_seconds, lightning_max_seconds)
		WeatherType.THUNDERSTORM:
			lightning_timer = rng.randf_range(1, 1)

func _create_lightning_flash():
	lightning_flash_layer = CanvasLayer.new()
	lightning_flash_layer.name = "LightningFlashLayer"
	lightning_flash_layer.layer = 110

	lightning_flash = ColorRect.new()
	lightning_flash.name = "LightningFlash"
	lightning_flash.color = Color(1, 1, 1, 0)
	lightning_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lightning_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lightning_flash.z_index = 10
	lightning_flash_layer.add_child(lightning_flash)
	get_tree().root.add_child.call_deferred(lightning_flash_layer)

func _update_day_night(delta):
	time_of_day += delta / day_length_seconds
	if time_of_day >= 1.0:
		time_of_day -= 1.0
	_apply_day_night_color()

func _apply_day_night_color():
	if not canvas_modulate:
		return

	var night_color = Color(0.16, 0.20, 0.34)
	var morning_color = Color(1.0, 0.86, 0.62)
	var day_color = Color(1.0, 0.98, 0.9)
	var evening_color = Color(0.95, 0.55, 0.35)
	var tint: Color

	if time_of_day < 0.20:
		tint = night_color
	elif time_of_day < 0.35:
		var t = inverse_lerp(0.20, 0.35, time_of_day)
		tint = night_color.lerp(morning_color, t)
	elif time_of_day < 0.65:
		tint = day_color
	elif time_of_day < 0.82:
		var t = inverse_lerp(0.65, 0.82, time_of_day)
		tint = day_color.lerp(evening_color, t)
	elif time_of_day < 0.92:
		var t = inverse_lerp(0.82, 0.92, time_of_day)
		tint = evening_color.lerp(night_color, t)
	else:
		tint = night_color

	if current_weather == WeatherType.RAIN:
		tint = tint.darkened(0.12)
	elif current_weather == WeatherType.THUNDER:
		tint = tint.darkened(0.24)
	elif current_weather == WeatherType.THUNDERSTORM:
		tint = tint.darkened(0.38)
	elif current_weather == WeatherType.THUNDERSTORM:
		tint = tint.darkened(0.38)
		tint = tint.lerp(Color(0.1, 0.13, 0.22), 0.35)

	canvas_modulate.color = tint

func _update_weather_timer(delta):
	weather_timer -= delta
	if weather_timer <= 0.0:
		_pick_next_weather()

func _pick_next_weather():
	var roll = rng.randi_range(1, 100)
	if roll <= 80:
		_set_weather(WeatherType.CLEAR)
	elif roll <= 92:
		_set_weather(WeatherType.RAIN)
	elif roll <= 98:
		_set_weather(WeatherType.THUNDER)
	else:
		_set_weather(WeatherType.THUNDERSTORM)
	weather_timer = rng.randf_range(weather_min_seconds, weather_max_seconds)

func _update_lightning(delta):
	var is_electric = current_weather == WeatherType.THUNDER or current_weather == WeatherType.THUNDERSTORM

	if not is_electric:
		lightning_alpha = move_toward(lightning_alpha, 0.0, delta * 5.0)
		if lightning_flash:
			lightning_flash.color = Color(1, 1, 1, lightning_alpha)
		return

	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		lightning_timer -= delta
		if lightning_timer <= 0.0:
			if current_weather == WeatherType.THUNDERSTORM:
				var strike_count = rng.randi_range(1, 3)
				for i in range(strike_count):
					var strike_pos = _get_random_lightning_world_position()
					if multiplayer.has_multiplayer_peer():
						lightning_strike_rpc.rpc(strike_pos.x, strike_pos.y)
					else:
						lightning_strike_rpc(strike_pos.x, strike_pos.y)
				lightning_timer = rng.randf_range(1.0, 3.0)
			else:
				var strike_pos = _get_random_lightning_world_position()
				if multiplayer.has_multiplayer_peer():
					lightning_strike_rpc.rpc(strike_pos.x, strike_pos.y)
				else:
					lightning_strike_rpc(strike_pos.x, strike_pos.y)
				lightning_timer = rng.randf_range(lightning_min_seconds, lightning_max_seconds)

	lightning_alpha = move_toward(lightning_alpha, 0.0, delta * 3.5)
	if lightning_flash:
		lightning_flash.color = Color(1, 1, 1, lightning_alpha)

@rpc("authority", "call_remote", "reliable")
func sync_weather_state(weather: int, synced_time: float, timer: float):
	current_weather = weather
	time_of_day = synced_time
	weather_timer = timer
	_set_weather(current_weather)
	_apply_day_night_color()

func _get_random_lightning_world_position() -> Vector2:
	var players = get_tree().get_nodes_in_group("players")
	players = players.filter(func(p): return is_instance_valid(p))
	if players.size() > 0:
		var target = players[rng.randi_range(0, players.size() - 1)]
		var angle = rng.randf_range(0.0, TAU)
		var distance = rng.randf_range(0.0, lightning_spawn_radius)
		return target.global_position + Vector2(cos(angle), sin(angle)) * distance
	var camera = get_viewport().get_camera_2d()
	if camera:
		return camera.get_screen_center_position()
	return Vector2.ZERO

func _show_lightning_strike(world_pos: Vector2):
	var bolt = Line2D.new()
	bolt.width = 5.0
	bolt.default_color = Color(0.8, 0.9, 1.0, 1.0)
	bolt.z_index = 100
	bolt.global_position = world_pos
	bolt.points = [
		Vector2(rng.randf_range(-60.0, 60.0), -lightning_bolt_height),
		Vector2(rng.randf_range(-45.0, 45.0), -lightning_bolt_height * 0.72),
		Vector2(rng.randf_range(-55.0, 55.0), -lightning_bolt_height * 0.45),
		Vector2(rng.randf_range(-35.0, 35.0), -lightning_bolt_height * 0.22),
		Vector2.ZERO
	]
	add_child(bolt)
	await get_tree().create_timer(0.16).timeout
	if is_instance_valid(bolt):
		bolt.queue_free()

func _kill_players_hit_by_lightning(world_pos: Vector2):
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	var scene_node = get_tree().root.get_node_or_null("Scene")
	if not scene_node:
		return

	var space = get_world_2d().direct_space_state

	for player in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(player):
			continue
		if player.global_position.distance_to(world_pos) > lightning_hit_radius:
			continue

		var query = PhysicsPointQueryParameters2D.new()
		query.position = player.global_position
		query.collision_mask = 4
		query.exclude = [player]
		var overlaps = space.intersect_point(query)
		if overlaps.size() > 0:
			continue

		var player_id = player.name.to_int()
		var player_name = Steam.getFriendPersonaName(player_id) if multiplayer.has_multiplayer_peer() else "Player"
		if player_name == "" or player_name == null:
			player_name = "Player"

		if multiplayer.has_multiplayer_peer():
			if player_id == multiplayer.get_unique_id():
				player.take_damage(lightning_kill_damage)
			else:
				scene_node.deal_damage_to_player.rpc_id(player_id, lightning_kill_damage)
		else:
			player.take_damage(lightning_kill_damage)

		var chat = get_tree().root.get_node_or_null("Scene/CanvasLayer/Chat_Box")
		if chat:
			if multiplayer.has_multiplayer_peer():
				chat._broadcast_message.rpc(player_name + " was struck by the gods")
			else:
				chat._add_message(player_name + " was struck by the gods")

func _get_local_player():
	var scene_node = get_tree().root.get_node_or_null("Scene")
	if not scene_node:
		return null
	for child in scene_node.get_children():
		if child is CharacterBody2D:
			if multiplayer.has_multiplayer_peer():
				if child.is_multiplayer_authority():
					return child
			else:
				return child
	return null

@rpc("authority", "call_local", "reliable")
func lightning_strike_rpc(pos_x: float, pos_y: float):
	var strike_pos = Vector2(pos_x, pos_y)
	lightning_alpha = rng.randf_range(0.55, 0.85)
	if _is_position_on_screen(strike_pos):
		_show_lightning_strike(strike_pos)
	_kill_players_hit_by_lightning(strike_pos)

func _is_position_on_screen(world_pos: Vector2) -> bool:
	var camera = get_viewport().get_camera_2d()
	if not camera:
		return false
	var screen_size = get_viewport().get_visible_rect().size
	var cam_pos = camera.get_screen_center_position()
	var screen_rect = Rect2(cam_pos - screen_size / 2.0, screen_size)
	return screen_rect.has_point(world_pos)
