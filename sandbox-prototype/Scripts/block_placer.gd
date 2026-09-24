# Block placement controller.
# Watches the selected hotbar item, drives the placement preview and places the block when the player right clicks.

extends Node

# Size of one building grid cell in pixels. The preview script does the actual snapping.
const GRID_SIZE = 64
# Maximum placement distance in pixels. The preview script is what enforces it.
const PLACE_RANGE = 300.0

# Ghost image that shows where the block will go.
var preview: Node2D = null
# Name of the placeable item currently held, or an empty string.
var current_item: String = ""
# Picture of the placeable item currently held.
var current_texture: Texture2D = null
# Reserved for tracking placed blocks. The scene currently keeps the real list.
var placed_blocks: Dictionary = {}
# Reserved for numbering placed blocks. The scene currently hands out the real IDs.
var next_block_id: int = 0


# Find the placement preview in the scene.
func _ready():
	preview = get_tree().root.get_node_or_null("Scene/BuildingPreview")


# Returns true when the inventory or chat is open, so building is paused.
func _is_ui_open() -> bool:
	var inventory_ui = get_tree().root.get_node_or_null("Scene/CanvasLayer/Inventory_UI")
	var chat_box = get_tree().root.get_node_or_null("Scene/CanvasLayer/Chat_Box")
	return (inventory_ui != null and inventory_ui.visible) or (chat_box != null and chat_box.get("is_open"))


# Every frame, checks the held hotbar item and turns the preview on or off.
func _process(_delta):
	# Cancel any placement while a menu is open.
	if _is_ui_open():
		current_item = ""
		current_texture = null
		if preview:
			preview.deactivate()
		return
	# Use up the item from the selected hotbar slot.
	var hotbar = get_tree().root.get_node_or_null("Scene/CanvasLayer/Hotbar")
	if not hotbar:
		return

	# Look at the item in the currently selected hotbar slot.
	var slot_data = Inventory.slots[hotbar.current_slot - 1]
	var item = slot_data["item"]

	# Start previewing a new item, or clear the preview when the item is not placeable.
	if BuildingManager.is_placeable(item):
		if item != current_item:
			current_item = item
			current_texture = slot_data["texture"]
			if preview:
				preview.activate(current_texture, item)
	else:
		if current_item != "":
			current_item = ""
			current_texture = null
			if preview:
				preview.deactivate()


# Places the block when the player right clicks with a valid preview.
func _unhandled_input(event):
	if _is_ui_open():
		return
	if event.is_action_pressed("right_click"):
		if current_item == "" or not preview or not preview.active:
			return
		# Do nothing if the preview says the spot is blocked.
		if not preview.can_place:
			return
		# Read the grid aligned position, offset and rotation from the preview.
		var snapped_position = preview.get_place_pos()
		var place_offset = preview.get_place_offset()
		var rotation_angle = preview.get_current_rotation()
		_place_block(current_item, current_texture, snapped_position + place_offset, rotation_angle)


# Places a block on the host (asking the host when this is a client) and uses up one item.
func _place_block(item_name: String, texture: Texture2D, world_position: Vector2, rotation_angle: float = 0.0):
	# Only the host creates blocks, so clients send a request.
	var scene_node = get_tree().root.get_node("Scene")
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			scene_node.host_place_block(item_name, world_position, rotation_angle)
		else:
			scene_node.request_place_block.rpc_id(1, item_name, world_position.x, world_position.y, rotation_angle)
	else:
		scene_node.host_place_block(item_name, world_position, rotation_angle)
	# Remove exactly ONE item
	var hotbar = get_tree().root.get_node_or_null("Scene/CanvasLayer/Hotbar")
	if hotbar:
		var slot_index = hotbar.current_slot - 1
		# Reduce the stack by one, or remove the item completely if it was the last one.
		if Inventory.slots[slot_index]["count"] > 1:
			Inventory.slots[slot_index]["count"] -= 1
			Inventory.inventory_changed.emit()
		else:
			Inventory.remove_item(slot_index, false)
