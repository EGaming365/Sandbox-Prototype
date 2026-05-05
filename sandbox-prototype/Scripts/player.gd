extends CharacterBody2D

@export var speed = 450
@export var synced_velocity : Vector2 = Vector2.ZERO
@onready var anim = $AnimatedSprite2D
var chop_cooldown_timer: float = 0.0
var chop_cooldown_max: float = 1.5

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
	# Cooldown bar runs for authority player only
	if is_multiplayer_authority() or not multiplayer.has_multiplayer_peer():
		if chop_cooldown_timer > 0:
			chop_cooldown_timer = max(chop_cooldown_timer - delta, 0.0)
			var pct = chop_cooldown_timer / chop_cooldown_max if chop_cooldown_max > 0 else 0.0
			var cursor = get_tree().root.get_node_or_null("Scene/CanvasLayer/Cursor")
			if cursor:
				cursor.show_cooldown(pct)

	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		if synced_velocity.length() > 0:
			anim.play("walk_down")
		else:
			anim.play("idle")
		z_index = int(global_position.y)
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
	synced_velocity = velocity
	move_and_slide()
	z_index = int(global_position.y)

func start_chop_cooldown(duration: float):
	chop_cooldown_max = duration
	chop_cooldown_timer = duration
