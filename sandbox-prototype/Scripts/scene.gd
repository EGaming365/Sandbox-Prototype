extends Node2D

var lobby_id : int = 0
var peer : SteamMultiplayerPeer
@export var player_scene : PackedScene
var is_host : bool = false
var is_joining : bool = false
var signals_connected : bool = false

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

func host_lobby():
	await get_tree().create_timer(1.0).timeout
	Steam.initRelayNetworkAccess()
	# ✅ Wait for relay network to be ready before creating lobby
	await get_tree().create_timer(1.0).timeout
	Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, 2)
	is_host = true

func join_lobby(new_lobby_id : int):
	is_joining = true
	Steam.joinLobby(new_lobby_id)

func _on_lobby_created(result: int, new_lobby_id: int):
	if result != 1:
		return
	lobby_id = new_lobby_id
	# Remove singleplayer placeholder
	if has_node("1"):
		get_node("1").queue_free()
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
	_spawn_player(multiplayer.get_unique_id())

func _on_lobby_joined(new_lobby_id: int, _permissions: int, _locked: bool, response: int):
	print("Lobby joined response: ", response)
	if !is_joining:
		return
	lobby_id = new_lobby_id
	# Remove singleplayer placeholder
	if has_node("1"):
		get_node("1").queue_free()
	await get_tree().create_timer(1.0).timeout
	peer = SteamMultiplayerPeer.new()
	peer.server_relay = true
	peer.create_client(Steam.getLobbyOwner(lobby_id))
	multiplayer.multiplayer_peer = peer
	is_joining = false
	multiplayer.server_disconnected.connect(_on_host_disconnected)
	multiplayer.peer_disconnected.connect(_remove_player)

func _on_host_disconnected():
	print("Host disconnected, leaving lobby")
	Steam.leaveLobby(lobby_id)
	lobby_id = 0
	# Remove all multiplayer players (keep singleplayer "1" node)
	for child in get_children():
		if child.name.is_valid_int() and child.name != "1":
			child.queue_free()
	# Remove the local multiplayer player too and respawn as singleplayer
	if has_node(str(multiplayer.get_unique_id())):
		get_node(str(multiplayer.get_unique_id())).queue_free()
	multiplayer.multiplayer_peer = null
	is_host = false
	is_joining = false
	# Respawn as singleplayer
	await get_tree().process_frame
	_spawn_player(1)

func _on_peer_connected(id: int):
	print("Peer connected on host: ", id)
	_spawn_player(id)
	var ids_to_send : Array[int] = []
	for child in get_children():
		if child.name.is_valid_int():
			ids_to_send.append(child.name.to_int())
	sync_players_to_client.rpc_id(id, ids_to_send)

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
