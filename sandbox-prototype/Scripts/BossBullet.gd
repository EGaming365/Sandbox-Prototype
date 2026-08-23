class_name BossBullet
extends Node2D

const ENABLED := true
const LIFETIME := 4.0
const BASE_HIT_RADIUS := 7.0

var direction: Vector2 = Vector2.ZERO
var speed: float = 260.0
var damage: int = 1
var visual_scale: float = 1.0
var hit_radius: float = BASE_HIT_RADIUS
var _timer: float = 0.0
var _sprite: Sprite2D

func _init(tex: Texture2D, dir: Vector2, spd: float, dmg: int = 1, vscale: float = 1.0) -> void:
	direction = dir
	speed = spd
	damage = dmg
	visual_scale = vscale
	hit_radius = BASE_HIT_RADIUS * vscale
	_sprite = Sprite2D.new()
	_sprite.texture = tex
	_sprite.scale = Vector2(vscale, vscale)
	add_child(_sprite)

func _process(delta: float) -> void:
	if not ENABLED:
		queue_free()
		return
	_timer += delta
	if _timer >= LIFETIME:
		queue_free()
		return
	global_position += direction * speed * delta
	rotation = direction.angle()
	if _check_wall_hit():
		queue_free()
		return
	_check_hit()

func _check_wall_hit() -> bool:
	var cave_gen: Node = get_tree().root.get_node_or_null("Scene/CaveWorldGen")
	if not cave_gen or not cave_gen.has_method("is_tile_solid"):
		return false
	return cave_gen.is_tile_solid(global_position)

func _check_hit() -> void:
	for p in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(p):
			continue
		if global_position.distance_to((p as Node2D).global_position) > hit_radius:
			continue
		if bool(p.get("is_invulnerable")):
			continue
		var scene_node := get_tree().root.get_node_or_null("Scene")
		if scene_node and scene_node.has_method("apply_damage_to_player"):
			scene_node.apply_damage_to_player(p, damage, null)
		elif p.has_method("defend_enemy_attack"):
			p.defend_enemy_attack(damage, null)
		elif p.has_method("take_damage"):
			p.take_damage(damage)
		queue_free()
		return
