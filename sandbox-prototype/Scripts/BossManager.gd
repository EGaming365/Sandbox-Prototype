extends Node

const ENABLED := true

var _registry: Dictionary = {
	"spider_queen": "res://Scenes/Spider_Queen.tscn",
}

func handle_command(raw: String) -> void:
	if not ENABLED:
		return
	var parts := raw.strip_edges().split(" ", false)
	if parts.size() < 2:
		return
	var key := parts[1].to_lower().replace(" ", "_")
	_spawn(key)

func _spawn(key: String) -> void:
	if not ENABLED:
		return
	if not _registry.has(key):
		push_warning("BossManager: no boss registered as '%s'" % key)
		return
	var player := get_tree().get_first_node_in_group("players")
	if not player:
		push_warning("BossManager: no player found")
		return
	var scene: PackedScene = load(_registry[key])
	if not scene:
		push_warning("BossManager: could not load scene for '%s'" % key)
		return
	var boss := scene.instantiate()
	boss.global_position = (player as Node2D).global_position + Vector2(200, 0)
	get_tree().current_scene.add_child(boss)
	if boss.has_signal("boss_died"):
		boss.boss_died.connect(_on_boss_died.bind(key))
	print("BossManager: spawned '%s'" % key)

func _on_boss_died(key: String) -> void:
	print("BossManager: '%s' defeated" % key)
