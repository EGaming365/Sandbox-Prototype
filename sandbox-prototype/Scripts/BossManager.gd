# Boss manager autoload.
# Keeps a registry of spawnable bosses and handles the /boss chat command.

extends Node

# Master switch that turns all boss spawning on or off.
const ENABLED := true

# Names of the bosses that can be spawned with the /boss command.
var _registry: Dictionary = {
	"spider_queen": true,
}


# Reads a /boss command and spawns the boss on the host, asking the host to do it when this is a client.
func handle_command(command_text: String) -> void:
	if not ENABLED:
		return
	# Split the command into words, ignoring extra spaces.
	var command_parts := command_text.strip_edges().split(" ", false)
	if command_parts.size() < 2:
		return
	# The boss name is the second word, converted to a lookup key such as spider_queen.
	var boss_key := command_parts[1].to_lower().replace(" ", "_")
	# Warn and stop if the requested boss does not exist.
	if not _registry.has(boss_key):
		push_warning("BossManager: no boss registered as '%s'" % boss_key)
		return
	# Clients cannot spawn bosses, so they send a request to the host instead.
	var scene_node := get_tree().root.get_node_or_null("Scene")
	if scene_node and multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		if scene_node.has_method("request_spawn_boss"):
			scene_node.request_spawn_boss.rpc_id(1, boss_key)
		return
	# The host (or a single player game) spawns the boss directly.
	spawn_by_key(boss_key)


# Spawns the boss registered under the given key near the first player.
func spawn_by_key(boss_key: String) -> void:
	if not ENABLED:
		return
	if not _registry.has(boss_key):
		push_warning("BossManager: no boss registered as '%s'" % boss_key)
		return
	# Only the host may create bosses so every client sees the same one.
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	# Find a player to spawn the boss next to.
	var player := get_tree().get_first_node_in_group("players")
	if not player:
		push_warning("BossManager: no player found")
		return
	# The animal spawner owns the code that creates the boss scene.
	var animal_spawner := get_tree().root.get_node_or_null("AnimalSpawner")
	if not animal_spawner or not animal_spawner.has_method("spawn_combat_boss"):
		push_warning("BossManager: AnimalSpawner unavailable")
		return
	# Spawn the boss 200 pixels to the right of the player.
	var spawn_pos: Vector2 = (player as Node2D).global_position + Vector2(200, 0)
	# Create the boss and get notified when it dies.
	var boss: Node = animal_spawner.spawn_combat_boss(spawn_pos, -1)
	if boss and is_instance_valid(boss) and boss.has_signal("boss_died"):
		boss.boss_died.connect(_on_boss_died.bind(boss_key))
	print("BossManager: spawned '%s'" % boss_key)


# Called when a boss created by this manager is defeated.
func _on_boss_died(boss_key: String) -> void:
	print("BossManager: '%s' defeated" % boss_key)
