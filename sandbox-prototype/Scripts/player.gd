extends CharacterBody2D

@export var speed = 450
@export var synced_velocity : Vector2 = Vector2.ZERO
@onready var anim = $AnimatedSprite2D
var nearest_tree = null
var tree_check_timer : float = 0.0

func _enter_tree():
	if multiplayer.has_multiplayer_peer():
		set_multiplayer_authority(name.to_int())
	else:
		set_multiplayer_authority(1)

func _ready():
	add_to_group("players")
	$Camera2D.enabled = false
	call_deferred("_setup_camera")
	if not multiplayer.has_multiplayer_peer():
		collision_layer = 1
		collision_mask = 1
		$CollisionShape2D.disabled = false
	elif not is_multiplayer_authority():
		collision_layer = 0
		collision_mask = 0
		$CollisionShape2D.disabled = true

func _setup_camera():
	if not multiplayer.has_multiplayer_peer():
		$Camera2D.enabled = true
		$Camera2D.make_current()
	elif is_multiplayer_authority():
		$Camera2D.enabled = true
		$Camera2D.make_current()

func _physics_process(delta):
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		if synced_velocity.length() > 0:
			anim.play("walk_down")
		else:
			anim.play("idle")

	if not multiplayer.has_multiplayer_peer() or is_multiplayer_authority():
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
		synced_velocity = velocity
		move_and_slide()

	# Z-index runs for ALL players on ALL machines, trees only
	tree_check_timer += delta
	if tree_check_timer >= 0.2:
		tree_check_timer = 0.0
		var nearest_dist = INF
		nearest_tree = null
		for tree in get_tree().get_nodes_in_group("trees"):
			var dist = global_position.distance_to(tree.global_position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest_tree = tree

	if nearest_tree and is_instance_valid(nearest_tree):
		if global_position.y > nearest_tree.global_position.y:
			z_index = nearest_tree.z_index + 1
		else:
			z_index = max(1, nearest_tree.z_index - 1)
