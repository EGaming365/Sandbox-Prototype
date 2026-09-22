# Rain effect.
# A row of falling particles that only runs during rain weather and never inside the cave.

extends GPUParticles2D


# Sets up the particle emitter for light rain. It starts switched off.
func _ready():
	# Number of raindrops alive at once.
	amount = 300
	lifetime = 0.8
	explosiveness = 0.0
	randomness = 0.0
	fixed_fps = 0
	local_coords = true
	# Emit from just above the top of the screen.
	position = Vector2(960, -50)
	# Controls how each raindrop is created and how it moves.
	var particle_material = ParticleProcessMaterial.new()
	# Spawn drops along a wide, thin box across the screen.
	particle_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	particle_material.emission_box_extents = Vector3(960, 1, 1)
	particle_material.direction = Vector3(0, 1, 0)
	particle_material.spread = 0.0
	# Pull the drops downwards quickly.
	particle_material.gravity = Vector3(0, 980, 0)
	particle_material.initial_velocity_min = 800.0
	particle_material.initial_velocity_max = 1200.0
	particle_material.scale_min = 1.5
	particle_material.scale_max = 2.5
	process_material = particle_material
	# Create a thin white rectangle to use as the raindrop picture.
	var raindrop_image = Image.create(2, 16, false, Image.FORMAT_RGBA8)
	raindrop_image.fill(Color.WHITE)
	texture = ImageTexture.create_from_image(raindrop_image)
	# Give the drops a light blue, semi transparent tint.
	modulate = Color(0.8, 0.9, 1.0, 0.5)
	emitting = false


# Turns the rain on or off depending on the weather and whether the player is in the cave.
func _process(_delta):
	var cave_gen = get_tree().root.get_node_or_null("Scene/CaveWorldGen")
	# There is no rain underground.
	var in_cave: bool = cave_gen != null and cave_gen.get("in_cave") == true
	var weather = get_tree().root.get_node_or_null("Scene/Weather")
	if in_cave:
		emitting = false
	elif weather:
		# It rains during rain, thunder and thunderstorm weather.
		var should_rain: bool = weather.current_weather == weather.WeatherType.RAIN or \
			weather.current_weather == weather.WeatherType.THUNDER or \
			weather.current_weather == weather.WeatherType.THUNDERSTORM
		emitting = should_rain


# Switches between light rain and a heavier storm with more, faster, darker drops.
func set_storm_intensity(is_heavy: bool):
	var particle_material = process_material as ParticleProcessMaterial
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
