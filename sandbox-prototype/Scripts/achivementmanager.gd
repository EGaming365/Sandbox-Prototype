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

const ITEM_ACHIEVEMENTS := {
	"Wood": "get_wood",
	"Stone": "get_stone",
	"Torch": "make_torch",
	"Fishing Rod": "make_fishing_rod",
}

@export var announce_in_chat: bool = true
@export var cave_check_interval: float = 0.5
@export var chat_box_path: String = "Scene/CanvasLayer/Chat_Box"
@export var cave_gen_path: String = "Scene/CaveWorldGen"

var _unlocked_by_peer: Dictionary = {}
var _requested: Dictionary = {}
var _cave_timer: float = 0.0


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.connected_to_server.connect(_on_connection_changed)
	multiplayer.server_disconnected.connect(_on_connection_changed)
	Inventory.inventory_changed.connect(_check_item_achievements)
	get_parent().child_entered_tree.connect(_on_scene_child_added)
	_check_item_achievements()


func _process(delta: float) -> void:
	if _requested.has("enter_cave_world"):
		return
	_cave_timer += delta
	if _cave_timer < cave_check_interval:
		return
	_cave_timer = 0.0
	var cave_gen = get_tree().root.get_node_or_null(cave_gen_path)
	if cave_gen and cave_gen.get("in_cave"):
		request_unlock("enter_cave_world")


func _on_connection_changed() -> void:
	_requested.clear()
	_check_item_achievements()


func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if not _unlocked_by_peer.has(peer_id):
		_unlocked_by_peer[peer_id] = {}
	_sync_state.rpc_id(peer_id, _unlocked_by_peer)


@rpc("authority", "call_remote", "reliable")
func _sync_state(state: Dictionary) -> void:
	_unlocked_by_peer = state


func _check_item_achievements() -> void:
	for item_name: String in ITEM_ACHIEVEMENTS:
		var achievement_id: String = ITEM_ACHIEVEMENTS[item_name]
		if _requested.has(achievement_id):
			continue
		if Inventory.discovered_items.has(item_name):
			request_unlock(achievement_id)


func _on_scene_child_added(node: Node) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	if not node.has_signal("boss_died"):
		return
	if node.is_connected("boss_died", _on_boss_died):
		return
	node.connect("boss_died", _on_boss_died)


func _on_boss_died() -> void:
	var target_ids: Array[int] = [multiplayer.get_unique_id()]
	if multiplayer.has_multiplayer_peer():
		for remote_id: int in multiplayer.get_peers():
			target_ids.append(remote_id)
	for target_id: int in target_ids:
		_process_unlock(target_id, "kill_boss")


func request_unlock(achievement_id: String) -> void:
	if not ACHIEVEMENT_DATA.has(achievement_id):
		return
	if _requested.has(achievement_id):
		return
	_requested[achievement_id] = true
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		_process_unlock(multiplayer.get_unique_id(), achievement_id)
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
	if multiplayer.has_multiplayer_peer():
		_announce_unlock.rpc(peer_id, achievement_id)
	else:
		_announce_unlock(peer_id, achievement_id)


@rpc("authority", "call_local", "reliable")
func _announce_unlock(peer_id: int, achievement_id: String) -> void:
	if not _unlocked_by_peer.has(peer_id):
		_unlocked_by_peer[peer_id] = {}
	_unlocked_by_peer[peer_id][achievement_id] = true
	var data: Dictionary = ACHIEVEMENT_DATA[achievement_id]
	if announce_in_chat:
		var chat_box = get_tree().root.get_node_or_null(chat_box_path)
		if chat_box and chat_box.has_method("_add_message"):
			var message := "%s unlocked an achievement: %s" % [_get_player_name(peer_id), data["title"]]
			chat_box._add_message(message)
	achievement_unlocked.emit(peer_id, achievement_id)


func _get_player_name(peer_id: int) -> String:
	var chat_box = get_tree().root.get_node_or_null(chat_box_path)
	if chat_box and chat_box.has_method("_get_steam_name_for_peer"):
		return str(chat_box._get_steam_name_for_peer(peer_id))
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
