extends Node2D

@onready var area = $Area2D
var wood_scene = preload("res://Scenes/wood.tscn")
var player_in_range = false
var max_hits = randi_range(4, 8)
var hits = 0
const CHOP_COOLDOWN = 0.1
static var can_chop = true

func _ready():
	add_to_group("trees")

func _on_area_2d_body_entered(body):
	if body is CharacterBody2D:
		player_in_range = true

func _on_area_2d_body_exited(body):
	if body is CharacterBody2D:
		player_in_range = false

func _input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if player_in_range and can_chop:
			var mouse_pos = get_global_mouse_position()
			var col = $CollisionShape2D
			var shape = col.shape
			var local_mouse = col.to_local(mouse_pos)
			if shape.get_rect().has_point(local_mouse):
				drop_wood()

func drop_wood():
	if not can_chop:
		return
	can_chop = false
	hits += 1
	var wood = wood_scene.instantiate()
	var angle = randf_range(0, TAU)
	var radius = randf_range(75, 95)
	radius = radius + 40
	var offset = Vector2(cos(angle), sin(angle)) * radius
	wood.position = position + offset + Vector2(0, -40)
	get_parent().add_child(wood)
	if hits >= max_hits:
		can_chop = true
		queue_free()
		return
	await get_tree().create_timer(CHOP_COOLDOWN).timeout
	can_chop = true
