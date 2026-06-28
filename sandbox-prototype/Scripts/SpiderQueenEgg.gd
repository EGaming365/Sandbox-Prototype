extends Node2D

const ENABLED := true

@export var hatch_time: float = 10.0
@export var enemy_scene: PackedScene
@export var hp: int = 30

var _timer: float = 0.0

func _ready() -> void:
	if not ENABLED:
		queue_free()
		return
	add_to_group("boss_eggs")

func _process(delta: float) -> void:
	if not ENABLED:
		return
	_timer += delta
	var pulse := 1.0 + 0.08 * sin(_timer * TAU / hatch_time * 4.0)
	scale = Vector2(pulse, pulse)
	queue_redraw()
	if _timer >= hatch_time:
		_hatch()

func _draw() -> void:
	var pct := clampf(_timer / hatch_time, 0.0, 1.0)
	var col := Color(0.15, 0.08, 0.0).lerp(Color(0.6, 0.1, 0.0), pct)
	draw_circle(Vector2.ZERO, 12.0, col)
	draw_arc(Vector2.ZERO, 12.0, 0.0, TAU, 32, Color(0.05, 0.05, 0.05), 2.0)
	var web_col := Color(0.7, 0.7, 0.7, 0.5)
	draw_line(Vector2(-12, 0), Vector2(12, 0), web_col, 1.0)
	draw_line(Vector2(0, -12), Vector2(0, 12), web_col, 1.0)
	draw_line(Vector2(-8, -8), Vector2(8, 8), web_col, 1.0)
	draw_line(Vector2(8, -8), Vector2(-8, 8), web_col, 1.0)

func take_damage(amount: int) -> void:
	hp -= amount
	if hp <= 0:
		queue_free()

func _hatch() -> void:
	if enemy_scene:
		var e := enemy_scene.instantiate()
		get_parent().add_child(e)
		e.global_position = global_position
	queue_free()
