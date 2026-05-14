extends GPUParticles2D

func _ready():
	amount = 300
	lifetime = 0.8
	explosiveness = 0.0
	randomness = 0.0
	fixed_fps = 0
	local_coords = true
	position = Vector2(960, -50)

	var mat = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(960, 1, 1)
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 0.0
	mat.gravity = Vector3(0, 980, 0)
	mat.initial_velocity_min = 800.0
	mat.initial_velocity_max = 1200.0
	mat.scale_min = 1.5
	mat.scale_max = 2.5
	process_material = mat

	var img = Image.create(2, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	texture = ImageTexture.create_from_image(img)

	modulate = Color(0.8, 0.9, 1.0, 0.5)
	emitting = false

func set_storm_intensity(heavy: bool):
	var mat = process_material as ParticleProcessMaterial
	if heavy:
		amount = 600
		mat.initial_velocity_min = 1100.0
		mat.initial_velocity_max = 1500.0
		mat.scale_min = 2.0
		mat.scale_max = 3.5
		modulate = Color(0.231, 0.314, 0.44, 0.85)
	else:
		amount = 300
		mat.initial_velocity_min = 800.0
		mat.initial_velocity_max = 1200.0
		mat.scale_min = 1.5
		mat.scale_max = 2.5
		modulate = Color(0.548, 0.778, 1.0, 0.5)
