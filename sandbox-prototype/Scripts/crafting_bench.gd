extends Node2D
@export var item_id: int = -1
@export var durability: int = 1
var crafting_bench_texture: Texture2D
var _picked_up: bool = false
const DESPAWN_TIME = 300.0
const PICKUP_RANGE = 40.0
const CHECK_INTERVAL = 0.1
var despawn_timer: float = 0.0
var check_timer: float = 0.0

func _ready():
	crafting_bench_texture = Crafting.bench_texture
	$Sprite2D.texture = crafting_bench_texture
	z_as_relative = false
	z_index = int(global_position.y) % 1000
	despawn_timer = DESPAWN_TIME + randf_range(-30.0, 30.0)
	check_timer = randf_range(0.0, CHECK_INTERVAL)

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
	var scene_node = get_tree().root.get_node_or_null("Scene")
	if not scene_node or not scene_node.local_player:
		return
	if scene_node.local_player.global_position.distance_to(global_position) <= PICKUP_RANGE:
		if _is_inventory_full("Crafting_Bench"):
			return
		_picked_up = true
		Inventory.batch_add_item("Crafting_Bench", crafting_bench_texture, durability)
		Inventory.request_inventory_update()
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
	if Inventory.non_stackable_items.has(item_name):
		for slot in Inventory.slots:
			if slot["item"] == "":
				return false
		for slot in Inventory.inv_slots:
			if slot["item"] == "":
				return false
		return true
	for slot in Inventory.slots:
		if slot["item"] == "" or (slot["item"] == item_name and slot["count"] < 99):
			return false
	for slot in Inventory.inv_slots:
		if slot["item"] == "" or (slot["item"] == item_name and slot["count"] < 99):
			return false
	return true
