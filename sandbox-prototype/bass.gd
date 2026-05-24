extends Node2D

@export var item_id: int = -1
@export var durability: int = 1
@export var item_type: String = "Tophat Fish"

var _texture_map: Dictionary = {
	"Bass":             "res://Assets/Fish_Bass_Raw.png",
	"Albino Bass":      "res://Assets/Fish_Bass_Raw.png",
}

const BASE_WEIGHTS_KG: Dictionary = {
	"Bass": 1.2,
}

const DESPAWN_TIME = 300.0
const PICKUP_RANGE = 40.0
const CHECK_INTERVAL = 0.1

var _picked_up: bool = false
var despawn_timer: float = 0.0
var check_timer: float = 0.0

func _ready():
	visible = false
	z_index = 2
	set_meta("item_name", item_type)
	despawn_timer = DESPAWN_TIME + randf_range(-30.0, 30.0)
	check_timer = randf_range(0.0, CHECK_INTERVAL)
	await get_tree().process_frame
	_apply_visuals()
	visible = true

func _apply_visuals():
	var weight_kg: float = durability / 1000.0
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
	var sprite := $Sprite2D
	if sprite:
		sprite.scale = Vector2(scale_factor, scale_factor)
		var tex_path: String = _texture_map.get(item_type, "res://Assets/Fish_Bass_Raw.png")
		sprite.texture = load(tex_path)
		if item_type.begins_with("Albino "):
			sprite.modulate = Color(0.82, 0.82, 0.82)

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
	var hotbar = get_tree().root.get_node_or_null("Scene/CanvasLayer/Hotbar")
	if not hotbar:
		return
	var player = hotbar.get_local_player()
	if not player:
		return
	if player.global_position.distance_to(global_position) <= PICKUP_RANGE:
		var name_to_pick := _get_item_name()
		if _is_inventory_full(name_to_pick):
			return
		_picked_up = true
		var tex_path: String = _texture_map.get(name_to_pick, "res://Assets/Fish_Bass_Raw.png")
		var tex: Texture2D = load(tex_path)
		var placed := false
		for i in Inventory.slots.size():
			if Inventory.slots[i]["item"] == "":
				Inventory.slots[i]["item"] = name_to_pick
				Inventory.slots[i]["count"] = durability
				Inventory.slots[i]["texture"] = tex
				Inventory.discover(name_to_pick)
				Inventory._queue_emit()
				placed = true
				break
		if not placed:
			for i in Inventory.unlocked_inv_slots:
				if Inventory.inv_slots[i]["item"] == "":
					Inventory.inv_slots[i]["item"] = name_to_pick
					Inventory.inv_slots[i]["count"] = durability
					Inventory.inv_slots[i]["texture"] = tex
					Inventory.discover(name_to_pick)
					Inventory._queue_emit()
					break
		var scene_node = get_tree().root.get_node("Scene")
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

func _get_item_name() -> String:
	return get_meta("item_name", item_type)

func _is_inventory_full(item_name: String) -> bool:
	for slot in Inventory.slots:
		if slot["item"] == "":
			return false
	for i in Inventory.unlocked_inv_slots:
		if Inventory.inv_slots[i]["item"] == "":
			return false
	return true
