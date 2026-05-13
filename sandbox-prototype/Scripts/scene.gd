extends Node

var lobby_id: int = 0
var peer: SteamMultiplayerPeer
@export var player_scene: PackedScene
var is_host: bool = false
var is_joining: bool = false
var signals_connected: bool = false
var local_player: CharacterBody2D = null

var synced_world_seed: int = 0
var destroyed_env_objects: Dictionary = {}
var env_object_hits: Dictionary = {}

var floor_items: Dictionary = {}
var next_item_id: int = 0
var trees: Dictionary = {}
var next_tree_id: int = 0
var rocks: Dictionary = {}
var next_rock_id: int = 0
var placed_blocks: Dictionary = {}
var next_block_id: int = 0
var last_placed_texture: Texture2D = null

@onready var host_button: Button = $CanvasLayer/Host_Button
@onready var join_button: Button = $CanvasLayer/Join_Button
@onready var id_prompt: LineEdit = $CanvasLayer/id_prompt

func _ready():
	get_tree().set_auto_accept_quit(false)
	print("Steam initialised: ", Steam.steamInitEx(480))
	Steam.initRelayNetworkAccess()
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	print("My Steam ID: ", Steam.getSteamID())
	_spawn_player(1)

func _process(_delta):
	Steam.run_callbacks()
	local_player = null

	for child in get_children():
		if child is CharacterBody2D:
			if not multiplayer.has_multiplayer_peer() or child.is_multiplayer_authority():
				local_player = child
				break

func _sync_world_to_peer(peer_id: int):
	var world_gen = get_node_or_null("WorldGen")
	var env_gen = get_node_or_null("EnvironmentGen")
	if not world_gen:
		return

	if world_gen.world_seed == 0:
		world_gen.world_seed = randi()

	synced_world_seed = world_gen.world_seed

	sync_world_rpc.rpc_id(
		peer_id,
		synced_world_seed,
		world_gen.tile_size,
		world_gen.biome_noise_frequency,
		world_gen.forest_threshold,
		destroyed_env_objects,
		env_object_hits
	)

	if env_gen:
		env_gen.set_world_seed(synced_world_seed)

@rpc("authority", "call_remote", "reliable")
func sync_world_rpc(seed: int, synced_tile_size: int, frequency: float, threshold: float, destroyed: Dictionary, hits: Dictionary):
	var world_gen = get_node_or_null("WorldGen")
	var env_gen = get_node_or_null("EnvironmentGen")

	if world_gen:
		world_gen.set_world_settings(seed, synced_tile_size, frequency, threshold)

	if env_gen:
		env_gen.set_world_seed(seed)
		env_gen.apply_env_state(destroyed, hits)

@rpc("any_peer", "call_remote", "reliable")
func request_hit_env_object(env_id: String, damage: int, max_hits: int):
	if multiplayer.has_multiplayer_peer() and not is_host:
		return

	var current_hits = int(env_object_hits.get(env_id, 0)) + damage

	if current_hits >= max_hits:
		destroyed_env_objects[env_id] = true
		env_object_hits.erase(env_id)
		sync_destroy_env_object.rpc(env_id)
	else:
		env_object_hits[env_id] = current_hits
		sync_env_object_hits.rpc(env_id, current_hits)

@rpc("authority", "call_local", "reliable")
func sync_destroy_env_object(env_id: String):
	destroyed_env_objects[env_id] = true
	env_object_hits.erase(env_id)

	var env_gen = get_node_or_null("EnvironmentGen")
	if env_gen:
		env_gen.mark_destroyed(env_id)

@rpc("authority", "call_local", "reliable")
func sync_env_object_hits(env_id: String, hits: int):
	env_object_hits[env_id] = hits

	var env_gen = get_node_or_null("EnvironmentGen")
	if env_gen:
		env_gen.set_object_hits(env_id, hits)

func join_lobby(new_lobby_id: int):
	is_joining = true
	Steam.joinLobby(new_lobby_id)

func host_lobby():
	if is_host:
		return

	is_host = true
	Steam.initRelayNetworkAccess()
	await get_tree().create_timer(2.0).timeout
	Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, 4)

func _on_lobby_created(result: int, new_lobby_id: int):
	if result != 1:
		is_host = false
		return

	lobby_id = new_lobby_id
	peer = SteamMultiplayerPeer.new()
	peer.create_host()
	multiplayer.multiplayer_peer = peer

	if not signals_connected:
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_remove_player)
		signals_connected = true

	DisplayServer.clipboard_set(str(lobby_id))
	print("Lobby Created, Lobby id: ", lobby_id)
	print("Lobby ID copied to clipboard!")

	if has_node("1"):
		get_node("1").name = str(multiplayer.get_unique_id())
		get_node(str(multiplayer.get_unique_id())).set_multiplayer_authority(multiplayer.get_unique_id(), true)

	else:
		_spawn_player(multiplayer.get_unique_id())

	var world_gen = get_node_or_null("WorldGen")
	if world_gen:
		if world_gen.world_seed == 0:
			world_gen.world_seed = randi()
		synced_world_seed = world_gen.world_seed

	var env_gen = get_node_or_null("EnvironmentGen")
	if env_gen:
		env_gen.set_world_seed(synced_world_seed)

func _on_lobby_joined(new_lobby_id: int, _permissions: int, _locked: bool, response: int):
	print("Lobby joined response: ", response)
	if not is_joining:
		return

	lobby_id = new_lobby_id
	await get_tree().create_timer(1.0).timeout
	_clear_world_state()
	_clear_inventory()

	peer = SteamMultiplayerPeer.new()
	peer.server_relay = true
	peer.create_client(Steam.getLobbyOwner(lobby_id))
	multiplayer.multiplayer_peer = peer

	is_joining = false
	multiplayer.server_disconnected.connect(_on_host_disconnected)
	multiplayer.peer_disconnected.connect(_remove_player)

	if has_node("1"):
		var player = get_node("1")
		player.name = str(multiplayer.get_unique_id())
		player.set_multiplayer_authority(multiplayer.get_unique_id())

func _on_peer_connected(id: int):
	print("Peer connected on host: ", id)

	_spawn_player(id)
	_sync_world_to_peer(id)
	var weather = get_node_or_null("Weather")
	if weather:
		weather.sync_weather_state.rpc_id(id, weather.current_weather, weather.time_of_day, weather.weather_timer)

	await get_tree().create_timer(0.5).timeout

	var ids_to_send: Array[int] = []
	for child in get_children():
		if child.name.is_valid_int():
			ids_to_send.append(child.name.to_int())

	sync_players_to_client.rpc_id(id, ids_to_send)
	sync_floor_items_to_peer(id)
	sync_placed_blocks_to_peer(id)

func _on_host_disconnected():
	get_tree().quit()

func _clear_world_state():
	for item_id in floor_items:
		if is_instance_valid(floor_items[item_id]):
			floor_items[item_id].queue_free()
	floor_items.clear()

	for block_id in placed_blocks:
		if is_instance_valid(placed_blocks[block_id]):
			placed_blocks[block_id].queue_free()
	placed_blocks.clear()

	for tree_id in trees:
		if is_instance_valid(trees[tree_id]):
			trees[tree_id].queue_free()
	trees.clear()

	for rock_id in rocks:
		if is_instance_valid(rocks[rock_id]):
			rocks[rock_id].queue_free()
	rocks.clear()

	destroyed_env_objects.clear()
	env_object_hits.clear()

func _clear_inventory():
	for i in Inventory.slots.size():
		Inventory.slots[i] = {"item": "", "count": 0, "texture": null}

	for i in Inventory.inv_slots.size():
		Inventory.inv_slots[i] = {"item": "", "count": 0, "texture": null}

	Inventory.inventory_changed.emit()

@rpc("authority", "call_remote", "reliable")
func sync_players_to_client(ids: Array[int]):
	for id in ids:
		_spawn_player(id)

func _spawn_player(id: int):
	if has_node(str(id)):
		return

	if player_scene == null:
		print("ERROR: player_scene is null! Assign it in the inspector.")
		return

	var player = player_scene.instantiate()
	player.name = str(id)
	add_child(player)
	player.set_multiplayer_authority(id, true)
	player.global_position = Vector2(0, 0)


func _remove_player(id: int):
	if not has_node(str(id)):
		return

	get_node(str(id)).queue_free()

@rpc("authority", "call_remote", "reliable")
func remove_player_on_clients(id: int):
	if has_node(str(id)):
		get_node(str(id)).queue_free()

func spawn_tree_with_id(pos: Vector2) -> int:
	var id = next_tree_id
	next_tree_id += 1
	return id

func spawn_rock_with_id(pos: Vector2) -> int:
	var id = next_rock_id
	next_rock_id += 1
	return id

func remove_tree(tree_id: int):
	if trees.has(tree_id):
		if is_instance_valid(trees[tree_id]):
			trees[tree_id].queue_free()
		trees.erase(tree_id)

@rpc("authority", "call_local", "reliable")
func sync_remove_tree(tree_id: int):
	remove_tree(tree_id)

func remove_rock(rock_id: int):
	if rocks.has(rock_id):
		if is_instance_valid(rocks[rock_id]):
			rocks[rock_id].queue_free()
		rocks.erase(rock_id)

@rpc("authority", "call_local", "reliable")
func sync_remove_rock(rock_id: int):
	remove_rock(rock_id)

func host_place_block(item_name: String, pos: Vector2, rot: float = 0.0, tex: Texture2D = null) -> int:
	var id = next_block_id
	next_block_id += 1

	if multiplayer.has_multiplayer_peer():
		place_block_rpc.rpc(id, item_name, pos.x, pos.y, rot)
	else:
		_do_place_block(id, item_name, pos.x, pos.y, rot)

	return id

@rpc("authority", "call_local", "reliable")
func place_block_rpc(block_id: int, item_name: String, pos_x: float, pos_y: float, rot: float = 0.0):
	_do_place_block(block_id, item_name, pos_x, pos_y, rot)

func _do_place_block(block_id: int, item_name: String, pos_x: float, pos_y: float, rot: float = 0.0):
	if placed_blocks.has(block_id):
		return

	var block_scene = preload("res://Scenes/placed_block.tscn")
	var block = block_scene.instantiate()
	block.setup(item_name, _get_item_texture(item_name), block_id, rot)
	block.global_position = Vector2(pos_x, pos_y)
	placed_blocks[block_id] = block
	add_child(block)

func _get_item_texture(item_name: String) -> Texture2D:
	for slot in Inventory.slots:
		if slot["item"] == item_name and slot["texture"] != null:
			return slot["texture"]

	for slot in Inventory.inv_slots:
		if slot["item"] == item_name and slot["texture"] != null:
			return slot["texture"]

	return last_placed_texture

func remove_placed_block(block_id: int):
	if placed_blocks.has(block_id):
		if is_instance_valid(placed_blocks[block_id]):
			placed_blocks[block_id].queue_free()
		placed_blocks.erase(block_id)

@rpc("authority", "call_local", "reliable")
func sync_remove_placed_block(block_id: int):
	remove_placed_block(block_id)

@rpc("any_peer", "call_remote", "reliable")
func request_place_block(item_name: String, pos_x: float, pos_y: float, rot: float = 0.0):
	if not is_host:
		return

	host_place_block(item_name, Vector2(pos_x, pos_y), rot)

@rpc("any_peer", "call_remote", "reliable")
func request_break_block(block_id: int):
	if not is_host:
		return

	process_block_hit(block_id)

func sync_placed_blocks_to_peer(peer_id: int):
	for block_id in placed_blocks:
		var block = placed_blocks[block_id]
		if is_instance_valid(block):
			place_block_rpc.rpc_id(peer_id, block_id, block.item_name, block.global_position.x, block.global_position.y, block.current_rotation)

func process_block_hit(block_id: int):
	if not placed_blocks.has(block_id):
		return

	var block = placed_blocks[block_id]
	if not is_instance_valid(block):
		return

	block.hits += 1

	if block.hits >= block.max_hits:
		var drop_pos = block.global_position + Vector2(randf_range(-20, 20), randf_range(-20, 20))
		host_spawn_floor_item(drop_pos, block.item_name)

		if multiplayer.has_multiplayer_peer():
			sync_remove_placed_block.rpc(block_id)
		else:
			remove_placed_block(block_id)

@rpc("any_peer", "call_local", "reliable")
func register_block_hit(block_id: int):
	if not is_host:
		return

	process_block_hit(block_id)

func host_spawn_floor_item(pos: Vector2, item_type: String = "Wood", durability: int = 60) -> int:
	var id = next_item_id
	next_item_id += 1

	if multiplayer.has_multiplayer_peer():
		spawn_floor_item_rpc.rpc(id, pos.x, pos.y, item_type, durability)
	else:
		_do_spawn_floor_item(id, pos.x, pos.y, item_type, durability)

	return id

@rpc("any_peer", "call_local", "reliable")
func spawn_floor_item_rpc(item_id: int, pos_x: float, pos_y: float, item_type: String = "Wood", durability: int = 1):
	_do_spawn_floor_item(item_id, pos_x, pos_y, item_type, durability)

func _do_spawn_floor_item(item_id: int, pos_x: float, pos_y: float, item_type: String = "Wood", durability: int = 60):
	if floor_items.has(item_id):
		return

	var item_scene

	match item_type:
		"Wood":
			item_scene = preload("res://Scenes/wood.tscn")
		"Wood Plank":
			item_scene = preload("res://Scenes/wooden_plank.tscn")
		"Axe":
			item_scene = preload("res://Scenes/wooden_axe.tscn")
		"Sword":
			item_scene = preload("res://Scenes/wooden_sword.tscn")
		"Pickaxe":
			item_scene = preload("res://Scenes/wooden_pickaxe.tscn")
		"Crafting_Bench":
			item_scene = preload("res://Scenes/crafting_bench.tscn")
		"Stone":
			item_scene = preload("res://Scenes/stone.tscn")
		"Stone Axe":
			item_scene = preload("res://Scenes/stone_axe.tscn")
		"Stone Sword":
			item_scene = preload("res://Scenes/stone_sword.tscn")
		"Stone Pickaxe":
			item_scene = preload("res://Scenes/stone_pickaxe.tscn")
		"Wardrobe":
			item_scene = preload("res://Scenes/wardrobe.tscn")
		_:
			item_scene = preload("res://Scenes/wood.tscn")

	var item = item_scene.instantiate()
	item.item_id = item_id

	if item_type in ["Axe", "Sword", "Pickaxe", "Stone Axe", "Stone Sword", "Stone Pickaxe"]:
		item.durability = durability

	item.global_position = Vector2(pos_x, pos_y)
	floor_items[item_id] = item
	add_child(item)

@rpc("any_peer", "call_remote", "reliable")
func request_spawn_floor_item(pos_x: float, pos_y: float, item_type: String = "Wood", durability: int = 1):
	if not is_host:
		return

	host_spawn_floor_item(Vector2(pos_x, pos_y), item_type, durability)

func sync_floor_items_to_peer(peer_id: int):
	for item_id in floor_items:
		var item = floor_items[item_id]
		if is_instance_valid(item):
			var pos = item.global_position
			var script_path = item.get_script().resource_path
			var item_type = "Wood"

			if script_path.contains("wooden_plank"):
				item_type = "Wood Plank"
			elif script_path.contains("wooden_axe"):
				item_type = "Axe"
			elif script_path.contains("wooden_sword"):
				item_type = "Sword"
			elif script_path.contains("stone_axe"):
				item_type = "Stone Axe"
			elif script_path.contains("stone_sword"):
				item_type = "Stone Sword"
			elif script_path.contains("stone_pickaxe"):
				item_type = "Stone Pickaxe"
			elif script_path.contains("pickaxe"):
				item_type = "Pickaxe"
			elif script_path.contains("crafting_bench"):
				item_type = "Crafting_Bench"
			elif script_path.contains("stone"):
				item_type = "Stone"

			var dur = item.durability if item.get("durability") != null else 1
			spawn_floor_item_rpc.rpc_id(peer_id, item_id, pos.x, pos.y, item_type, dur)

func remove_floor_item(item_id: int):
	if floor_items.has(item_id):
		if is_instance_valid(floor_items[item_id]):
			floor_items[item_id].queue_free()
		floor_items.erase(item_id)

@rpc("authority", "call_local", "reliable")
func sync_remove_floor_item(item_id: int):
	remove_floor_item(item_id)

@rpc("any_peer", "call_remote", "reliable")
func request_remove_floor_item(item_id: int):
	if not is_host:
		return

	sync_remove_floor_item.rpc(item_id)

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if lobby_id != 0:
			Steam.leaveLobby(lobby_id)
		get_tree().quit()

func _on_host_button_pressed():
	host_lobby()

func _on_id_prompt_text_changed(new_text):
	join_button.disabled = new_text.length() == 0

func _on_join_button_pressed():
	var new_lobby_id = id_prompt.text.to_int()

	if lobby_id != 0:
		Steam.leaveLobby(lobby_id)
		lobby_id = 0

		if multiplayer.multiplayer_peer:
			multiplayer.multiplayer_peer = null

		is_host = false
		_clear_world_state()
		_clear_inventory()

		var to_remove = []
		for child in get_children():
			if child.name.is_valid_int():
				to_remove.append(child)

		for child in to_remove:
			child.queue_free()

		await get_tree().process_frame
		await get_tree().process_frame
		_spawn_player(1)

	join_lobby(new_lobby_id)

@rpc("any_peer", "call_remote", "reliable")
func request_deal_damage(target_id: int, amount: int):
	if not is_host:
		return

	if has_node(str(target_id)):
		var target = get_node(str(target_id))
		if target is CharacterBody2D:
			deal_damage_to_player.rpc_id(target_id, amount)

@rpc("authority", "call_remote", "reliable")
func deal_damage_to_player(amount: int):
	for child in get_children():
		if child is CharacterBody2D:
			if child.is_multiplayer_authority():
				child.take_damage(amount)
				break

@rpc("any_peer", "call_remote", "reliable")
func request_chop_env_tree(env_id: String, held_item: String):
	if not is_host:
		return

	var env_gen = get_node_or_null("EnvironmentGen")
	if not env_gen:
		return

	if not env_gen.active_objects.has(env_id):
		return

	var tree = env_gen.active_objects[env_id]
	if not is_instance_valid(tree):
		return

	var sender_id = multiplayer.get_remote_sender_id()
	tree.do_chop(sender_id, held_item)

@rpc("authority", "call_remote", "reliable")
func consume_axe_on_client():
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

@rpc("any_peer", "call_remote", "reliable")
func request_mine_env_rock(env_id: String, held_item: String):
	if not is_host:
		return

	var env_gen = get_node_or_null("EnvironmentGen")
	if not env_gen:
		return

	if not env_gen.active_objects.has(env_id):
		return

	var rock = env_gen.active_objects[env_id]
	if not is_instance_valid(rock):
		return

	var sender_id = multiplayer.get_remote_sender_id()
	rock.do_mine(sender_id, held_item)

@rpc("authority", "call_remote", "reliable")
func consume_pickaxe_on_client():
	var hotbar = get_tree().root.get_node_or_null("Scene/CanvasLayer/Hotbar")
	if not hotbar:
		return

	var slot_index = hotbar.current_slot - 1
	var current = Inventory.slots[slot_index]

	if current["item"] in ["Pickaxe", "Stone Pickaxe"]:
		current["count"] -= 1
		if current["count"] <= 0:
			Inventory.remove_item(slot_index, false)
		else:
			Inventory.inventory_changed.emit()
