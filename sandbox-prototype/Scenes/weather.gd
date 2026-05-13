extends Node2D

enum WeatherType {
	CLEAR,
	RAIN,
	THUNDER
}

@export var day_length_seconds: float = 1800.0
@export var weather_min_seconds: float = 450.0
@export var weather_max_seconds: float = 2700.0

@export var rain_amount: int = 900
@export var rain_speed: float = 900.0

var current_weather: WeatherType = WeatherType.RAIN
var time_of_day: float = 0.5
var weather_timer: float = 0.0
var lightning_timer: float = 0.0
var lightning_alpha: float = 0.0

var rng := RandomNumberGenerator.new()
var canvas_modulate: CanvasModulate
var rain_particles: GPUParticles2D
var lightning_flash: ColorRect

func _ready():
	rng.randomize()
	_create_day_night()
	_create_rain()
	_create_lightning_flash()
	_pick_next_weather()

func _process(delta):
	_update_day_night(delta)
	_update_weather_timer(delta)
	_update_rain_position()
	_update_lightning(delta)

func _create_day_night():
	canvas_modulate = CanvasModulate.new()
	canvas_modulate.name = "DayNightTint"
	add_child(canvas_modulate)

func _create_rain():
	rain_particles = GPUParticles2D.new()
	rain_particles.name = "RainParticles"
	rain_particles.amount = rain_amount
	rain_particles.lifetime = 1.2
	rain_particles.preprocess = 1.2
	rain_particles.emitting = false

	var mat = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(900, 20, 1)
	mat.direction = Vector3(0.25, 1.0, 0.0)
	mat.initial_velocity_min = rain_speed
	mat.initial_velocity_max = rain_speed * 1.25
	mat.gravity = Vector3(0, 1600, 0)
	mat.scale_min = 0.7
	mat.scale_max = 1.2
	mat.color = Color(0.768, 0.846, 1.0, 1.0)

	rain_particles.process_material = mat
	add_child(rain_particles)


func _create_lightning_flash():
	var layer = CanvasLayer.new()
	layer.name = "LightningLayer"
	layer.layer = 50
	add_child(layer)

	lightning_flash = ColorRect.new()
	lightning_flash.name = "LightningFlash"
	lightning_flash.color = Color(1, 1, 1, 0)
	lightning_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lightning_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(lightning_flash)


func _update_day_night(delta):
	time_of_day += delta / day_length_seconds
	if time_of_day >= 1.0:
		time_of_day -= 1.0

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

	canvas_modulate.color = tint


func _update_weather_timer(delta):
	weather_timer -= delta
	if weather_timer <= 0.0:
		_pick_next_weather()


func _pick_next_weather():
	var roll = rng.randi_range(1, 100)

	if roll <= 55:
		_set_weather(WeatherType.CLEAR)
	elif roll <= 85:
		_set_weather(WeatherType.RAIN)
	else:
		_set_weather(WeatherType.THUNDER)

	weather_timer = rng.randf_range(weather_min_seconds, weather_max_seconds)


func _set_weather(new_weather: WeatherType):
	current_weather = new_weather

	match current_weather:
		WeatherType.CLEAR:
			rain_particles.emitting = false
			lightning_timer = 0.0
		WeatherType.RAIN:
			rain_particles.emitting = true
			lightning_timer = 0.0
		WeatherType.THUNDER:
			rain_particles.emitting = true
			lightning_timer = rng.randf_range(3.0, 8.0)


func _update_rain_position():
	if not rain_particles:
		return

	var camera = get_viewport().get_camera_2d()
	if camera:
		rain_particles.global_position = camera.get_screen_center_position() + Vector2(0, -360)
	else:
		rain_particles.global_position = Vector2.ZERO

	var viewport_size = get_viewport_rect().size
	var mat = rain_particles.process_material as ParticleProcessMaterial
	if mat:
		mat.emission_box_extents = Vector3(viewport_size.x * 0.65, 20, 1)


func _update_lightning(delta):
	if current_weather != WeatherType.THUNDER:
		lightning_alpha = move_toward(lightning_alpha, 0.0, delta * 5.0)
		lightning_flash.color = Color(1, 1, 1, lightning_alpha)
		return

	lightning_timer -= delta
	if lightning_timer <= 0.0:
		lightning_alpha = rng.randf_range(0.35, 0.75)
		lightning_timer = rng.randf_range(4.0, 10.0)

	lightning_alpha = move_toward(lightning_alpha, 0.0, delta * 3.5)
	lightning_flash.color = Color(1, 1, 1, lightning_alpha)
