# Tree in the world.
# Players chop it with an axe. Each hit drops wood and the tree disappears after enough hits.
# In windy weather the top of the tree sways using a small shader.

extends Node2D
# Detects when a player is close enough to chop the tree.
@onready var area = $Area2D
# True while a player is standing near the tree.
var player_in_range = false
# The player who is currently in range.
var player_in_range_node = null
# Number of hits needed to fell the tree, chosen at random from 4 to 8.
var max_hits = randi_range(4, 8)
# Hits the tree has taken so far.
var hits = 0
# ID used to remove the tree everywhere in multiplayer, or -1 if it has none.
var tree_id: int = -1
# ID of the tree in the environment generator, used to remove it and stop it respawning.
var env_id: String = ""
# Y position of the base of the trunk.
var trunk_base_y: float = 0.0

# Cached reference to the chat box.
var _chat_box: Node = null
# Cached reference to the inventory screen.
var _inventory_ui: Node = null
# Cached reference to the hotbar.
var _hotbar: Node = null
# Reserved for the sway animation.
var _sway_time: float = 0.0
# Material that holds the sway shader.
var _sway_material: ShaderMaterial = null
# Reserved to record whether the tree is currently swaying.
var _is_swaying: bool = false

# How far the top of the tree moves sideways in wind.
@export var sway_strength: float = 4.0
# How quickly the tree sways.
@export var sway_speed: float = 1.8
# Turns the swaying effect on or off.
@export var sway_enabled: bool = true


# Registers the tree in the trees group, reads its environment ID and finds the UI nodes it needs.
func _ready():
	add_to_group("trees")
	z_index = 2
	trunk_base_y = global_position.y
	if has_meta("env_id"):
		env_id = str(get_meta("env_id"))
	_chat_box = get_tree().root.get_node_or_null("Scene/CanvasLayer/Chat_Box")
	_inventory_ui = get_tree().root.get_node_or_null("Scene/CanvasLayer/Inventory_UI")
	_hotbar = get_tree().root.get_node_or_null("Scene/CanvasLayer/Hotbar")
	_setup_sway_shader()


# Animates the sway and handles the player clicking the tree with an axe while standing nearby.
func _process(delta):
	_update_sway(delta)
	if not player_in_range:
		return
	# Ignore chopping while the chat or inventory is open.
	if is_instance_valid(_chat_box) and "is_open" in _chat_box and _chat_box.is_open:
		return
	if is_instance_valid(_inventory_ui) and _inventory_ui.visible:
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	# The mouse must be over the tree's collision area.
	var mouse_world_position = get_global_mouse_position()
	var collision_node = $CollisionShape2D
	var shape = collision_node.shape
	var local_mouse = collision_node.to_local(mouse_world_position)
	if not shape.get_rect().has_point(local_mouse):
		return
	# Read which item is held in the selected hotbar slot.
	var held_item = ""
	if is_instance_valid(_hotbar):
		var slot = Inventory.slots[_hotbar.current_slot - 1]
		held_item = slot["item"]
	var scene_node = get_tree().root.get_node("Scene")
	# Wait for the chopping cooldown to finish.
	var local_player = _hotbar.get_local_player() if is_instance_valid(_hotbar) else null
	if local_player and (local_player.chop_cooldown_timer > 0 or local_player.attack_cooldown > 0):
		return
	# Clients ask the host to chop the tree, while the host or a single player chops it directly.
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		scene_node.request_chop_env_tree.rpc_id(1, env_id, held_item)
		if local_player:
			local_player.start_chop_cooldown(_get_chop_time(held_item))
	else:
		if local_player:
			local_player.start_chop_cooldown(_get_chop_time(held_item))
		do_chop(multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1, held_item)


# Returns how many seconds one chop takes with the given tool. Better axes are faster.
func _get_chop_time(held_item: String) -> float:
	match held_item:
		"Stone Axe":
			return 1.0
		"Axe":
			return 1.5
		_:
			return 2.0


# Registers one hit, drops wood near the tree, wears down the axe and removes the tree when it is felled.
func do_chop(chopper_id: int = 1, held_item: String = ""):
	var scene_node = get_tree().root.get_node("Scene")
	# Only axes lose durability.
	var has_axe = held_item in ["Axe", "Stone Axe"]
	hits += 1
	# Choose a random spot around the tree for the wood to land.
	var angle = randf_range(0, TAU)
	var radius = randf_range(75, 95) + 40
	var drop_pos = global_position + Vector2(cos(angle), sin(angle)) * radius + Vector2(0, -40)
	scene_node.host_spawn_floor_item(drop_pos, "Wood", 1)
	if has_axe:
		_consume_axe(chopper_id)
	# Remove the tree using the correct system for generated trees, tracked trees and loose trees.
	if hits >= max_hits:
		if env_id != "":
			if multiplayer.has_multiplayer_peer():
				scene_node.sync_destroy_env_object.rpc(env_id)
			else:
				scene_node.sync_destroy_env_object(env_id)
		elif tree_id != -1:
			if multiplayer.has_multiplayer_peer():
				scene_node.sync_remove_tree.rpc(tree_id)
			else:
				scene_node.remove_tree(tree_id)
		else:
			queue_free()


# Uses up one point of axe durability, or tells the chopping player's game to do it.
func _consume_axe(chopper_id: int):
	var scene_node = get_tree().root.get_node("Scene")
	if multiplayer.has_multiplayer_peer() and chopper_id != multiplayer.get_unique_id():
		scene_node.consume_axe_on_client.rpc_id(chopper_id)
		return
	var hotbar = get_tree().root.get_node_or_null("Scene/CanvasLayer/Hotbar")
	if not hotbar:
		return
	var slot_index = hotbar.current_slot - 1
	var current = Inventory.slots[slot_index]
	if current["item"] in ["Axe", "Stone Axe"]:
		current["count"] -= 1
		if current["count"] <= 0:
			Inventory.remove_item(slot_index, false)
		else:
			Inventory.inventory_changed.emit()


# A player walked into range.
func _on_area_2d_body_entered(body):
	if body is CharacterBody2D:
		player_in_range = true
		player_in_range_node = body


# A player walked out of range.
func _on_area_2d_body_exited(body):
	if body is CharacterBody2D:
		player_in_range = false
		player_in_range_node = null


# Creates a shader that bends the top of the tree sideways, more strongly further from the trunk base, and applies it to the tree sprite.
func _setup_sway_shader():
	# The shader code is written inline. It moves each vertex sideways with a sine wave, weighted by its height on the sprite.
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;

uniform float sway_amount = 0.0;
uniform float sway_speed = 1.8;
uniform float time_offset = 0.0;
uniform float trunk_base_uv = 0.85;

void vertex() {
	float t = TIME * sway_speed + time_offset;
	float influence = clamp(1.0 - (UV.y / trunk_base_uv), 0.0, 1.0);
	influence = pow(influence, 1.6);
	VERTEX.x += sin(t) * sway_amount * influence;
	VERTEX.x += sin(t * 2.3 + 0.9) * sway_amount * 0.18 * influence;
}
"""
	_sway_material = ShaderMaterial.new()
	_sway_material.shader = shader
	_sway_material.set_shader_parameter("sway_amount", 0.0)
	_sway_material.set_shader_parameter("sway_speed", sway_speed)
	_sway_material.set_shader_parameter("time_offset", randf_range(0.0, TAU))
	_sway_material.set_shader_parameter("trunk_base_uv", 0.85)

	# Find the tree's sprite so the shader can be applied to it.
	var sprite = null
	for child in get_children():
		if child is Sprite2D or child is AnimatedSprite2D:
			sprite = child
			break

	if sprite:
		sprite.material = _sway_material


# Eases the sway amount up in windy weather and back to zero otherwise.
func _update_sway(delta: float):
	if not _sway_material or not sway_enabled:
		return
	var weather_node = get_tree().root.get_node_or_null("Scene/Weather")
	# Weather type 4 is wind.
	var windy := false
	if weather_node and "current_weather" in weather_node:
		windy = weather_node.current_weather == 4
	var target_sway := sway_strength if windy else 0.0
	var current_sway := _sway_material.get_shader_parameter("sway_amount") as float
	var new_sway := move_toward(current_sway, target_sway, delta * 3.5)
	_sway_material.set_shader_parameter("sway_amount", new_sway)
