extends GPUParticles2D


func _ready():
	amount = 300
	lifetime = 0.8
	explosiveness = 0.0
	randomness = 0.0
	fixed_fps = 0
	local_coords = true
	position = Vector2(960, -50)
	var particle_material = ParticleProcessMaterial.new()
	particle_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	particle_material.emission_box_extents = Vector3(960, 1, 1)
	particle_material.direction = Vector3(0, 1, 0)
	particle_material.spread = 0.0
	particle_material.gravity = Vector3(0, 980, 0)
	particle_material.initial_velocity_min = 800.0
	particle_material.initial_velocity_max = 1200.0
	particle_material.scale_min = 1.5
	particle_material.scale_max = 2.5
	process_material = particle_material
	var raindrop_image = Image.create(2, 16, false, Image.FORMAT_RGBA8)
	raindrop_image.fill(Color.WHITE)
	texture = ImageTexture.create_from_image(raindrop_image)
	modulate = Color(0.8, 0.9, 1.0, 0.5)
	emitting = false


func _process(_delta):
	var cave_gen = get_tree().root.get_node_or_null("Scene/CaveWorldGen")
	var in_cave: bool = cave_gen != null and cave_gen.get("in_cave") == true
	var weather = get_tree().root.get_node_or_null("Scene/Weather")
	if in_cave:
		emitting = false
		return
	if not weather:
		emitting = false
		return
	var current_weather = weather.get("current_weather")
	if current_weather == null:
		emitting = false
		return
	var weather_type = weather.get("WeatherType")
	if weather_type == null:
		emitting = false
		return
	var should_rain: bool = current_weather == weather_type.RAIN or \
		current_weather == weather_type.THUNDER or \
		current_weather == weather_type.THUNDERSTORM
	emitting = should_rain


func set_storm_intensity(is_heavy: bool):
	var particle_material = process_material as ParticleProcessMaterial
	if not particle_material:
		return
	if is_heavy:
		amount = 600
		particle_material.initial_velocity_min = 1100.0
		particle_material.initial_velocity_max = 1500.0
		particle_material.scale_min = 2.0
		particle_material.scale_max = 3.5
		modulate = Color(0.231, 0.314, 0.44, 0.85)
	else:
		amount = 300
		particle_material.initial_velocity_min = 800.0
		particle_material.initial_velocity_max = 1200.0
		particle_material.scale_min = 1.5
		particle_material.scale_max = 2.5
		modulate = Color(0.548, 0.778, 1.0, 0.5)
