extends CharacterBody2D

@export var speed = 450
@onready var anim = $AnimatedSprite2D

func _enter_tree():
	set_multiplayer_authority(name.to_int())

func _ready():
	add_to_group("players")
	$Camera2D.enabled = false
	call_deferred("_setup_camera")
	if not is_multiplayer_authority():
		collision_layer = 0
		collision_mask = 0
		$CollisionShape2D.disabled = true

func _setup_camera():
	if is_multiplayer_authority():
		$Camera2D.enabled = true
		$Camera2D.make_current()

func _physics_process(_delta):
	# Non-authority just handles animations based on velocity from synchronizer
	if not is_multiplayer_authority():
		if velocity.length() > 0:
			anim.play("walk_down")
		else:
			anim.play("idle")
		return

	var direction = Vector2.ZERO
	if Input.is_action_pressed("move_left"):
		direction.x -= 1
	if Input.is_action_pressed("move_right"):
		direction.x += 1
	if Input.is_action_pressed("move_up"):
		direction.y -= 1
	if Input.is_action_pressed("move_down"):
		direction.y += 1

	if direction.length() > 0:
		anim.play("walk_down")
	else:
		anim.play("idle")

	direction = direction.normalized()
	velocity = direction * speed
	move_and_slide()

	# Z-index vs trees
	var nearest_tree = null
	var nearest_dist = INF
	for tree in get_tree().get_nodes_in_group("trees"):
		var dist = global_position.distance_to(tree.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_tree = tree

	if nearest_tree:
		if global_position.y > nearest_tree.global_position.y:
			z_index = nearest_tree.z_index + 1
		else:
			z_index = nearest_tree.z_index - 1

	# Z-index vs other players
	for other in get_tree().get_nodes_in_group("players"):
		if other == self:
			continue
		if global_position.y > other.global_position.y:
			z_index = max(z_index, other.z_index + 1)
		else:
			z_index = min(z_index, other.z_index - 1)
