# Projectile fired by a boss.
# Flies in a straight line, disappears after a few seconds or when it hits a wall, and damages the first player it touches.

class_name BossBullet
extends Node2D

# Master switch that removes bullets immediately when turned off.
const ENABLED := true
# Seconds before a bullet disappears on its own.
const LIFETIME := 4.0
# Hit radius in pixels when the bullet is at normal size.
const BASE_HIT_RADIUS := 7.0

# Unit vector the bullet travels along.
var direction: Vector2 = Vector2.ZERO
# Travel speed in pixels per second.
var speed: float = 260.0
# Damage dealt to a player it hits.
var damage: int = 1
# Size multiplier for the picture and the hit radius.
var visual_scale: float = 1.0
# Distance from the bullet within which a player is hit.
var hit_radius: float = BASE_HIT_RADIUS
# Seconds since the bullet was created.
var _age_seconds: float = 0.0
# Picture of the bullet.
var _sprite: Sprite2D


# Creates a bullet with the given picture, direction, speed, damage and size.
func _init(bullet_texture: Texture2D, travel_direction: Vector2, travel_speed: float, hit_damage: int = 1, sprite_scale: float = 1.0) -> void:
	direction = travel_direction
	speed = travel_speed
	damage = hit_damage
	visual_scale = sprite_scale
	# Bigger bullets are easier to hit with.
	hit_radius = BASE_HIT_RADIUS * sprite_scale
	_sprite = Sprite2D.new()
	_sprite.texture = bullet_texture
	_sprite.scale = Vector2(sprite_scale, sprite_scale)
	add_child(_sprite)


# Moves the bullet each frame and removes it when it expires or hits something.
func _process(delta: float) -> void:
	if not ENABLED:
		queue_free()
		return
	_age_seconds += delta
	if _age_seconds >= LIFETIME:
		queue_free()
		return
	# Move along the direction of travel.
	global_position += direction * speed * delta
	# Turn the picture to face the direction of travel.
	rotation = direction.angle()
	if _check_wall_hit():
		queue_free()
		return
	_check_hit()


# Returns true if the bullet is currently inside a solid cave wall tile.
func _check_wall_hit() -> bool:
	var cave_gen: Node = get_tree().root.get_node_or_null("Scene/CaveWorldGen")
	if not cave_gen or not cave_gen.has_method("is_tile_solid"):
		return false
	return cave_gen.is_tile_solid(global_position)


# Damages the first player within range and then removes the bullet.
func _check_hit() -> void:
	for player_node in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(player_node):
			continue
		if global_position.distance_to((player_node as Node2D).global_position) > hit_radius:
			continue
		# Players with invulnerability frames, such as while rolling, are not hurt.
		if bool(player_node.get("is_invulnerable")):
			continue
		# Prefer the scene's damage function so damage is handled correctly in multiplayer, then fall back to the player's own functions.
		var scene_node := get_tree().root.get_node_or_null("Scene")
		if scene_node and scene_node.has_method("apply_damage_to_player"):
			scene_node.apply_damage_to_player(player_node, damage, null)
		elif player_node.has_method("defend_enemy_attack"):
			player_node.defend_enemy_attack(damage, null)
		elif player_node.has_method("take_damage"):
			player_node.take_damage(damage)
		queue_free()
		return
