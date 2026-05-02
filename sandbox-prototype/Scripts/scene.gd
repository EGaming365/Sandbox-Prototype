extends Node2D

var lobby_id : int = 0
var peer : SteamMultiplayerPeer
@export var player_scene : PackedScene
var is_host : bool = false
var is_joining : bool = false
var signals_connected : bool = false

var floor_items: Dictionary = {}
var next_item_id: int = 0

var trees: Dictionary = {}  # { tree_id: Node }
var next_tree_id: int = 0

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

func join_lobby(new_lobby_id : int):
	is_joining = true
	Steam.joinLobby(new_lobby_id)

func host_lobby():
	if is_host:
		return
	is_host = true
	Steam.initRelayNetworkAccess()
	await get_tree().create_timer(2.0).timeout
	Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, 2)

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
	else:
		_spawn_player(multiplayer.get_unique_id())

func _on_lobby_joined(new_lobby_id: int, _permissions: int, _locked: bool, response: int):
	print("Lobby joined response: ", response)
	if !is_joining:
		return
	lobby_id = new_lobby_id
	await get_tree().create_timer(1.0).timeout
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

func _on_host_disconnected():
	print("Host disconnected, leaving lobby")
	Steam.leaveLobby(lobby_id)
	lobby_id = 0
	multiplayer.multiplayer_peer = null
	is_host = false
	is_joining = false
	for item_id in floor_items:
		if is_instance_valid(floor_items[item_id]):
			floor_items[item_id].queue_free()
	floor_items.clear()
	var to_remove = []
	for child in get_children():
		print("Child found: ", child.name)
		if child.name.is_valid_int():
			to_remove.append(child)
	print("Removing ", to_remove.size(), " players")
	for child in to_remove:
		child.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_spawn_player(1)

func _on_peer_connected(id: int):
	print("Peer connected on host: ", id)
	_spawn_player(id)
	var ids_to_send: Array[int] = []
	for child in get_children():
		if child.name.is_valid_int():
			ids_to_send.append(child.name.to_int())
	sync_players_to_client.rpc_id(id, ids_to_send)
	sync_floor_items_to_peer(id)
	sync_trees_to_peer(id)

@rpc("authority", "call_remote", "reliable")
func sync_players_to_client(ids: Array[int]):
	for id in ids:
		_spawn_player(id)

func _spawn_player(id: int):
	if has_node(str(id)):
		print("Player ", id, " already exists, skipping")
		return
	print("Spawning player with id: ", id)
	var player = player_scene.instantiate()
	player.name = str(id)
	add_child(player)
	player.name = str(id)

func _remove_player(id: int):
	if not has_node(str(id)):
		return
	get_node(str(id)).queue_free()

# ── Floor Item Networking ──────────────────────────────────────────────────────

func host_spawn_floor_item(pos: Vector2) -> int:
	var id = next_item_id
	next_item_id += 1
	if multiplayer.has_multiplayer_peer():
		spawn_floor_item_rpc.rpc(id, pos.x, pos.y)
	else:
		_do_spawn_floor_item(id, pos.x, pos.y)
	return id

@rpc("authority", "call_local", "reliable")
func spawn_floor_item_rpc(item_id: int, pos_x: float, pos_y: float):
	_do_spawn_floor_item(item_id, pos_x, pos_y)

func _do_spawn_floor_item(item_id: int, pos_x: float, pos_y: float):
	var wood_scene = preload("res://Scenes/wood.tscn")
	var wood = wood_scene.instantiate()
	wood.item_id = item_id
	wood.global_position = Vector2(pos_x, pos_y)
	add_child(wood)
	floor_items[item_id] = wood

func remove_floor_item(item_id: int):
	if floor_items.has(item_id):
		if is_instance_valid(floor_items[item_id]):
			floor_items[item_id].queue_free()
		floor_items.erase(item_id)

func sync_floor_items_to_peer(peer_id: int):
	for item_id in floor_items:
		var item = floor_items[item_id]
		if is_instance_valid(item):
			var pos = item.global_position
			spawn_floor_item_rpc.rpc_id(peer_id, item_id, pos.x, pos.y)

@rpc("any_peer", "call_remote", "reliable")
func request_spawn_floor_item(pos_x: float, pos_y: float):
	if not is_host:
		return
	host_spawn_floor_item(Vector2(pos_x, pos_y))

# Client calls this on host to request item removal
@rpc("any_peer", "call_remote", "reliable")
func request_remove_floor_item(item_id: int):
	if not is_host:
		return
	sync_remove_floor_item.rpc(item_id)

# Host broadcasts removal to all peers including itself
@rpc("authority", "call_local", "reliable")
func sync_remove_floor_item(item_id: int):
	remove_floor_item(item_id)

# ── Boilerplate ────────────────────────────────────────────────────────────────

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if lobby_id != 0:
			Steam.leaveLobby(lobby_id)
		get_tree().quit()

func _on_host_button_pressed():
	host_lobby()

func _on_id_prompt_text_changed(new_text):
	join_button.disabled = (new_text.length() == 0)

func _on_join_button_pressed():
	join_lobby(id_prompt.text.to_int())

func _process(_delta):
	Steam.run_callbacks()

func spawn_tree_with_id(pos: Vector2) -> int:
	var id = next_tree_id
	next_tree_id += 1
	if multiplayer.has_multiplayer_peer():
		spawn_tree_rpc.rpc(id, pos.x, pos.y)
	else:
		_do_spawn_tree(id, pos.x, pos.y)
	return id

@rpc("authority", "call_local", "reliable")
func spawn_tree_rpc(tree_id: int, pos_x: float, pos_y: float):
	_do_spawn_tree(tree_id, pos_x, pos_y)

func _do_spawn_tree(tree_id: int, pos_x: float, pos_y: float):
	var tree_scene = preload("res://Scenes/tree.tscn")
	var tree = tree_scene.instantiate()
	tree.position = Vector2(pos_x, pos_y)
	tree.tree_id = tree_id
	add_child(tree)
	trees[tree_id] = tree

func remove_tree(tree_id: int):
	if trees.has(tree_id):
		if is_instance_valid(trees[tree_id]):
			trees[tree_id].queue_free()
		trees.erase(tree_id)

@rpc("authority", "call_local", "reliable")
func sync_remove_tree(tree_id: int):
	remove_tree(tree_id)

@rpc("any_peer", "call_remote", "reliable")
func request_chop_tree(tree_id: int):
	if not is_host:
		return
	if trees.has(tree_id):
		trees[tree_id].do_chop()

func sync_trees_to_peer(peer_id: int):
	for tree_id in trees:
		var tree = trees[tree_id]
		if is_instance_valid(tree):
			spawn_tree_rpc.rpc_id(peer_id, tree_id, tree.position.x, tree.position.y)
