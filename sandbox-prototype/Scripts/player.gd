extends CharacterBody2D

@export var speed = 450
@onready var anim = $AnimatedSprite2D

func _enter_tree():
	set_multiplayer_authority(name.to_int())

func _ready():
	$Camera2D.enabled = is_multiplayer_authority()

func _physics_process(_delta):
	if not is_multiplayer_authority():
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
