extends Node2D

var lobby_id : int = 0
var peer : SteamMultiplayerPeer
@export var player_scene : PackedScene
var is_host : bool = false
var is_joining : bool = false

@onready var host_button: Button = $CanvasLayer/Host_Button
@onready var join_button: Button = $CanvasLayer/Join_Button
@onready var id_prompt: LineEdit = $CanvasLayer/id_prompt

func _ready():
	print("Steam initialised: ", Steam.steamInitEx(480))
	Steam.initRelayNetworkAccess()
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	print("My Steam ID: ", Steam.getSteamID())
	# Spawn a local player immediately for singleplayer
	_spawn_player(1)

func host_lobby():
	Steam.initRelayNetworkAccess()
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
	peer = SteamMultiplayerPeer.new()
	peer.create_host()
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_remove_player)
	print("Lobby Created, Lobby id: ", lobby_id)
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
	player.name = str(id)  # force it again after add_child
	print("Final player name: ", player.name)

func _remove_player(id: int):
	if not has_node(str(id)):
		return
	get_node(str(id)).queue_free()

func _on_host_button_pressed():
	host_lobby()

func _on_id_prompt_text_changed(new_text):
	join_button.disabled = (new_text.length() == 0)

func _on_join_button_pressed():
	join_lobby(id_prompt.text.to_int())

func _process(_delta):
	Steam.run_callbacks()
