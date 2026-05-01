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

func host_lobby():
	Steam.initRelayNetworkAccess()
	await get_tree().create_timer(1.0).timeout
	Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, 2)
	is_host = true

func join_lobby(new_lobby_id : int):
	is_joining = true
	Steam.joinLobby(new_lobby_id)

func _on_lobby_joined(new_lobby_id : int, _permissions : int, _locked : bool, response : int):
	print("Lobby joined response: ", response)
	if !is_joining:
		return
	self.lobby_id = new_lobby_id
	await get_tree().create_timer(1.0).timeout
	peer = SteamMultiplayerPeer.new()
	peer.server_relay = true
	peer.create_client(Steam.getLobbyOwner(lobby_id))
	multiplayer.multiplayer_peer = peer
	is_joining = false

func _on_lobby_created(result: int, new_lobby_id: int):
	if result == 1:
		lobby_id = new_lobby_id
		peer = SteamMultiplayerPeer.new()
		peer.create_host()
		multiplayer.multiplayer_peer = peer
		multiplayer.peer_connected.connect(_add_player)
		multiplayer.peer_disconnected.connect(_remove_player)
		_add_player()
		print("Lobby Created, Lobby id: ", lobby_id)

func _add_player(id : int = 1):
	print("Adding player with id: ", id)
	var player = player_scene.instantiate()
	player.name = str(id)
	call_deferred("add_child", player)

func _remove_player(id : int):
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
