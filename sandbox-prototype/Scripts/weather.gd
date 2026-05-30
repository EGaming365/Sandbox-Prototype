extends Node2D

enum WeatherType {
	CLEAR,
	RAIN,
	THUNDER,
	THUNDERSTORM,
	WIND,
	FOGGY,
	MISTY
}

@export var lightning_render_padding: float = 500.0
@export var lightning_flash_enabled: bool = true
@export var lightning_min_seconds: float = 25.0
@export var lightning_max_seconds: float = 60.0
@export var lightning_hit_radius: float = 36.0
@export var lightning_kill_damage: int = 9999
@export var lightning_spawn_radius: float = 1500.0
@export var lightning_bolt_height: float = 2200.0
@export var lightning_min_strike_gap: float = 50.0
@export var min_strike_count: float = 1
@export var max_strike_count: float = 3

@export var rain_drop_count: int = 420
@export var rain_min_speed: float = 620.0
@export var rain_max_speed: float = 900.0
@export var rain_slant: float = -12.0
@export var rain_alpha: float = 0.62
@export var fog_clear_radius: float = 170.0
@export var fog_fade_radius: float = 430.0
@export var fog_max_alpha: float = 1.0
@export var mist_clear_radius: float = 250.0
@export var mist_fade_radius: float = 620.0
@export var mist_max_alpha: float = 0.62
@export var wind_particle_count: int = 950
@export var wind_min_speed: float = 650.0
@export var wind_max_speed: float = 1200.0
@export var wind_gust_min_seconds: float = 6.0
@export var wind_gust_max_seconds: float = 12.0

@export var day_length_seconds: float = 1350.0
@export var weather_min_seconds: float = 450.0
@export var weather_max_seconds: float = 1350.0
@export var initial_weather: WeatherType = WeatherType.CLEAR
@export var clear_days_before_event: int = 5

var current_weather: WeatherType = WeatherType.CLEAR
var time_of_day: float = 0.5
var weather_timer: float = 0.0
var lightning_timer: float = 0.0
var lightning_alpha: float = 0.0
var clear_day_count: int = 0
var last_day_integer: int = 0
var aurora_active: bool = false
var day_event: String = ""
var day_event_timer: float = 0.0
var _was_night: bool = false
var _aurora_phase: float = 0.0
var _aurora_fade: float = 0.0
var _weather_initialized: bool = false

var rng := RandomNumberGenerator.new()
var canvas_modulate: CanvasModulate
var lightning_flash: ColorRect
var lightning_flash_layer: CanvasLayer
var rain_particles: GPUParticles2D = null
var aurora_overlay: ColorRect
var aurora_overlay_layer: CanvasLayer
var fog_overlay: ColorRect
var fog_overlay_layer: CanvasLayer
var fog_material: ShaderMaterial
var wind_particles: GPUParticles2D
var wind_layer: CanvasLayer
var wind_gust_timer: float = 0.0
var wind_direction: Vector2 = Vector2.RIGHT

var current_season: int = 0
var total_days_elapsed: int = 0
const DAYS_PER_SEASON: int = 20

func _ready():
	rng.randomize()
	current_season = rng.randi() % 4
	_create_day_night()
	_create_lightning_flash()
	call_deferred("_create_rain")
	call_deferred("_create_aurora_overlay")
	call_deferred("_create_fog_overlay")
	call_deferred("_create_wind_particles")
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		_set_weather(initial_weather)
		weather_timer = rng.randf_range(weather_min_seconds, weather_max_seconds)
	else:
		_set_weather(current_weather)
	_weather_initialized = true

func _create_aurora_overlay():
	aurora_overlay_layer = CanvasLayer.new()
	aurora_overlay_layer.layer = 109
	aurora_overlay = ColorRect.new()
	aurora_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	aurora_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	aurora_overlay.color = Color(0.0, 0.0, 0.0, 0.0)
	aurora_overlay_layer.add_child(aurora_overlay)
	get_tree().root.add_child(aurora_overlay_layer)

func _create_fog_overlay():
	fog_overlay_layer = CanvasLayer.new()
	fog_overlay_layer.layer = 0
	fog_overlay_layer.follow_viewport_enabled = false
	fog_overlay = ColorRect.new()
	fog_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fog_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fog_overlay.color = Color.WHITE
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform vec2 player_screen_pos = vec2(960.0, 540.0);
uniform float clear_radius = 260.0;
uniform float fade_radius = 620.0;
uniform float fog_alpha = 0.0;
uniform float distortion_strength = 0.0;
uniform float time = 0.0;
uniform vec4 fog_color : source_color = vec4(0.58, 0.60, 0.58, 1.0);

void fragment() {
	float dist_to_player = distance(FRAGCOORD.xy, player_screen_pos);
	float edge = smoothstep(clear_radius, fade_radius, dist_to_player);
	vec2 wobble = vec2(
		sin(FRAGCOORD.y * 0.028 + time * 1.7),
		cos(FRAGCOORD.x * 0.021 + time * 1.25)
	) * distortion_strength;
	vec3 warped = texture(screen_texture, SCREEN_UV + wobble).rgb;
	vec3 color = mix(warped, fog_color.rgb, clamp(fog_alpha, 0.0, 1.0));
	COLOR = vec4(color, edge * fog_alpha);
}
"""
	fog_material = ShaderMaterial.new()
	fog_material.shader = shader
	fog_overlay.material = fog_material
	fog_overlay_layer.add_child(fog_overlay)
	get_tree().root.add_child(fog_overlay_layer)

func _create_wind_particles():
	wind_layer = CanvasLayer.new()
	wind_layer.layer = 0
	wind_layer.follow_viewport_enabled = false
	wind_particles = GPUParticles2D.new()
	wind_particles.name = "WindParticles"
	wind_particles.amount = wind_particle_count
	wind_particles.lifetime = 2.0
	wind_particles.explosiveness = 0.0
	wind_particles.randomness = 0.45
	wind_particles.fixed_fps = 0
	wind_particles.local_coords = true
	wind_particles.emitting = false
	wind_particles.visibility_rect = Rect2(-600, -600, 4000, 3000)
	var img = Image.create(28, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.86, 0.9, 0.92, 0.75))
	wind_particles.texture = ImageTexture.create_from_image(img)
	var mat = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(64, 1400, 1)
	mat.direction = Vector3(1, 0, 0)
	mat.spread = 18.0
	mat.gravity = Vector3.ZERO
	mat.initial_velocity_min = wind_min_speed
	mat.initial_velocity_max = wind_max_speed
	mat.scale_min = 0.6
	mat.scale_max = 1.8
	wind_particles.process_material = mat
	wind_particles.modulate = Color(0.85, 0.9, 0.92, 0.65)
	wind_layer.add_child(wind_particles)
	get_tree().root.add_child(wind_layer)

func _process(delta):
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		_update_day_night(delta)
		_update_weather_timer(delta)
		_track_clear_days()
		if multiplayer.has_multiplayer_peer():
			sync_weather_state.rpc(current_weather, time_of_day, weather_timer)
	else:
		_apply_day_night_color()
	_update_lightning(delta)
	_update_aurora_overlay(delta)
	_update_fog_overlay(delta)
	_update_wind_particles(delta)
	_update_day_event(delta)

func _update_aurora_overlay(delta):
	if not aurora_overlay:
		return
	if aurora_active:
		_aurora_phase += delta * 0.15
		_aurora_fade = move_toward(_aurora_fade, 1.0, delta * 0.3)
		var aurora_tints = [
			Color(0.45, 0.0, 0.9),
			Color(0.0, 0.6, 0.5),
			Color(0.5, 0.0, 1.0),
			Color(0.0, 0.5, 0.6),
		]
		var idx_a = int(_aurora_phase) % aurora_tints.size()
		var idx_b = (idx_a + 1) % aurora_tints.size()
		var t = fmod(_aurora_phase, 1.0)
		var blended = aurora_tints[idx_a].lerp(aurora_tints[idx_b], t)
		aurora_overlay.color = Color(blended.r, blended.g, blended.b, 0.15 * _aurora_fade)
	else:
		_aurora_fade = move_toward(_aurora_fade, 0.0, delta * 0.3)
		aurora_overlay.color = Color(aurora_overlay.color.r, aurora_overlay.color.g, aurora_overlay.color.b, 0.15 * _aurora_fade)

func _update_fog_overlay(delta):
	if not fog_overlay or not fog_material:
		return
	var target_alpha := 0.0
	var clear_radius := fog_clear_radius
	var fade_radius := fog_fade_radius
	var fog_color := Color(0.58, 0.60, 0.58, 1.0)
	var distortion := 0.0
	if current_weather == WeatherType.FOGGY:
		target_alpha = fog_max_alpha
		fog_color = Color(0.55, 0.56, 0.55, 1.0)
	elif current_weather == WeatherType.MISTY:
		target_alpha = mist_max_alpha
		clear_radius = mist_clear_radius
		fade_radius = mist_fade_radius
		fog_color = Color(0.70, 0.74, 0.76, 1.0)
	var c := fog_overlay.color
	c.a = move_toward(c.a, target_alpha, delta * 1.5)
	fog_overlay.color = c
	var player_screen := get_viewport().get_visible_rect().size * 0.5
	var player = _get_local_player()
	if player:
		player_screen = get_viewport().get_canvas_transform() * player.global_position
	fog_material.set_shader_parameter("player_screen_pos", player_screen)
	fog_material.set_shader_parameter("clear_radius", clear_radius)
	fog_material.set_shader_parameter("fade_radius", fade_radius)
	fog_material.set_shader_parameter("fog_alpha", c.a)
	fog_material.set_shader_parameter("fog_color", fog_color)
	fog_material.set_shader_parameter("distortion_strength", distortion)
	fog_material.set_shader_parameter("time", Time.get_ticks_msec() / 1000.0)

func _update_wind_particles(delta):
	if not wind_particles:
		return
	var windy := current_weather == WeatherType.WIND
	wind_particles.emitting = windy
	if not windy:
		return
	var vp_size := get_viewport().get_visible_rect().size
	var max_dim: float = max(vp_size.x, vp_size.y) * 1.5
	wind_particles.position = vp_size * 0.5 - wind_direction * (max_dim * 0.65)
	wind_particles.rotation = wind_direction.angle()
	wind_particles.amount = wind_particle_count
	wind_gust_timer -= delta
	if wind_gust_timer <= 0.0:
		wind_gust_timer = rng.randf_range(wind_gust_min_seconds, wind_gust_max_seconds)
		var angle := rng.randf_range(0.0, TAU)
		wind_direction = Vector2(cos(angle), sin(angle)).normalized()
		var mat := wind_particles.process_material as ParticleProcessMaterial
		if mat:
			mat.direction = Vector3(1, 0, 0)
			var speed_boost := rng.randf_range(0.85, 1.35)
			mat.initial_velocity_min = wind_min_speed * speed_boost
			mat.initial_velocity_max = wind_max_speed * speed_boost
			mat.emission_box_extents = Vector3(64, max_dim * 0.7, 1)
		wind_particles.modulate = Color(0.85, 0.9, 0.92, rng.randf_range(0.45, 0.8))

func _update_day_event(delta):
	if day_event_timer <= 0.0:
		return
	day_event_timer -= delta
	if day_event_timer <= 0.0:
		day_event = ""

func _track_clear_days():
	var day_integer = int(time_of_day)
	if day_integer != last_day_integer:
		last_day_integer = day_integer
		if current_weather == WeatherType.CLEAR:
			clear_day_count += 1
		else:
			clear_day_count = 0
		total_days_elapsed += 1
		if total_days_elapsed % DAYS_PER_SEASON == 0:
			_advance_season()

func _advance_season():
	current_season = (current_season + 1) % 4
	var extras = get_tree().root.get_node_or_null("Scene/CanvasLayer/Extras")
	if extras and extras.has_method("on_season_changed"):
		extras.on_season_changed(current_season)
	var hud = get_tree().root.get_node_or_null("Scene/CanvasLayer/RightUI")
	if hud and hud.has_method("set_season_icon"):
		hud.set_season_icon(current_season)
	if multiplayer.has_multiplayer_peer():
		_sync_season.rpc(current_season)

@rpc("authority", "call_remote", "reliable")
func _sync_season(season: int):
	current_season = season
	var hud = get_tree().root.get_node_or_null("Scene/CanvasLayer/RightUI")
	if hud and hud.has_method("set_season_icon"):
		hud.set_season_icon(season)

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
	var is_night: bool = time_of_day >= 0.92 or time_of_day < 0.20
	if is_night and not _was_night:
		_was_night = true
		if not aurora_active and rng.randf() < 0.15:
			_start_aurora()
	if not is_night and _was_night:
		_was_night = false
		if aurora_active:
			_end_aurora()
	_apply_day_night_color()

func _start_aurora():
	aurora_active = true
	if rng.randf() < 0.20:
		_set_weather(WeatherType.RAIN)
	else:
		_set_weather(WeatherType.CLEAR)
	var extras = get_tree().root.get_node_or_null("Scene/CanvasLayer/Extras")
	if extras:
		extras.set_aurora(true)
	if multiplayer.has_multiplayer_peer():
		_sync_aurora.rpc(true)

func _end_aurora():
	aurora_active = false
	var extras = get_tree().root.get_node_or_null("Scene/CanvasLayer/Extras")
	if extras:
		extras.set_aurora(false)
	if multiplayer.has_multiplayer_peer():
		_sync_aurora.rpc(false)

@rpc("authority", "call_remote", "reliable")
func _sync_aurora(state: bool):
	aurora_active = state
	var extras = get_tree().root.get_node_or_null("Scene/CanvasLayer/Extras")
	if extras:
		extras.set_aurora(state)

func _apply_day_night_color():
	if not canvas_modulate:
		return
	# CanvasModulate handles ONLY colour warmth/hue tint — never brightness/darkening.
	# Darkness is handled entirely by the lighting manager's black overlay rects,
	# so torches can fully cancel it. Keeping RGB channels at 1.0 in the white ranges
	# means lit areas stay true-colour regardless of time of day.
	var morning_tint := Color(1.0, 0.88, 0.72)   # warm amber sunrise
	var day_tint     := Color(1.0, 0.98, 0.92)   # very slight warmth
	var evening_tint := Color(1.0, 0.78, 0.52)   # golden hour
	var night_tint   := Color(0.62, 0.68, 0.82)  # cool blue moonlight tint
	var tint: Color
	if time_of_day < 0.20:
		tint = night_tint
	elif time_of_day < 0.35:
		tint = night_tint.lerp(morning_tint, inverse_lerp(0.20, 0.35, time_of_day))
	elif time_of_day < 0.50:
		tint = morning_tint.lerp(day_tint, inverse_lerp(0.35, 0.50, time_of_day))
	elif time_of_day < 0.65:
		tint = day_tint
	elif time_of_day < 0.82:
		tint = day_tint.lerp(evening_tint, inverse_lerp(0.65, 0.82, time_of_day))
	elif time_of_day < 0.92:
		tint = evening_tint.lerp(night_tint, inverse_lerp(0.82, 0.92, time_of_day))
	else:
		tint = night_tint
	# Weather shifts hue only — no darkening here, lighting manager draws darkness
	match current_weather:
		WeatherType.RAIN:
			tint = tint.lerp(Color(0.78, 0.82, 0.88), 0.18)
		WeatherType.THUNDER:
			tint = tint.lerp(Color(0.70, 0.74, 0.82), 0.28)
		WeatherType.THUNDERSTORM:
			tint = tint.lerp(Color(0.55, 0.58, 0.72), 0.40)
		WeatherType.WIND:
			tint = tint.lerp(Color(0.88, 0.95, 1.0), 0.08)
		WeatherType.FOGGY:
			tint = tint.lerp(Color(0.78, 0.82, 0.78), 0.22)
		WeatherType.MISTY:
			tint = tint.lerp(Color(0.82, 0.88, 0.92), 0.14)
	canvas_modulate.color = tint

func _update_weather_timer(delta):
	weather_timer -= delta
	if weather_timer <= 0.0:
		_pick_next_weather()

func is_night() -> bool:
	return time_of_day < 0.20 or time_of_day >= 0.82

func _pick_next_weather():
	if aurora_active:
		weather_timer = rng.randf_range(weather_min_seconds, weather_max_seconds)
		return
	if clear_day_count >= clear_days_before_event:
		clear_day_count = 0
		var roll = rng.randi_range(1, 3)
		if roll == 1:
			_set_weather(WeatherType.RAIN)
		elif roll == 2:
			_set_weather(WeatherType.THUNDER)
		else:
			_set_weather(WeatherType.THUNDERSTORM)
		weather_timer = rng.randf_range(weather_min_seconds, weather_max_seconds)
		return
	var roll = rng.randi_range(1, 100)
	if roll <= 74:
		_set_weather(WeatherType.CLEAR)
	elif roll <= 86:
		_set_weather(WeatherType.RAIN)
	elif roll <= 91:
		_set_weather(WeatherType.WIND)
	elif roll <= 95:
		_set_weather(WeatherType.FOGGY)
	elif roll <= 98:
		_set_weather(WeatherType.MISTY)
	elif roll <= 99:
		_set_weather(WeatherType.THUNDER)
	else:
		_set_weather(WeatherType.THUNDERSTORM)
	if current_weather == WeatherType.CLEAR and not is_night() and rng.randf() < 0.12:
		_start_day_event("Rainbow" if rng.randf() < 0.65 else "Divine Blessing")
	weather_timer = rng.randf_range(weather_min_seconds, weather_max_seconds)

func _update_lightning(delta):
	var is_electric: bool = current_weather == WeatherType.THUNDER or current_weather == WeatherType.THUNDERSTORM
	if not is_electric:
		lightning_alpha = move_toward(lightning_alpha, 0.0, delta * 1.5)
		if lightning_flash and lightning_flash_enabled:
			lightning_flash.color = Color(1, 1, 1, lightning_alpha)
		return
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		lightning_timer -= delta
		if lightning_timer <= 0.0:
			if current_weather == WeatherType.THUNDERSTORM:
				var strike_count = rng.randi_range(min_strike_count, max_strike_count)
				var chosen_positions: Array[Vector2] = []
				var attempts := 0
				while chosen_positions.size() < strike_count and attempts < 30:
					attempts += 1
					var candidate := _get_random_lightning_world_position()
					var too_close := false
					for existing in chosen_positions:
						if candidate.distance_to(existing) < lightning_min_strike_gap:
							too_close = true
							break
					if not too_close:
						chosen_positions.append(candidate)
				for strike_pos in chosen_positions:
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
	lightning_alpha = move_toward(lightning_alpha, 0.0, delta * 1.5)
	if lightning_flash and lightning_flash_enabled:
		lightning_flash.color = Color(1, 1, 1, lightning_alpha)

@rpc("any_peer", "call_remote", "reliable")
func sync_weather_state(weather: int, synced_time: float, timer: float):
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		return
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
	bolt.width = 7.0
	bolt.default_color = Color(0.9, 0.95, 1.0, 1.0)
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
	await get_tree().create_timer(0.45).timeout
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
	for chicken in get_tree().get_nodes_in_group("chickens"):
		if not is_instance_valid(chicken):
			continue
		if chicken.global_position.distance_to(world_pos) <= lightning_hit_radius:
			chicken.take_damage(9999)

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
	if lightning_flash_enabled:
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
	var screen_rect = Rect2(cam_pos - screen_size / 2.0 - Vector2(lightning_render_padding, lightning_render_padding), screen_size + Vector2(lightning_render_padding * 2.0, lightning_render_padding * 2.0))
	return screen_rect.has_point(world_pos)

func _set_weather(new_weather: WeatherType):
	var was_raining: bool = current_weather == WeatherType.RAIN or current_weather == WeatherType.THUNDER or current_weather == WeatherType.THUNDERSTORM
	print("_set_weather called: ", new_weather, " was_raining=", was_raining, " initialized=", _weather_initialized, " aurora=", aurora_active)
	current_weather = new_weather
	var raining: bool = current_weather == WeatherType.RAIN or current_weather == WeatherType.THUNDER or current_weather == WeatherType.THUNDERSTORM
	if rain_particles:
		rain_particles.emitting = raining
		rain_particles.set_storm_intensity(current_weather == WeatherType.THUNDERSTORM)
	if _weather_initialized:
		if raining and not was_raining:
			if not aurora_active:
				_show_rain_notification("It has started raining.")
		elif not raining and was_raining:
			_show_rain_notification("The rain has stopped.")
	match current_weather:
		WeatherType.CLEAR:
			lightning_timer = 0.0
		WeatherType.RAIN:
			lightning_timer = 0.0
		WeatherType.THUNDER:
			lightning_timer = rng.randf_range(lightning_min_seconds, lightning_max_seconds)
		WeatherType.THUNDERSTORM:
			lightning_timer = rng.randf_range(1, 1)
		_:
			lightning_timer = 0.0

func _start_day_event(event_name: String):
	day_event = event_name
	day_event_timer = rng.randf_range(90.0, 180.0)
	if event_name == "Divine Blessing":
		for player in get_tree().get_nodes_in_group("players"):
			if is_instance_valid(player) and player.has_method("heal"):
				player.heal(2)
	var extras = get_tree().root.get_node_or_null("Scene/CanvasLayer/Extras")
	if extras and extras.has_method("show_day_event_notification"):
		extras.show_day_event_notification(event_name)
	else:
		_show_rain_notification(event_name + " has begun.")

func start_day_event(event_name: String):
	_start_day_event(event_name)
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_sync_day_event.rpc(event_name, day_event_timer)

func clear_day_event():
	day_event = ""
	day_event_timer = 0.0
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_sync_clear_day_event.rpc()

@rpc("authority", "call_remote", "reliable")
func _sync_day_event(event_name: String, timer: float):
	_start_day_event(event_name)
	day_event_timer = timer

@rpc("authority", "call_remote", "reliable")
func _sync_clear_day_event():
	day_event = ""
	day_event_timer = 0.0

func _show_rain_notification(msg: String):
	var canvas = get_tree().root.get_node_or_null("Scene/CanvasLayer")
	if not canvas:
		return
	var vp_size = get_viewport().get_visible_rect().size
	var label = Label.new()
	label.text = msg
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.z_index = 20
	label.size = Vector2(600, 40)
	label.position = Vector2(vp_size.x / 2.0 - 300.0, 60.0)
	canvas.add_child(label)
	var tween = label.create_tween()
	tween.tween_interval(4.0)
	tween.tween_property(label, "modulate:a", 0.0, 1.0)
	tween.tween_callback(label.queue_free)
