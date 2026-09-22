# Floor item for a top hat fish.
# A caught fish lying in the world. Its size depends on its weight and the local player can pick it up.
# The weight in grams is stored in the durability value.

extends Node2D

# Unique ID given by the scene so every player refers to the same floor item.
@export var item_id: int = -1
# For fish this stores the weight in grams.
@export var durability: int = 1
# Name of the fish, which decides its picture and weight.
@export var item_type: String = "Tophat Fish"

# Maps the fish name, and its albino version, to the picture used for it.
var _texture_map: Dictionary = {
	"Tophat Fish":       "res://Assets/Fish_Tophat_Raw.png",
	"Albino Tophat Fish":"res://Assets/Fish_Tophat_Raw.png",
}

# Typical weight of this fish in kilograms.
const BASE_WEIGHTS_KG: Dictionary = {
	"Tophat Fish": 0.6,
}

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


# Hides the fish while it is set up, stores its name in metadata and randomises its timers.
func _ready():
	visible = false
	z_index = 2
	# Store the fish name so it can be read back when the fish is picked up.
	set_meta("item_name", item_type)
	despawn_timer = DESPAWN_TIME + randf_range(-30.0, 30.0)
	check_timer = randf_range(0.0, CHECK_INTERVAL)
	await get_tree().process_frame
	_apply_visuals()
	visible = true


# Sizes and tints the fish sprite from its weight so heavier fish look bigger.
func _apply_visuals():
	# The weight is stored in grams, so convert it to kilograms.
	var weight_kg: float = durability / 1000.0
	# Choose a sprite size for the weight, from 0.55 for tiny fish up to 2.0 for fish of 10 kg or more.
	var scale_factor: float
	if weight_kg >= 10.0:
		scale_factor = 2.0
	elif weight_kg >= 5.0:
		scale_factor = 1.6
	elif weight_kg >= 2.0:
		scale_factor = 1.35
	elif weight_kg >= 1.0:
		scale_factor = 1.0
	elif weight_kg >= 0.5:
		scale_factor = 0.85
	elif weight_kg >= 0.2:
		scale_factor = 0.7
	else:
		scale_factor = 0.55
	# Apply the size and the picture if the sprite node exists.
	var sprite := $Sprite2D
	if sprite:
		sprite.scale = Vector2(scale_factor, scale_factor)
		var tex_path: String = _texture_map.get(item_type, "res://Assets/Fish_Tophat_Raw.png")
		sprite.texture = load(tex_path)
		# Albino fish are drawn slightly greyed out.
		if item_type.begins_with("Albino "):
			sprite.modulate = Color(0.82, 0.82, 0.82)


# Handles despawning and lets the local player pick the fish up when close enough.
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
	var player = hotbar.get_local_player()
	if not player:
		return
	if player.global_position.distance_to(global_position) <= PICKUP_RANGE:
		# Read the fish name back from the item's metadata.
		var name_to_pick := _get_item_name()
		# Leave the fish on the floor if there is no room.
		if _is_inventory_full(name_to_pick):
			return
		_picked_up = true
		var tex_path: String = _texture_map.get(name_to_pick, "res://Assets/Fish_Tophat_Raw.png")
		var tex: Texture2D = load(tex_path)
		# Try the hotbar first, then the unlocked inventory slots.
		var placed := false
		# Use the first empty hotbar slot. The count holds the weight in grams.
		for i in Inventory.slots.size():
			if Inventory.slots[i]["item"] == "":
				Inventory.slots[i]["item"] = name_to_pick
				Inventory.slots[i]["count"] = durability
				Inventory.slots[i]["texture"] = tex
				Inventory.discover(name_to_pick)
				Inventory._queue_emit()
				placed = true
				break
		# The hotbar was full, so use the first empty unlocked inventory slot instead.
		if not placed:
			for i in Inventory.unlocked_inv_slots:
				if Inventory.inv_slots[i]["item"] == "":
					Inventory.inv_slots[i]["item"] = name_to_pick
					Inventory.inv_slots[i]["count"] = durability
					Inventory.inv_slots[i]["texture"] = tex
					Inventory.discover(name_to_pick)
					Inventory._queue_emit()
					break
		# Remove the fish from the world. The host tells everyone, a client asks the host, and a single player game removes it directly.
		var scene_node = get_tree().root.get_node("Scene")
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


# Returns the fish name stored in the item's metadata.
func _get_item_name() -> String:
	return get_meta("item_name", item_type)


# Returns true when the item has nowhere to go in the hotbar or unlocked inventory slots.
func _is_inventory_full(item_name: String) -> bool:
	for slot in Inventory.slots:
		if slot["item"] == "":
			return false
	for i in Inventory.unlocked_inv_slots:
		if Inventory.inv_slots[i]["item"] == "":
			return false
	return true
