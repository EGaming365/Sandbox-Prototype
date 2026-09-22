# Floor item for the stone fishing rod.
# Sits in the world, is picked up by the local player and despawns after a while. Durability is stored as the item's count.

extends Node2D

# Unique ID given by the scene so every player refers to the same floor item.
@export var item_id: int = -1
# Uses left on the tool when it is picked up.
@export var durability: int = 100

# Image used for this tool in the inventory.
var stone_fishing_rod_texture = preload("res://Assets/Stone_Fishing_Rod.png")

# Seconds before an uncollected item disappears.
const DESPAWN_TIME = 300.0
# Distance in pixels within which the local player picks the item up.
const PICKUP_RANGE = 40.0
# Seconds between pickup checks, so the distance is not tested every frame.
const CHECK_INTERVAL = 0.1

# Set once the item has been collected so it cannot be collected twice.
var _picked_up: bool = false
# Counts down until the item despawns.
var despawn_timer: float = 0.0
# Counts down until the next pickup check.
var check_timer: float = 0.0


# Hides the item while it is set up and randomises its timers so items do not all despawn together.
func _ready():
	visible = false
	z_index = 2
	despawn_timer = DESPAWN_TIME + randf_range(-30.0, 30.0)
	check_timer = randf_range(0.0, CHECK_INTERVAL)
	# Wait one frame before making the item visible.
	await get_tree().process_frame
	visible = true


# Handles despawning and lets the local player pick the tool up when close enough.
func _process(delta):
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
	# The hotbar knows which player belongs to this game instance.
	var hotbar = get_tree().root.get_node_or_null("Scene/CanvasLayer/Hotbar")
	if not hotbar:
		return
	# Stop if there is no local player yet.
	var player = hotbar.get_local_player()
	if not player:
		return
	# Pick the tool up only when the local player is within range.
	if player.global_position.distance_to(global_position) <= PICKUP_RANGE:
		# Leave the tool on the floor if there is no room for it.
		if _is_inventory_full("Stone Fishing Rod"):
			return
		# Mark the tool as collected before touching the inventory.
		_picked_up = true
		# Add the tool with its durability stored as the item's count.
		Inventory.add_item_with_count("Stone Fishing Rod", stone_fishing_rod_texture, durability)
		var scene_node = get_tree().root.get_node("Scene")
		# Remove the tool from the world. The host tells everyone, a client asks the host, and a single player game removes it directly.
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
	# Tools cannot stack, so they need a completely empty slot.
	if Inventory.non_stackable_items.has(item_name):
		for slot in Inventory.slots:
			if slot["item"] == "":
				return false
		for slot in Inventory.inv_slots:
			if slot["item"] == "":
				return false
		return true
	# Other items may also join an existing stack that is below the limit of 99.
	for slot in Inventory.slots:
		if slot["item"] == "" or (slot["item"] == item_name and slot["count"] < 99):
			return false
	for slot in Inventory.inv_slots:
		if slot["item"] == "" or (slot["item"] == item_name and slot["count"] < 99):
			return false
	return true
