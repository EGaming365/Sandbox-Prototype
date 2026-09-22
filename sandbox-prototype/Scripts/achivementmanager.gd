# Achievement manager.
# Detects when a player reaches a milestone, records it on the host and announces it in the chat for everyone.
# Wood, stone, torch and fishing rod are detected from the inventory, the cave from the cave generator and the boss from its death signal.

extends Node

# Emitted on every game when someone unlocks an achievement. A future UI can listen to this.
signal achievement_unlocked(peer_id: int, achievement_id: String)

# The suggested order for guiding the player. The next one not yet unlocked is the current goal.
const ORDERED_ACHIEVEMENTS: Array[String] = [
	"get_wood",
	"get_stone",
	"make_torch",
	"enter_cave_world",
	"kill_boss",
]

# Title and hint for every achievement, stored by ID.
const ACHIEVEMENT_DATA := {
	"get_wood": {"title": "Lumberjack", "hint": "Go gather some wood."},
	"get_stone": {"title": "Rock Solid", "hint": "Now go gather some stone."},
	"make_fishing_rod": {"title": "Gone Fishing", "hint": "Try crafting a fishing rod."},
	"make_torch": {"title": "Let There Be Light", "hint": "Craft yourself a torch."},
	"enter_cave_world": {"title": "Into the Dark", "hint": "Head into the cave world."},
	"kill_boss": {"title": "Boss Slayer", "hint": "Find and defeat the boss."},
}

# Maps an item name to the achievement earned the first time the player has that item.
const ITEM_ACHIEVEMENTS := {
	"Wood": "get_wood",
	"Stone": "get_stone",
	"Torch": "make_torch",
	"Fishing Rod": "make_fishing_rod",
}

# Turns the chat announcement on or off.
@export var announce_in_chat: bool = true
# Seconds between checks for whether the player has entered the cave.
@export var cave_check_interval: float = 0.5
# Location of the chat box in the scene.
@export var chat_box_path: String = "Scene/CanvasLayer/Chat_Box"
# Location of the cave generator in the scene.
@export var cave_gen_path: String = "Scene/CaveWorldGen"

# Unlocked achievements for each player, stored by network ID.
var _unlocked_by_peer: Dictionary = {}
# Achievements this game has already asked to unlock, so requests are not repeated.
var _requested: Dictionary = {}
# Time since the cave was last checked.
var _cave_timer: float = 0.0


# Connects everything the manager needs to watch: connections, the inventory and new bosses.
func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.connected_to_server.connect(_on_connection_changed)
	multiplayer.server_disconnected.connect(_on_connection_changed)
	Inventory.inventory_changed.connect(_check_item_achievements)
	get_parent().child_entered_tree.connect(_on_scene_child_added)
	_check_item_achievements()


# Regularly checks whether the player has entered the cave world.
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


# The player's network ID changes when joining or leaving a game, so ask for their achievements again.
func _on_connection_changed() -> void:
	_requested.clear()
	_check_item_achievements()


# The host sends a joining player everything already unlocked.
func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if not _unlocked_by_peer.has(peer_id):
		_unlocked_by_peer[peer_id] = {}
	_sync_state.rpc_id(peer_id, _unlocked_by_peer)


# Sent by the host to give a player the current list of unlocked achievements.
@rpc("authority", "call_remote", "reliable")
func _sync_state(state: Dictionary) -> void:
	_unlocked_by_peer = state


# Unlocks achievements for items the player has discovered.
func _check_item_achievements() -> void:
	for item_name: String in ITEM_ACHIEVEMENTS:
		var achievement_id: String = ITEM_ACHIEVEMENTS[item_name]
		if _requested.has(achievement_id):
			continue
		if Inventory.discovered_items.has(item_name):
			request_unlock(achievement_id)


# Only the host, or a single player game, watches bosses. When a new boss appears, listen for its death.
func _on_scene_child_added(node: Node) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	if not node.has_signal("boss_died"):
		return
	if node.is_connected("boss_died", _on_boss_died):
		return
	node.connect("boss_died", _on_boss_died)


# Gives the boss achievement to every connected player.
func _on_boss_died() -> void:
	var target_ids: Array[int] = [multiplayer.get_unique_id()]
	if multiplayer.has_multiplayer_peer():
		for remote_id: int in multiplayer.get_peers():
			target_ids.append(remote_id)
	for target_id: int in target_ids:
		_process_unlock(target_id, "kill_boss")


# Asks for an achievement to be unlocked. The host does it directly and clients ask the host.
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


# Sent by a client to ask the host to unlock an achievement for them.
@rpc("any_peer", "reliable")
func _server_process_unlock(achievement_id: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	_process_unlock(sender_id, achievement_id)


# Host only. Records the achievement once and tells every player about it.
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


# Sent by the host so every player records and announces the unlock.
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


# Returns the player's Steam name, falling back to 'You' or a numbered name.
func _get_player_name(peer_id: int) -> String:
	var chat_box = get_tree().root.get_node_or_null(chat_box_path)
	if chat_box and chat_box.has_method("_get_steam_name_for_peer"):
		return str(chat_box._get_steam_name_for_peer(peer_id))
	if peer_id == multiplayer.get_unique_id():
		return "You"
	return "Player %d" % peer_id


# Returns true if the player has already unlocked the achievement.
func is_unlocked(achievement_id: String, peer_id: int = -1) -> bool:
	var pid := peer_id if peer_id != -1 else multiplayer.get_unique_id()
	if not _unlocked_by_peer.has(pid):
		return false
	return _unlocked_by_peer[pid].get(achievement_id, false)


# Returns the next achievement in the guided order that the player has not unlocked, or an empty string when all are done.
func get_next_ordered_achievement(peer_id: int = -1) -> String:
	var pid := peer_id if peer_id != -1 else multiplayer.get_unique_id()
	for achievement_id in ORDERED_ACHIEVEMENTS:
		if not is_unlocked(achievement_id, pid):
			return achievement_id
	return ""
