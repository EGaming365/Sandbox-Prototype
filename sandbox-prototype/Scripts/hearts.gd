extends Control

var heart_texture = preload("res://Assets/heart.png")
var hearts = []
var max_health = 10
var current_health = 10

func _ready():
	_build_hearts()

func _build_hearts():
	var hbox = HBoxContainer.new()
	hbox.position = Vector2(610, 930)
	hbox.add_theme_constant_override("separation", 2)
	add_child(hbox)
	for i in max_health:
		var tex = TextureRect.new()
		tex.texture = heart_texture
		tex.custom_minimum_size = Vector2(25, 25)
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.expand_mode = TextureRect.EXPAND_FIT_WIDTH
		hearts.append(tex)
		hbox.add_child(tex)

func update_hearts(health: int):
	current_health = health
	for i in hearts.size():
		hearts[i].modulate = Color(1, 1, 1, 1) if i < health else Color(0.2, 0.2, 0.2, 0.5)
