# Floor item for wood planks.
# Sits in the world showing its stack size, is picked up by the local player and despawns after a while.

extends Node2D

# Unique ID given by the scene so every player refers to the same floor item.
@export var item_id: int = -1
# Durability value, which this stackable item does not use.
@export var durability: int = 1
# Name of this item in the inventory.
var item_type: String = "Wood Plank"
# Number of items in this pile.
var stack_count: int = 1
# Image used for this item in the inventory.
var plank_texture = preload("res://Assets/Wood_Planks.png")
# Set once the item has been collected so it cannot be collected twice.
var _picked_up: bool = false
# Seconds before an uncollected item disappears.
const DESPAWN_TIME = 300.0
# Distance in pixels within which the local player picks the item up.
const PICKUP_RANGE = 40.0
# Seconds between pickup checks, so the distance is not tested every frame.
const CHECK_INTERVAL = 0.1
# Counts down until the item despawns.
var despawn_timer: float = 0.0
# Counts down until the next pickup check.
var check_timer: float = 0.0
# Small label that shows the stack size above the item.
var label: Label = null


# Hides the item while it is set up, randomises its timers so items do not all despawn together, and creates the stack label.
func _ready():
	visible = false
	z_index = 2
	despawn_timer = DESPAWN_TIME + randf_range(-30.0, 30.0)
	check_timer = randf_range(0.0, CHECK_INTERVAL)
	# Create a white label with a black outline that shows the number of items in the pile.
	label = Label.new()
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	label.position = Vector2(-8, -24)
	label.z_index = 100
	# Top level means the label ignores the item's own position and rotation.
	label.top_level = true
	add_child(label)
	_update_label()
	# Wait one frame before making the item visible.
	await get_tree().process_frame
	visible = true


# Shows the stack size above the item. Nothing is shown for a stack of one.
func _update_label():
	if label:
		label.text = str(stack_count) if stack_count > 1 else ""
		label.global_position = global_position + Vector2(-8, -24)


# Keeps the label in place, handles despawning and picks the item up when the local player is close.
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
	# The scene stores which player belongs to this game instance.
	var scene_node = get_tree().root.get_node_or_null("Scene")
	if not scene_node or not scene_node.local_player:
		return
	# Do nothing unless the local player is within pick up range.
	if scene_node.local_player.global_position.distance_to(global_position) > PICKUP_RANGE:
		return
	# Leave the pile on the floor if there is no room for it.
	if _is_inventory_full("Wood Plank"):
		return
	_picked_up = true
	# Move as much of the pile as possible into the inventory. The result is how many items actually fitted.
	var added = Inventory.batch_add_item("Wood Plank", plank_texture, stack_count)
	# Nothing fitted, so leave the pile on the floor.
	if added <= 0:
		_picked_up = false
		return
	# Only part of the pile fitted, so keep the remainder on the floor with the new count.
	if added < stack_count:
		stack_count -= added
		_picked_up = false
		_update_label()
		Inventory._queue_emit()
		return
	Inventory._queue_emit()
	# Remove the pile from the world. The host tells everyone, a client asks the host, and a single player game removes it directly.
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			scene_node.sync_remove_floor_item.rpc(item_id)
		else:
			scene_node.request_remove_floor_item.rpc_id(1, item_id)
	else:
		scene_node.remove_floor_item(item_id)


# Removes the item when its timer runs out. Only the host, or a single player game, removes it so everyone stays in sync.
func _do_despawn():
	var scene_node = get_tree().root.get_node_or_null("Scene")
	if not scene_node:
		return
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			scene_node.sync_remove_floor_item.rpc(item_id)
	else:
		scene_node.remove_floor_item(item_id)


# Returns true when the item has nowhere to go in the hotbar or unlocked inventory slots.
func _is_inventory_full(item_name: String) -> bool:
	for slot in Inventory.slots:
		if slot["item"] == "" or (slot["item"] == item_name and slot["count"] < 99):
			return false
	for i in Inventory.unlocked_inv_slots:
		var slot = Inventory.inv_slots[i]
		if slot["item"] == "" or (slot["item"] == item_name and slot["count"] < 99):
			return false
	return true
