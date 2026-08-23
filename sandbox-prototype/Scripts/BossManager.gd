extends Node

const ENABLED := true

var _registry: Dictionary = {
	"spider_queen": true,
}

func handle_command(raw: String) -> void:
	if not ENABLED:
		return
	var parts := raw.strip_edges().split(" ", false)
	if parts.size() < 2:
		return
	var key := parts[1].to_lower().replace(" ", "_")
	if not _registry.has(key):
		push_warning("BossManager: no boss registered as '%s'" % key)
		return
	var scene_node := get_tree().root.get_node_or_null("Scene")
	if scene_node and multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		if scene_node.has_method("request_spawn_boss"):
			scene_node.request_spawn_boss.rpc_id(1, key)
		return
	spawn_by_key(key)

func spawn_by_key(key: String) -> void:
	if not ENABLED:
		return
	if not _registry.has(key):
		push_warning("BossManager: no boss registered as '%s'" % key)
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	var player := get_tree().get_first_node_in_group("players")
	if not player:
		push_warning("BossManager: no player found")
		return
	var animal_spawner := get_tree().root.get_node_or_null("AnimalSpawner")
	if not animal_spawner or not animal_spawner.has_method("spawn_combat_boss"):
		push_warning("BossManager: AnimalSpawner unavailable")
		return
	var spawn_pos: Vector2 = (player as Node2D).global_position + Vector2(200, 0)
	var boss: Node = animal_spawner.spawn_combat_boss(spawn_pos, -1)
	if boss and is_instance_valid(boss) and boss.has_signal("boss_died"):
		boss.boss_died.connect(_on_boss_died.bind(key))
	print("BossManager: spawned '%s'" % key)

func _on_boss_died(key: String) -> void:
	print("BossManager: '%s' defeated" % key)
