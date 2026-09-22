# Spider Queen egg.
# Pulses and darkens as it ripens, then hatches an enemy. Players can destroy it before it hatches.

extends Node2D

# Master switch that removes the egg immediately when turned off.
const ENABLED := true

# Seconds before the egg hatches.
@export var hatch_time: float = 10.0
# Scene of the enemy spawned when the egg hatches.
@export var enemy_scene: PackedScene
# Damage the egg can take before it is destroyed.
@export var hp: int = 30

# Seconds since the egg was created.
var _hatch_timer: float = 0.0


# Register the egg in a group so other scripts can find it, or remove it if eggs are disabled.
func _ready() -> void:
	if not ENABLED:
		queue_free()
		return
	add_to_group("boss_eggs")


# Advances the hatch timer and animates the egg.
func _process(delta: float) -> void:
	if not ENABLED:
		return
	_hatch_timer += delta
	# Make the egg swell and shrink slightly, faster as it nears hatching.
	var pulse := 1.0 + 0.08 * sin(_hatch_timer * TAU / hatch_time * 4.0)
	scale = Vector2(pulse, pulse)
	queue_redraw()
	if _hatch_timer >= hatch_time:
		_hatch()


# Draws the egg as a circle that turns from dark brown to red, with a web pattern on top.
func _draw() -> void:
	# Fraction of the hatch time that has passed, from 0 to 1.
	var hatch_progress := clampf(_hatch_timer / hatch_time, 0.0, 1.0)
	var egg_colour := Color(0.15, 0.08, 0.0).lerp(Color(0.6, 0.1, 0.0), hatch_progress)
	draw_circle(Vector2.ZERO, 12.0, egg_colour)
	draw_arc(Vector2.ZERO, 12.0, 0.0, TAU, 32, Color(0.05, 0.05, 0.05), 2.0)
	# Semi transparent grey used for the web lines.
	var web_colour := Color(0.7, 0.7, 0.7, 0.5)
	draw_line(Vector2(-12, 0), Vector2(12, 0), web_colour, 1.0)
	draw_line(Vector2(0, -12), Vector2(0, 12), web_colour, 1.0)
	draw_line(Vector2(-8, -8), Vector2(8, 8), web_colour, 1.0)
	draw_line(Vector2(8, -8), Vector2(-8, 8), web_colour, 1.0)


# Reduces the egg's health and destroys it when it reaches zero.
func take_damage(amount: int) -> void:
	hp -= amount
	if hp <= 0:
		queue_free()


# Spawns the enemy at the egg's position and removes the egg.
func _hatch() -> void:
	if enemy_scene:
		var hatchling := enemy_scene.instantiate()
		get_parent().add_child(hatchling)
		hatchling.global_position = global_position
	queue_free()
