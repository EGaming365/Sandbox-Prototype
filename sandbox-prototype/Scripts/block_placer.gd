extends Node

const GRID_SIZE = 64
const PLACE_RANGE = 300.0

var preview: Node2D = null
var current_item: String = ""
var current_texture: Texture2D = null
var placed_blocks: Dictionary = {}
var next_block_id: int = 0

func _ready():
	preview = get_tree().root.get_node_or_null("Scene/BuildingPreview")

func _is_ui_open() -> bool:
	var inv = get_tree().root.get_node_or_null("Scene/CanvasLayer/Inventory_UI")
	var chat = get_tree().root.get_node_or_null("Scene/CanvasLayer/Chat_Box")
	return (inv != null and inv.visible) or (chat != null and chat.is_open)

func _process(_delta):
	if _is_ui_open():
		current_item = ""
		current_texture = null
		if preview:
			preview.deactivate()
		return
	var hotbar = get_tree().root.get_node_or_null("Scene/CanvasLayer/Hotbar")
	if not hotbar:
		return

	var slot_data = Inventory.slots[hotbar.current_slot - 1]
	var item = slot_data["item"]

	if BuildingManager.is_placeable(item):
		if item != current_item:
			current_item = item
			current_texture = slot_data["texture"]
			if preview:
				preview.activate(current_texture)
	else:
		if current_item != "":
			current_item = ""
			current_texture = null
			if preview:
				preview.deactivate()

func _unhandled_input(event):
	if _is_ui_open():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if current_item == "" or not preview or not preview.active:
			return
		if not preview.can_place:
			return
		var snapped = preview.get_snapped_mouse_pos()
		var rot = preview.get_current_rotation()
		_place_block(current_item, current_texture, snapped, rot)

func _place_block(item_name: String, texture: Texture2D, pos: Vector2, rot: float = 0.0):
	var scene_node = get_tree().root.get_node("Scene")
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			scene_node.host_place_block(item_name, pos, rot)
		else:
			scene_node.request_place_block.rpc_id(1, item_name, pos.x, pos.y, rot)
	else:
		scene_node.host_place_block(item_name, pos, rot)
	# Remove exactly ONE item
	var hotbar = get_tree().root.get_node_or_null("Scene/CanvasLayer/Hotbar")
	if hotbar:
		var slot_index = hotbar.current_slot - 1
		if Inventory.slots[slot_index]["count"] > 1:
			Inventory.slots[slot_index]["count"] -= 1
			Inventory.inventory_changed.emit()
		else:
			Inventory.remove_item(slot_index, false)
