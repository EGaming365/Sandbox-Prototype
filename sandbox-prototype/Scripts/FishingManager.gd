extends Node

const CAST_RANGE: float = 200.0
const MINIGAME_SCENE: String = "res://Scenes/fishing_minigame.tscn"
var _minigame_packed: PackedScene = preload("res://Scenes/fishing_minigame.tscn")
var _cast_water_type: String = "both"
var _active_fish: Dictionary = {}

const RARITY_WEIGHTS: Dictionary = {
	"Trash": 5.0,  # 4.47
	"Common": 55.0,  # 49.19
	"Uncommon": 30.0,  # 26.83
	"Unusual": 10.0,  # 8.94
	"Rare": 5.0,  # 4.47
	"Epic": 3.5,  # 3.13
	"Legendary": 2.0,  # 1.79
	"Mythic": 1.0,  # 0.89
	"Exotic": 0.3,  # 0.27
}

const FISH_TABLE: Array[Dictionary] = [
	{"name": "Minnow",      "rarity": "Common",    "habitat": "lake",  "zone_height": 10.0,  "speed": 0.55, "progress_rate": 1.0,  "escape_rate": 0.7,  "base_weight_kg": 0.08, "tension": 1},
	{"name": "Perch",       "rarity": "Common",    "habitat": "lake",  "zone_height": 10.0,  "speed": 0.75, "progress_rate": 0.95, "escape_rate": 0.85, "base_weight_kg": 0.3,  "tension": 1},
	{"name": "Bass",        "rarity": "Uncommon",  "habitat": "all",   "zone_height": 10.0,  "speed": 1.0,  "progress_rate": 0.90, "escape_rate": 1.05, "base_weight_kg": 1.2,  "tension": 1},
	{"name": "Pike",        "rarity": "Uncommon",  "habitat": "lake",  "zone_height": 10.0,  "speed": 1.25, "progress_rate": 0.85, "escape_rate": 1.2,  "base_weight_kg": 2.5,  "tension": 1},
	{"name": "Catfish",     "rarity": "Unusual",   "habitat": "lake",  "zone_height": 10.0,  "speed": 1.5,  "progress_rate": 0.80, "escape_rate": 1.4,  "base_weight_kg": 4.0,  "tension": 2},
	{"name": "Sturgeon",    "rarity": "Unusual",   "habitat": "cave",  "zone_height": 10.0,  "speed": 1.8,  "progress_rate": 0.75, "escape_rate": 1.6,  "base_weight_kg": 12.0, "tension": 2},
	{"name": "Tophat Fish", "rarity": "Legendary", "habitat": "lake",  "zone_height": 10.0,  "speed": 2.1,  "progress_rate": 0.65, "escape_rate": 1.7,  "base_weight_kg": 0.6,  "tension": 2},
	{"name": "Clownfish",   "rarity": "Common",    "habitat": "ocean", "zone_height": 10.0,  "speed": 0.6,  "progress_rate": 1.2,  "escape_rate": 0.6,  "base_weight_kg": 0.1,  "tension": 1},
	{"name": "Blue Tang",   "rarity": "Common",    "habitat": "ocean", "zone_height": 10.0,  "speed": 0.8,  "progress_rate": 1.0,  "escape_rate": 0.8,  "base_weight_kg": 0.9,  "tension": 1},
	{"name": "Red Tang",    "rarity": "Unusual",   "habitat": "ocean", "zone_height": 10.0,  "speed": 1.2,  "progress_rate": 0.6,  "escape_rate": 1.5,  "base_weight_kg": 2.5,  "tension": 1},
	{"name": "Salmon",      "rarity": "Uncommon",  "habitat": "ocean", "zone_height": 10.0,  "speed": 1.4,  "progress_rate": 0.8,  "escape_rate": 1.3,  "base_weight_kg": 3.0,  "tension": 1},
	{"name": "Lionfish",    "rarity": "Rare",      "habitat": "ocean", "zone_height": 10.0,  "speed": 1.9,  "progress_rate": 0.7,  "escape_rate": 1.7,  "base_weight_kg": 0.8,  "tension": 2},
	{"name": "Tire",        "rarity": "Trash",     "habitat": "all",   "zone_height": 10.0,  "speed": 1.9,  "progress_rate": 0.75, "escape_rate": 1.7,  "base_weight_kg": 10.0, "tension": 1},
]

const ROD_STATS: Dictionary = {
	"Fishing Rod": {
		"cast_range":    150.0,
		"zone_height":   1.0,
		"speed":         1.0,
		"progress_rate": 1.0,
		"escape_rate":   1.0,
		"player_bar":    70.0,
		"luck":          1.0,
		"max_weight_kg": 4.0,
		"bar_speed":     1.0,
		"tension":       1,
		"bite_time":     4.0,
	},
	"Stone Fishing Rod": {
		"cast_range":    180.0,
		"zone_height":   1.0,
		"speed":         0.9,
		"progress_rate": 1.0,
		"escape_rate":   0.9,
		"player_bar":    90.0,
		"luck":          0.85,
		"max_weight_kg": 200.0,
		"bar_speed":     1.1,
		"tension":       2,
		"bite_time":     3.0,
	},
}

var catch_textures = {
	"Trash": preload("res://Assets/Catch_Normal.png"),
	"Common": preload("res://Assets/Catch_Normal.png"),
	"Uncommon": preload("res://Assets/Catch_Normal.png"),
	"Unusual": preload("res://Assets/Catch_Normal.png"),
	"Rare": preload("res://Assets/Catch_Normal.png"),
	"Epic": preload("res://Assets/Catch_Normal.png"),
	"Legendary": preload("res://Assets/Catch_Legendary.png"),
	"Mythic": preload("res://Assets/Catch_Mythic.png"),
	"Exotic": preload("res://Assets/Catch_Exotic.png"),
}

var bobber_texture = preload("res://Assets/Fishing_Bobber.png")

var _waiting_for_bite: bool = false
var _minigame_active: bool = false
var _catch_icon_scene: Node = null
var _bobber: Sprite2D = null
var _world_gen: Node = null
var _player: Node = null
var _cast_cooldown: float = 0.0
var _cast_gen: int = 0

const CAST_COOLDOWN_TIME: float = 2.5

func _get_held_rod() -> String:
	var hotbar = get_tree().root.get_node_or_null("Scene/CanvasLayer/Hotbar")
	if not hotbar:
		return ""
	var slot = Inventory.slots[hotbar.current_slot - 1]
	if slot["item"] in ROD_STATS:
		return slot["item"]
	return ""

func _get_rod_stats() -> Dictionary:
	var rod = _get_held_rod()
	if rod != "" and ROD_STATS.has(rod):
		return ROD_STATS[rod]
	return ROD_STATS["Fishing Rod"]

func _apply_rod_to_fish(fish: Dictionary) -> Dictionary:
	var f := fish.duplicate()
	var rs := _get_rod_stats()
	f["zone_height"]   = f["zone_height"]   * rs.get("zone_height",   1.0)
	f["speed"]         = f["speed"]         * rs.get("speed",         1.0)
	f["progress_rate"] = f["progress_rate"] * rs.get("progress_rate", 1.0)
	f["escape_rate"]   = f["escape_rate"]   * rs.get("escape_rate",   1.0)
	f["player_bar"]    = rs.get("player_bar", 1.0)
	f["bar_speed"]     = rs.get("bar_speed", 1.0)
	return f

func _process(delta: float) -> void:
	if _cast_cooldown > 0.0:
		_cast_cooldown -= delta
		var cursor = get_tree().root.get_node_or_null("Scene/CanvasLayer/Cursor")
		if cursor:
			cursor.show_cooldown(clamp(_cast_cooldown / CAST_COOLDOWN_TIME, 0.0, 1.0), "fishing")

func try_cast(screen_pos: Vector2) -> void:
	if _cast_cooldown > 0.0:
		return
	if _minigame_active or _waiting_for_bite:
		_cancel_cast()
		return
	var player := _get_player()
	if not player:
		return
	if not _has_empty_slot():
		_show_full_inventory_notice()
		return
	var world_click := get_viewport().get_canvas_transform().affine_inverse() * screen_pos
	var cast_range: float = _get_rod_stats().get("cast_range", CAST_RANGE)
	if player.global_position.distance_to(world_click) > cast_range:
		return
	var wg := _get_world_gen()
	if not wg:
		return
	var cave_gen := get_tree().root.get_node_or_null("Scene/CaveWorldGen")
	var in_cave: bool = cave_gen != null and cave_gen.in_cave
	if not in_cave and not wg.is_water_tile_at(world_click):
		return
	if in_cave:
		var cave_tile: Vector2i = cave_gen.world_to_tile(world_click)
		var cave_biome: int = cave_gen._biome_for_tile(cave_tile)
		if cave_biome != cave_gen.BiomeType.WATER_LAKE:
			return
		_cast_water_type = "cave"
	elif wg.has_method("is_ocean_at") and wg.is_ocean_at(world_click):
		_cast_water_type = "ocean"
	elif wg.has_method("is_lake_at") and wg.is_lake_at(world_click):
		_cast_water_type = "lake"
	else:
		_cast_water_type = "all"
	_spawn_bobber(world_click)
	player.is_fishing = true
	_start_minigame()

func _pick_random_fish() -> Dictionary:
	var luck: float = _get_rod_stats().get("luck", 1.0)
	var max_weight_kg: float = _get_rod_stats().get("max_weight_kg", 5.0)
	var rod_tension: int = _get_rod_stats().get("tension", 1)
	var weights := RARITY_WEIGHTS.duplicate()

	for rarity in ["Trash", "Common", "Uncommon", "Unusual"]:
		if weights.has(rarity):
			weights[rarity] *= luck

	var weather = get_tree().root.get_node_or_null("Scene/Weather")
	if weather and weather.aurora_active:
		for rarity in ["Rare", "Epic", "Legendary"]:
			if weights.has(rarity):
				weights[rarity] *= 9.0

	var available_rarities: Dictionary = {}
	for f in FISH_TABLE:
		var h: String = f.get("habitat", "both")
		if (h == "both" or h == _cast_water_type) and f.get("tension", 1) <= rod_tension:
			available_rarities[f["rarity"]] = true

	var filtered_weights: Dictionary = {}
	for rarity in weights:
		if available_rarities.has(rarity):
			filtered_weights[rarity] = weights[rarity]
	if filtered_weights.is_empty():
		filtered_weights = {"Common": 100}

	const PRECIOUS = ["Legendary", "Mythic", "Exotic"]
	var chosen_rarity: String = ""
	var max_attempts := 10
	while max_attempts > 0:
		max_attempts -= 1
		var total: float = 0.0
		for w in filtered_weights.values():
			total += w
		var rarity_roll := randf() * total
		var cumulative: float = 0.0
		var rolled: String = "Common"
		for rarity in filtered_weights:
			cumulative += filtered_weights[rarity]
			if rarity_roll <= cumulative:
				rolled = rarity
				break
		if rolled in PRECIOUS:
			var valid := false
			for f in FISH_TABLE:
				var h: String = f.get("habitat", "both")
				if f["rarity"] == rolled and (h == "both" or h == _cast_water_type) and f.get("tension", 1) <= rod_tension:
					valid = true
					break
			if not valid:
				continue
		chosen_rarity = rolled
		break
	if chosen_rarity == "":
		chosen_rarity = "Common"

	var pool: Array = []
	for f in FISH_TABLE:
		var h: String = f.get("habitat", "both")
		if f["rarity"] == chosen_rarity and (h == "both" or h == _cast_water_type) and f.get("tension", 1) <= rod_tension:
			pool.append(f)
	if pool.is_empty():
		for f in FISH_TABLE:
			if f.get("tension", 1) <= rod_tension:
				pool.append(f)
	if pool.is_empty():
		return FISH_TABLE[0]

	var fish: Dictionary
	var attempts: int = 0
	while true:
		fish = pool[randi() % pool.size()].duplicate()
		fish["weight_kg"] = _generate_weight(fish["base_weight_kg"])
		fish["mutations"] = _generate_mutations()
		if fish["weight_kg"] <= max_weight_kg or attempts >= 10:
			break
		attempts += 1
	fish["bar_speed"] = _get_rod_stats().get("bar_speed", 1.0)
	return fish

func _start_minigame() -> void:
	if _waiting_for_bite:
		return
	_waiting_for_bite = true
	var gen := _cast_gen
	var fish := _pick_random_fish()
	var bite_time: float = _get_rod_stats().get("bite_time", 3.0)
	var wait_time = randf_range(bite_time - 1.0, bite_time + 1.0)
	await get_tree().create_timer(wait_time).timeout
	if not _waiting_for_bite or gen != _cast_gen:
		return
	_show_catch_icon(fish)
	await get_tree().create_timer(0.8).timeout
	_hide_catch_icon()
	if gen != _cast_gen:
		return
	_launch_minigame(fish)

func _launch_minigame(fish: Dictionary) -> void:
	_waiting_for_bite = false
	_active_fish = fish
	var mg: Control = _minigame_packed.instantiate()
	var canvas := get_tree().root.get_node_or_null("Scene/CanvasLayer")
	if canvas:
		canvas.add_child(mg)
	else:
		get_tree().root.add_child(mg)
	_minigame_active = true
	var modified_fish := _apply_rod_to_fish(fish)
	mg.fish_caught.connect(_on_fish_caught.bind(fish))
	mg.fish_escaped.connect(_on_fish_escaped)
	mg.setup.call_deferred(modified_fish)

func _cancel_cast() -> void:
	if _minigame_active:
		return
	if _catch_icon_scene and is_instance_valid(_catch_icon_scene):
		return
	_cast_gen += 1
	_waiting_for_bite = false
	_despawn_bobber()
	_hide_catch_icon()
	_cast_cooldown = CAST_COOLDOWN_TIME
	var player := _get_player()
	if player:
		player.is_fishing = false

func _on_fish_caught(fish: Dictionary) -> void:
	_minigame_active = false
	_despawn_bobber()
	_cast_cooldown = CAST_COOLDOWN_TIME
	_consume_rod_durability()
	var player := _get_player()
	if player:
		player.is_fishing = false
	_give_fish_to_player(fish)

func _on_fish_escaped() -> void:
	_minigame_active = false
	_despawn_bobber()
	_cast_cooldown = CAST_COOLDOWN_TIME
	_consume_rod_durability()
	var player := _get_player()
	if player:
		player.is_fishing = false
	_show_lost_notification(_active_fish)
	_active_fish = {}

func _show_lost_notification(fish: Dictionary) -> void:
	if fish.is_empty():
		return
	var canvas := get_tree().root.get_node_or_null("Scene/CanvasLayer")
	if not canvas:
		return

	var rarity_name: String = fish.get("rarity", "Common")
	var rarity_color := Color.WHITE
	var extras = get_tree().root.get_node_or_null("Scene/CanvasLayer/Extras")
	if extras:
		rarity_color = extras._rarity_color(rarity_name)

	var container := VBoxContainer.new()
	container.anchor_left = 0.5
	container.anchor_top = 0.5
	container.anchor_right = 0.5
	container.anchor_bottom = 0.5
	container.grow_horizontal = Control.GROW_DIRECTION_BOTH
	container.grow_vertical = Control.GROW_DIRECTION_BOTH
	container.z_index = 20

	var lost_label := Label.new()
	lost_label.text = "You Lost a " + rarity_name + "!"
	lost_label.add_theme_font_size_override("font_size", 26)
	lost_label.add_theme_color_override("font_color", rarity_color)
	lost_label.add_theme_color_override("font_outline_color", Color.BLACK)
	lost_label.add_theme_constant_override("outline_size", 6)
	lost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(lost_label)

	canvas.add_child(container)
	await get_tree().process_frame
	container.offset_left = -container.size.x / 2.0
	container.offset_right = container.size.x / 2.0
	container.offset_top = -container.size.y / 2.0 - 450.0
	container.offset_bottom = container.size.y / 2.0 - 450.0
	var tween := container.create_tween()
	tween.tween_interval(2.2)
	tween.tween_property(container, "modulate:a", 0.0, 0.6)
	tween.tween_callback(container.queue_free)

func _give_fish_to_player(fish: Dictionary) -> void:
	var weight_kg: float = fish.get("weight_kg", 0.1)
	var weight_grams: int = int(round(weight_kg * 1000.0))
	var mutations: Array = fish.get("mutations", [])
	var is_albino: bool = "Albino" in mutations
	var display_name: String = fish["name"]
	if is_albino:
		display_name = "Albino " + display_name
	var fish_texture_map = {
		"Perch": "res://Assets/Fish_Perch_Raw.png",
		"Albino Perch": "res://Assets/Fish_Perch_Raw.png",
		"Catfish": "res://Assets/Fish_Catfish_Raw.png",
		"Albino Catfish": "res://Assets/Fish_Catfish_Raw.png",
	}
	var tex: Texture2D = load(fish_texture_map.get(display_name, "res://Assets/Fish_Tophat_Raw.png"))
	var existing_tex: Texture2D = Inventory.get_texture(display_name)
	if existing_tex:
		tex = existing_tex
	Inventory.discover(display_name)
	var extras = get_tree().root.get_node_or_null("Scene/CanvasLayer/Extras")
	if extras:
		extras.discover_fish(display_name, weight_kg)
	for i in Inventory.slots.size():
		if Inventory.slots[i]["item"] == "":
			Inventory.slots[i]["item"] = display_name
			Inventory.slots[i]["count"] = weight_grams
			Inventory.slots[i]["texture"] = tex
			Inventory._queue_emit()
			_show_catch_notification(display_name, weight_kg, mutations)
			return
	for i in Inventory.unlocked_inv_slots:
		if Inventory.inv_slots[i]["item"] == "":
			Inventory.inv_slots[i]["item"] = display_name
			Inventory.inv_slots[i]["count"] = weight_grams
			Inventory.inv_slots[i]["texture"] = tex
			Inventory._queue_emit()
			_show_catch_notification(display_name, weight_kg, mutations)
			return
	_show_catch_notification(display_name, weight_kg, mutations)

func _show_catch_notification(name: String, weight_kg: float, mutations: Array) -> void:
	var canvas := get_tree().root.get_node_or_null("Scene/CanvasLayer")
	if not canvas:
		return

	var weight_str: String
	if weight_kg < 1.0:
		weight_str = str(int(weight_kg * 1000)) + "g"
	else:
		weight_str = str(snappedf(weight_kg, 0.01)) + "kg"

	var base_kg := _get_base_weight_for_name(name)
	var size_tag := _get_size_tag(weight_kg, base_kg)

	var rarity_color := Color.WHITE
	for f in FISH_TABLE:
		if f["name"] == name or "Albino " + f["name"] == name:
			var extras = get_tree().root.get_node_or_null("Scene/CanvasLayer/Extras")
			if extras:
				rarity_color = extras._rarity_color(f.get("rarity", "Common"))
			break

	var container := VBoxContainer.new()
	container.anchor_left = 0.5
	container.anchor_top = 0.5
	container.anchor_right = 0.5
	container.anchor_bottom = 0.5
	container.grow_horizontal = Control.GROW_DIRECTION_BOTH
	container.grow_vertical = Control.GROW_DIRECTION_BOTH
	container.z_index = 20

	var rarity_label := Label.new()
	var rarity_name := "Common"
	for f in FISH_TABLE:
		if f["name"] == name or "Albino " + f["name"] == name:
			rarity_name = f.get("rarity", "Common")
			break
	rarity_label.text = "You Caught a " + rarity_name + "!"
	rarity_label.add_theme_font_size_override("font_size", 26)
	rarity_label.add_theme_color_override("font_color", rarity_color)
	rarity_label.add_theme_color_override("font_outline_color", Color.BLACK)
	rarity_label.add_theme_constant_override("outline_size", 6)
	rarity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(rarity_label)

	var fish_label := Label.new()
	fish_label.text = name + size_tag + "  •  " + weight_str
	fish_label.add_theme_font_size_override("font_size", 22)
	fish_label.add_theme_color_override("font_color", rarity_color)
	fish_label.add_theme_color_override("font_outline_color", Color.BLACK)
	fish_label.add_theme_constant_override("outline_size", 5)
	fish_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(fish_label)

	canvas.add_child(container)
	container.pivot_offset = container.size / 2.0
	await get_tree().process_frame
	container.offset_left = -container.size.x / 2.0
	container.offset_right = container.size.x / 2.0
	container.offset_top = -container.size.y / 2.0 - 450.0
	container.offset_bottom = container.size.y / 2.0 - 450.0
	var tween := container.create_tween()
	tween.tween_interval(2.2)
	tween.tween_property(container, "modulate:a", 0.0, 0.6)
	tween.tween_callback(container.queue_free)

func _get_base_weight_for_name(fish_name: String) -> float:
	for f in FISH_TABLE:
		if f["name"] == fish_name or "Albino " + f["name"] == fish_name:
			return f["base_weight_kg"]
	return 1.0

func _consume_rod_durability() -> void:
	var hotbar = get_tree().root.get_node_or_null("Scene/CanvasLayer/Hotbar")
	if not hotbar:
		return
	var slot_index = hotbar.current_slot - 1
	var slot = Inventory.slots[slot_index]
	if slot["item"] != "Fishing Rod" and slot["item"] != "Stone Fishing Rod":
		return
	slot["count"] -= 1
	if slot["count"] <= 0:
		Inventory.remove_item(slot_index, false)
	else:
		Inventory.inventory_changed.emit()

func _get_player() -> Node:
	if _player and is_instance_valid(_player):
		return _player
	var scene := get_tree().root.get_node_or_null("Scene")
	if not scene:
		return null
	var lp = scene.get("local_player")
	if lp and is_instance_valid(lp):
		_player = lp
		return _player
	for child in scene.get_children():
		if child is CharacterBody2D:
			if not multiplayer.has_multiplayer_peer() or child.is_multiplayer_authority():
				_player = child
				return _player
	return null

func _get_world_gen() -> Node:
	if _world_gen and is_instance_valid(_world_gen):
		return _world_gen
	_world_gen = get_tree().root.get_node_or_null("Scene/WorldGen")
	return _world_gen

func _generate_weight(base_kg: float) -> float:
	var r1 := randf()
	var r2 := randf()
	var r3 := randf()
	var r4 := randf()
	var avg := (r1 + r2 + r3 + r4) / 4.0
	var multiplier: float = lerp(0.1, 3.0, pow(avg, 1.35))
	return snappedf(base_kg * multiplier, 0.01)

func _generate_mutations() -> Array:
	var mutations: Array = []
	if randf() < 0.03:
		mutations.append("Albino")
	return mutations

func _get_size_tag(weight_kg: float, base_kg: float) -> String:
	var ratio := weight_kg / base_kg
	if ratio >= 2.5:
		return " (giant)"
	elif ratio >= 1.8:
		return " (large)"
	elif ratio >= 1.4:
		return " (big)"
	elif ratio <= 0.15:
		return " (tiny)"
	elif ratio <= 0.35:
		return " (small)"
	return ""

func _spawn_bobber(world_pos: Vector2) -> void:
	_despawn_bobber()
	var bobber := Sprite2D.new()
	bobber.texture = bobber_texture
	bobber.position = world_pos
	bobber.z_index = 3
	bobber.scale = Vector2(4.5, 4.5)
	get_tree().root.get_node("Scene").add_child(bobber)
	_bobber = bobber
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		var player := _get_player()
		if player:
			var peer_id := player.get_multiplayer_authority()
			_sync_bobber_spawn.rpc(peer_id, world_pos)

func _despawn_bobber() -> void:
	if _bobber and is_instance_valid(_bobber):
		_bobber.queue_free()
	_bobber = null
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		var player := _get_player()
		if player:
			var peer_id := player.get_multiplayer_authority()
			_sync_bobber_despawn.rpc(peer_id)

func _show_catch_icon(fish: Dictionary) -> void:
	var player := _get_player()
	if not player:
		return
	var tex = catch_textures.get(fish["rarity"], catch_textures["Common"])
	var icon := Sprite2D.new()
	icon.texture = tex
	icon.position = player.global_position + Vector2(0, -145)
	icon.z_index = 10
	get_tree().root.get_node("Scene").add_child(icon)
	_catch_icon_scene = icon
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		var peer_id := player.get_multiplayer_authority()
		_sync_catch_icon_show.rpc(peer_id, player.global_position, fish["rarity"])

func _hide_catch_icon() -> void:
	if _catch_icon_scene and is_instance_valid(_catch_icon_scene):
		_catch_icon_scene.queue_free()
	_catch_icon_scene = null
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		var player := _get_player()
		if player:
			_sync_catch_icon_hide.rpc(player.get_multiplayer_authority())

@rpc("authority", "call_remote", "reliable")
func _sync_bobber_spawn(owner_peer_id: int, world_pos: Vector2) -> void:
	if multiplayer.get_unique_id() == owner_peer_id:
		return
	var key := "bobber_" + str(owner_peer_id)
	var scene := get_tree().root.get_node_or_null("Scene")
	if not scene:
		return
	var existing = scene.get_node_or_null(key)
	if existing:
		existing.queue_free()
	var bobber := Sprite2D.new()
	bobber.texture = bobber_texture
	bobber.position = world_pos
	bobber.z_index = 3
	bobber.scale = Vector2(4.5, 4.5)
	bobber.name = key
	scene.add_child(bobber)

@rpc("authority", "call_remote", "reliable")
func _sync_bobber_despawn(owner_peer_id: int) -> void:
	if multiplayer.get_unique_id() == owner_peer_id:
		return
	var key := "bobber_" + str(owner_peer_id)
	var scene := get_tree().root.get_node_or_null("Scene")
	if not scene:
		return
	var existing = scene.get_node_or_null(key)
	if existing:
		existing.queue_free()

@rpc("authority", "call_remote", "reliable")
func _sync_catch_icon_show(owner_peer_id: int, player_pos: Vector2, rarity: String) -> void:
	if multiplayer.get_unique_id() == owner_peer_id:
		return
	var scene := get_tree().root.get_node_or_null("Scene")
	if not scene:
		return
	var key := "catch_icon_" + str(owner_peer_id)
	var existing = scene.get_node_or_null(key)
	if existing:
		existing.queue_free()
	var tex = catch_textures.get(rarity, catch_textures["Common"])
	var icon := Sprite2D.new()
	icon.texture = tex
	icon.position = player_pos + Vector2(0, -145)
	icon.z_index = 10
	icon.name = key
	scene.add_child(icon)

@rpc("authority", "call_remote", "reliable")
func _sync_catch_icon_hide(owner_peer_id: int) -> void:
	if multiplayer.get_unique_id() == owner_peer_id:
		return
	var scene := get_tree().root.get_node_or_null("Scene")
	if not scene:
		return
	var key := "catch_icon_" + str(owner_peer_id)
	var existing = scene.get_node_or_null(key)
	if existing:
		existing.queue_free()

func sync_fishing_state_to_peer(peer_id: int) -> void:
	if _bobber and is_instance_valid(_bobber):
		var player := _get_player()
		if player:
			_sync_bobber_spawn.rpc_id(peer_id, player.get_multiplayer_authority(), _bobber.position)

func _has_empty_slot() -> bool:
	for slot in Inventory.slots:
		if slot["item"] == "":
			return true
	for i in Inventory.unlocked_inv_slots:
		if Inventory.inv_slots[i]["item"] == "":
			return true
	return false

func _show_full_inventory_notice() -> void:
	var canvas := get_tree().root.get_node_or_null("Scene/CanvasLayer")
	if not canvas:
		return
	if canvas.get_node_or_null("FullInvNotice"):
		return
	var label := Label.new()
	label.name = "FullInvNotice"
	label.text = "Inventory is full!"
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	label.offset_top = 80
	label.z_index = 20
	canvas.add_child(label)
	var tween := label.create_tween()
	tween.tween_interval(1.5)
	tween.tween_property(label, "modulate:a", 0.0, 0.5)
	tween.tween_callback(label.queue_free)
