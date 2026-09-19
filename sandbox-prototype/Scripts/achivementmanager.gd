extends Node

signal achievement_unlocked(peer_id: int, achievement_id: String)

const ORDERED_ACHIEVEMENTS: Array[String] = [
	"get_wood",
	"get_stone",
	"make_torch",
	"enter_cave_world",
	"kill_boss",
]

const ACHIEVEMENT_DATA := {
	"get_wood": {"title": "Lumberjack", "hint": "Go gather some wood."},
	"get_stone": {"title": "Rock Solid", "hint": "Now go gather some stone."},
	"make_fishing_rod": {"title": "Gone Fishing", "hint": "Try crafting a fishing rod."},
	"make_torch": {"title": "Let There Be Light", "hint": "Craft yourself a torch."},
	"enter_cave_world": {"title": "Into the Dark", "hint": "Head into the cave world."},
	"kill_boss": {"title": "Boss Slayer", "hint": "Find and defeat the boss."},
}

var _unlocked_by_peer: Dictionary = {}


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)


func _on_peer_connected(peer_id: int) -> void:
	if not _unlocked_by_peer.has(peer_id):
		_unlocked_by_peer[peer_id] = {}


func request_unlock(achievement_id: String) -> void:
	var peer_id := multiplayer.get_unique_id()
	if multiplayer.is_server():
		_process_unlock(peer_id, achievement_id)
	else:
		_server_process_unlock.rpc_id(1, achievement_id)


@rpc("any_peer", "reliable")
func _server_process_unlock(achievement_id: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	_process_unlock(sender_id, achievement_id)


func _process_unlock(peer_id: int, achievement_id: String) -> void:
	if not ACHIEVEMENT_DATA.has(achievement_id):
		return
	if not _unlocked_by_peer.has(peer_id):
		_unlocked_by_peer[peer_id] = {}
	if _unlocked_by_peer[peer_id].get(achievement_id, false):
		return
	_unlocked_by_peer[peer_id][achievement_id] = true
	_announce_unlock.rpc(peer_id, achievement_id)


@rpc("authority", "call_local", "reliable")
func _announce_unlock(peer_id: int, achievement_id: String) -> void:
	var data: Dictionary = ACHIEVEMENT_DATA[achievement_id]
	var player_name := _get_player_name(peer_id)
	var message := "%s unlocked an achievement: %s" % [player_name, data["title"]]
	# Swap for real chat post call.
	if has_node("/root/ChatBox"):
		get_node("/root/ChatBox").post_system_message(message)
	achievement_unlocked.emit(peer_id, achievement_id)


func _get_player_name(peer_id: int) -> String:
	# Swap for real name lookup.
	if peer_id == multiplayer.get_unique_id():
		return "You"
	return "Player %d" % peer_id


func is_unlocked(achievement_id: String, peer_id: int = -1) -> bool:
	var pid := peer_id if peer_id != -1 else multiplayer.get_unique_id()
	if not _unlocked_by_peer.has(pid):
		return false
	return _unlocked_by_peer[pid].get(achievement_id, false)


func get_next_ordered_achievement(peer_id: int = -1) -> String:
	var pid := peer_id if peer_id != -1 else multiplayer.get_unique_id()
	for achievement_id in ORDERED_ACHIEVEMENTS:
		if not is_unlocked(achievement_id, pid):
			return achievement_id
	return ""
