extends CharacterBody2D

@export var speed = 450
@onready var anim = $AnimatedSprite2D

func _enter_tree():
	set_multiplayer_authority(name.to_int())

func _physics_process(_delta):
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
