extends Node2D

@export var item_id: int = -1
@export var durability: int = 1
var item_type: String = "Wood Plank"
var stack_count: int = 1
var plank_texture: Texture2D
var _picked_up: bool = false
const DESPAWN_TIME = 300.0
const PICKUP_RANGE = 40.0
const CHECK_INTERVAL = 0.1
var despawn_timer: float = 0.0
var check_timer: float = 0.0
var label: Label = null

func _ready():
	z_index = 2
	plank_texture = Crafting.plank_texture
	$Sprite2D.texture = plank_texture
	despawn_timer = DESPAWN_TIME + randf_range(-30.0, 30.0)
	check_timer = randf_range(0.0, CHECK_INTERVAL)
	label = Label.new()
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	label.position = Vector2(-8, -24)
	label.z_index = 100
	label.top_level = true
	add_child(label)
	_update_label()

func _update_label():
	if label:
		label.text = str(stack_count) if stack_count > 1 else ""
		label.global_position = global_position + Vector2(-8, -24)

func _process(delta):
	if label:
		label.global_position = global_position + Vector2(-8, -24)
	if _picked_up:
		return
	despawn_timer -= delta
	if despawn_timer <= 0.0:
		_do_despawn()
		return
	check_timer -= delta
	if check_timer > 0.0:
		return
	check_timer = CHECK_INTERVAL
	var scene_node = get_tree().root.get_node_or_null("Scene")
	if not scene_node or not scene_node.local_player:
		return
	if scene_node.local_player.global_position.distance_to(global_position) > PICKUP_RANGE:
		return
	if _is_inventory_full("Wood Plank"):
		return
	_picked_up = true
	var added = Inventory.batch_add_item("Wood Plank", plank_texture, stack_count)
	if added <= 0:
		_picked_up = false
		return
	if added < stack_count:
		stack_count -= added
		_picked_up = false
		_update_label()
		Inventory._queue_emit()
		return
	Inventory._queue_emit()
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			scene_node.sync_remove_floor_item.rpc(item_id)
		else:
			scene_node.request_remove_floor_item.rpc_id(1, item_id)
	else:
		scene_node.remove_floor_item(item_id)

func _do_despawn():
	var scene_node = get_tree().root.get_node_or_null("Scene")
	if not scene_node:
		return
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			scene_node.sync_remove_floor_item.rpc(item_id)
	else:
		scene_node.remove_floor_item(item_id)

func _is_inventory_full(item_name: String) -> bool:
	for slot in Inventory.slots:
		if slot["item"] == "" or (slot["item"] == item_name and slot["count"] < 99):
			return false
	for i in Inventory.unlocked_inv_slots:
		var slot = Inventory.inv_slots[i]
		if slot["item"] == "" or (slot["item"] == item_name and slot["count"] < 99):
			return false
	return true
