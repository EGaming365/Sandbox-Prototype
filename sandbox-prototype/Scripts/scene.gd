# Main scene script.
# The heart of the game. It connects to Steam, hosts and joins lobbies, spawns and removes players, and keeps every player's game in step with the host.
# It stores the floor items, trees, rocks and placed blocks, and holds the network functions used for damage, respawning, enemies, chickens and bosses.
# The host decides what happens and clients send requests to it.

extends Node2D

# Steam ID of each connected player, stored by network ID.
# The Steam network connection.
var peer_to_steam_id: Dictionary = {}
# ID of the Steam lobby, or 0 if there is none.
var lobby_id: int = 0
var peer: SteamMultiplayerPeer
# Scene created for each player.
@export var player_scene: PackedScene
# True if this game is hosting.
var is_host: bool = false
# True while joining a lobby.
var is_joining: bool = false
# True once the network signals have been connected.
var signals_connected: bool = false
# The player controlled by this game instance.
var local_player: CharacterBody2D = null

# World seed shared by all players.
var synced_world_seed: int = 0
# IDs of trees and rocks that have been destroyed.
var destroyed_env_objects: Dictionary = {}
# Hits taken by damaged trees and rocks, stored by ID.
var env_object_hits: Dictionary = {}

# Items lying on the floor, stored by ID.
var floor_items: Dictionary = {}
# ID given to the next floor item.
var next_item_id: int = 0
# Loose trees, stored by ID.
var trees: Dictionary = {}
# ID given to the next tree.
var next_tree_id: int = 0
# Loose rocks, stored by ID.
var rocks: Dictionary = {}
# ID given to the next rock.
var next_rock_id: int = 0
# Blocks placed by players, stored by ID.
var placed_blocks: Dictionary = {}
# ID given to the next placed block.
var next_block_id: int = 0
# Picture of the block that was placed last.
var last_placed_texture: Texture2D = null

# Button that starts hosting.
@onready var host_button: Button = $CanvasLayer/Host_Button
# Button that joins a lobby.
@onready var join_button: Button = $CanvasLayer/Join_Button
# Text box for the lobby ID.
@onready var id_prompt: LineEdit = $CanvasLayer/id_prompt

# Bottom right button that shows the current lobby code and copies it when clicked.
var lobby_code_display: Button = null
# Counts down while the button is showing "Copied!", so its text can be restored afterwards.
var _lobby_code_copied_timer: float = 0.0
# Bottom right label showing the local player's Steam name.
var username_display: Label = null

# Which world the player is in: overworld or cave.
var current_world_layer: String = "overworld"
# Which world each floor item belongs to.
var floor_item_layers: Dictionary = {}
# True if Steam started correctly.
var steam_connected: bool = false


# Returns cave or overworld depending on where the player is.
func _get_current_world_layer() -> String:
	var cave_gen = get_node_or_null("CaveWorldGen")
	if cave_gen and cave_gen.get("in_cave"):
		return "cave"
	return "overworld"


# Shows floor items that belong to the current world and hides the others.
func _refresh_floor_item_visibility():
	var layer = _get_current_world_layer()
	for item_id in floor_items:
		var item = floor_items[item_id]
		if is_instance_valid(item):
			var matches = floor_item_layers.get(item_id, "overworld") == layer
			item.visible = matches
			item.process_mode = Node.PROCESS_MODE_INHERIT if matches else Node.PROCESS_MODE_DISABLED
			for child in item.get_children():
				if child is CollisionShape2D or child is CollisionPolygon2D:
					child.disabled = not matches


# Host function. Drops an item on the floor, joining an existing pile if one is close, and tells the other players.
func host_spawn_floor_item(world_position: Vector2, item_type: String = "Wood", durability: int = 60) -> int:
	var layer = _get_current_world_layer()
	if not item_type in NON_STACKABLE_FLOOR_ITEMS and not _is_fish_item_name(item_type):
		for item_id in floor_items:
			var item = floor_items[item_id]
			if not is_instance_valid(item):
				continue
			if floor_item_layers.get(item_id, "overworld") != layer:
				continue
			if item.get("item_type") != item_type:
				continue
			if item.global_position.distance_to(world_position) > 48.0:
				continue
			if item.get("stack_count") >= 99:
				continue
			if multiplayer.has_multiplayer_peer():
				increment_floor_item_rpc.rpc(item_id)
			else:
				item.stack_count += 1
				item._update_label()
			return item_id
	var id = next_item_id
	next_item_id += 1
	floor_item_layers[id] = layer
	if multiplayer.has_multiplayer_peer():
		spawn_floor_item_rpc.rpc(id, world_position.x, world_position.y, item_type, durability, layer)
	else:
		_do_spawn_floor_item(id, world_position.x, world_position.y, item_type, durability, layer)
	return id


# Creates the floor item scene that matches the item type and sets it up.
func _do_spawn_floor_item(
	item_id: int,
	pos_x: float,
	pos_y: float,
	item_type: String = "Wood",
	durability: int = 60,
	layer: String = "overworld",
):
	if floor_items.has(item_id):
		return
	floor_item_layers[item_id] = layer
	if item_type == "Wardrobe":
		var wardrobe_scene = preload("res://Scenes/wardrobe.tscn")
		var wardrobe = wardrobe_scene.instantiate()
		wardrobe.setup_floor(item_id)
		wardrobe.global_position = Vector2(pos_x, pos_y)
		floor_items[item_id] = wardrobe
		add_child(wardrobe)
		wardrobe.visible = (layer == _get_current_world_layer())
		return
	var item_scene: PackedScene
	if _is_fish_item_name(item_type):
		match item_type:
			"Perch", "Albino Perch":
				item_scene = preload("res://Scenes/perch.tscn")
			"Catfish", "Albino Catfish":
				item_scene = preload("res://Scenes/catfish.tscn")
			"Bass", "Albino Bass":
				item_scene = preload("res://Scenes/bass.tscn")
			"Minnow", "Albino Minnow":
				item_scene = preload("res://Scenes/minnow.tscn")
			"Sturgeon", "Albino Sturgeon":
				item_scene = preload("res://Scenes/sturgeon.tscn")
			"Pike", "Albino Pike":
				item_scene = preload("res://Scenes/pike.tscn")
			"Blue Tang", "Albino Blue Tang":
				item_scene = preload("res://Scenes/blue_tang.tscn")
			"Clownfish", "Albino Clownfish":
				item_scene = preload("res://Scenes/clownfish.tscn")
			"Lionfish", "Albino Lionfish":
				item_scene = preload("res://Scenes/lionfish.tscn")
			"Tire", "Albino Tire":
				item_scene = preload("res://Scenes/tire.tscn")
			"Salmon", "Albino Salmon":
				item_scene = preload("res://Scenes/salmon.tscn")
			"Red Tang", "Albino Red Tang":
				item_scene = preload("res://Scenes/red_tang.tscn")
			"Guppy", "Albino Guppy":
				item_scene = preload("res://Scenes/guppy.tscn")
			"Snapper", "Albino Snapper":
				item_scene = preload("res://Scenes/snapper.tscn")
			"Muskie", "Albino Muskie":
				item_scene = preload("res://Scenes/muskie.tscn")
			"Ghost Eel", "Albino Ghost Eel":
				item_scene = preload("res://Scenes/ghost_eel.tscn")
			"Crystal Creeper", "Albino Crystal Creeper":
				item_scene = preload("res://Scenes/crystal_creeper.tscn")
			_:
				return
	else:
		match item_type:
			"Wood":
				item_scene = preload("res://Scenes/wood.tscn")
			"Wood Plank":
				item_scene = preload("res://Scenes/wooden_plank.tscn")
			"Axe":
				item_scene = preload("res://Scenes/wooden_axe.tscn")
			"Sword":
				item_scene = preload("res://Scenes/wooden_sword.tscn")
			"Pickaxe":
				item_scene = preload("res://Scenes/wooden_pickaxe.tscn")
			"Crafting_Bench":
				item_scene = preload("res://Scenes/crafting_bench.tscn")
			"Stone":
				item_scene = preload("res://Scenes/stone.tscn")
			"Stone Axe":
				item_scene = preload("res://Scenes/stone_axe.tscn")
			"Stone Sword":
				item_scene = preload("res://Scenes/stone_sword.tscn")
			"Stone Pickaxe":
				item_scene = preload("res://Scenes/stone_pickaxe.tscn")
			"Chicken_Raw":
				item_scene = preload("res://Scenes/chicken_raw.tscn")
			"String":
				item_scene = preload("res://Scenes/string.tscn")
			"Coal":
				item_scene = preload("res://Scenes/coal.tscn")
			"Torch":
				item_scene = preload("res://Scenes/torch.tscn")
			"Fishing Rod":
				item_scene = preload("res://Scenes/fishing_rod.tscn")
			"Stone Fishing Rod":
				item_scene = preload("res://Scenes/stone_fishing_rod.tscn")
			"Copper Fishing Rod":
				item_scene = preload("res://Scenes/copper_fishing_rod.tscn")
			_:
				item_scene = preload("res://Scenes/wood.tscn")
	var item = item_scene.instantiate()
	item.item_id = item_id
	if _is_fish_item_name(item_type):
		item.item_type = item_type
		item.durability = durability
		item.set_meta("item_name", item_type)
	elif item_type in [
		"Axe", "Sword", "Pickaxe", "Stone Axe", "Stone Sword", "Stone Pickaxe",
		"Fishing Rod", "Stone Fishing Rod", "Copper Fishing Rod",
	]:
		item.durability = durability
	item.global_position = Vector2(pos_x, pos_y)
	floor_items[item_id] = item
	add_child(item)
	item.visible = (layer == _get_current_world_layer())


# Removes a floor item from the world.
func remove_floor_item(item_id: int):
	floor_item_layers.erase(item_id)
	if floor_items.has(item_id):
		if is_instance_valid(floor_items[item_id]):
			floor_items[item_id].queue_free()
		floor_items.erase(item_id)

# Creates a floor item on every player's game.
@rpc("any_peer", "call_local", "reliable")


func spawn_floor_item_rpc(
	item_id: int,
	pos_x: float,
	pos_y: float,
	item_type: String = "Wood",
	durability: int = 1,
	layer: String = "overworld",
):
	_do_spawn_floor_item(item_id, pos_x, pos_y, item_type, durability, layer)


# Sends every floor item to a player who has just joined.
func sync_floor_items_to_peer(peer_id: int):
	if not multiplayer.get_peers().has(peer_id):
		return
	for item_id in floor_items:
		var item = floor_items[item_id]
		if not is_instance_valid(item):
			continue
		var world_position = item.global_position
		var script_path = item.get_script().resource_path
		var item_type: String
		if item.has_meta("item_name"):
			item_type = item.get_meta("item_name")
		elif script_path.contains("wooden_plank"):
			item_type = "Wood Plank"
		elif script_path.contains("wooden_axe"):
			item_type = "Axe"
		elif script_path.contains("wooden_sword"):
			item_type = "Sword"
		elif script_path.contains("stone_axe"):
			item_type = "Stone Axe"
		elif script_path.contains("stone_sword"):
			item_type = "Stone Sword"
		elif script_path.contains("stone_pickaxe"):
			item_type = "Stone Pickaxe"
		elif script_path.contains("pickaxe"):
			item_type = "Pickaxe"
		elif script_path.contains("stone_fishing_rod"):
			item_type = "Stone Fishing Rod"
		elif script_path.contains("fishing_rod"):
			item_type = "Fishing Rod"
		elif script_path.contains("copper_fishing_rod"):
			item_type = "Copper Fishing Rod"
		elif script_path.contains("crafting_bench"):
			item_type = "Crafting_Bench"
		elif script_path.contains("stone"):
			item_type = "Stone"
		elif script_path.contains("wardrobe"):
			item_type = "Wardrobe"
		elif script_path.contains("chicken_raw"):
			item_type = "Chicken_Raw"
		elif script_path.contains("string"):
			item_type = "String"
		elif script_path.contains("coal"):
			item_type = "Coal"
		elif script_path.contains("torch"):
			item_type = "Torch"
		else:
			item_type = "Wood"
		var dur: int = item.durability if item.get("durability") != null else 1
		var layer = floor_item_layers.get(item_id, "overworld")
		spawn_floor_item_rpc.rpc_id(peer_id, item_id, world_position.x, world_position.y, item_type, dur, layer)

# Names of every fish item.
const FISH_ITEM_NAMES: Array = [
	"Tophat Fish", "Albino Tophat Fish",
	"Minnow", "Albino Minnow",
	"Perch", "Albino Perch",
	"Bass", "Albino Bass",
	"Pike", "Albino Pike",
	"Catfish", "Albino Catfish",
	"Sturgeon", "Albino Sturgeon",
	"Salmon", "Albino Salmon",
	"Clownfish", "Albino Clownfish",
	"Blue Tang", "Albino Blue Tang",
	"Red Tang", "Albino Red Tang",
	"Lionfish", "Albino Lionfish",
	"Tire", "Albino Tire",
	"Guppy", "Albino Guppy",
	"Snapper", "Albino Snapper",
	"Muskie", "Albino Muskie",
	"Ghost Eel", "Albino Ghost Eel",
	"Crystal Creeper", "Albino Crystal Creeper",
]

# Items that always make their own pile and never join another.
const NON_STACKABLE_FLOOR_ITEMS: Array = [
	"Axe", "Sword", "Pickaxe", "Stone Axe", "Stone Sword", "Stone Pickaxe",
	"Wardrobe", "Fishing Rod", "Stone Fishing Rod",
	"Tophat Fish", "Albino Tophat Fish",
	"Minnow", "Albino Minnow",
	"Perch", "Albino Perch",
	"Bass", "Albino Bass",
	"Pike", "Albino Pike",
	"Catfish", "Albino Catfish",
	"Sturgeon", "Albino Sturgeon",
	"Salmon", "Albino Salmon",
	"Clownfish", "Albino Clownfish",
	"Blue Tang", "Albino Blue Tang",
	"Red Tang", "Albino Red Tang",
	"Lionfish", "Albino Lionfish",
	"Tire", "Albino Tire",
	"Guppy", "Albino Guppy",
	"Snapper", "Albino Snapper",
	"Muskie", "Albino Muskie",
	"Ghost Eel", "Albino Ghost Eel",
	"Crystal Creeper", "Albino Crystal Creeper",
	"Copper Fishing Rod",
]


# Returns true if the item is a fish.
func _is_fish_item_name(item_name: String) -> bool:
	if item_name in FISH_ITEM_NAMES:
		return true
	var fishing_manager = get_tree().root.get_node_or_null("FishingManager")
	if fishing_manager:
		for fish in fishing_manager.FISH_TABLE:
			var base_name: String = fish.get("name", "")
			if item_name == base_name or item_name == "Albino " + base_name:
				return true
	return false


# Starts Steam, connects the buttons and network signals and prepares the village and UI.
func _ready():
	y_sort_enabled = true
	get_tree().set_auto_accept_quit(false)
	var init_result = Steam.steamInitEx(480)
	print("Steam initialised: ", init_result)
	steam_connected = typeof(init_result) == TYPE_DICTIONARY \
		and int(init_result.get("status", 1)) == 0
	if steam_connected:
		Steam.initRelayNetworkAccess()
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	print("My Steam ID: ", Steam.getSteamID())
	_spawn_player(1)
	_show_steam_status_warning()
	_create_online_status_display()
	set_online_ui_visible(false)
	_init_village()


# Places the village at its spawn point and builds it.
func _init_village() -> void:
	var spawn_point = get_node_or_null("VillageSpawnPoint")
	if spawn_point:
		VillageManager.global_position = spawn_point.global_position
	VillageManager.preload_village()


# Shows or hides the host and join controls, but keeps them hidden once already connected to a lobby, regardless of what is asked for.
func set_online_ui_visible(should_show: bool) -> void:
	# Only actually show the controls if the game is not already in a lobby.
	var show_it: bool = should_show and lobby_id == 0
	if host_button:
		host_button.visible = show_it
	if join_button:
		join_button.visible = show_it
	if id_prompt:
		id_prompt.visible = show_it


# Creates the bottom right stack showing the online username and, once in a lobby, the lobby code.
# Uses a VBoxContainer with a bottom right anchor preset so Godot handles the stacking and screen
# corner placement itself, instead of hand rolled anchor and offset math.
func _create_online_status_display() -> void:
	var canvas: CanvasLayer = get_node_or_null("CanvasLayer")
	if not canvas:
		return

	var container := VBoxContainer.new()
	container.name = "OnlineStatusDisplay"
	container.alignment = BoxContainer.ALIGNMENT_END
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.z_index = 4096
	canvas.add_child(container)
	# Anchors the container's bottom right corner 14 pixels in from the screen's bottom right corner,
	# and keeps it there as its content (and therefore its size) changes.
	container.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_KEEP_SIZE, 14)

	username_display = Label.new()
	username_display.name = "UsernameDisplay"
	username_display.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	username_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	username_display.add_theme_font_size_override("font_size", 18)
	username_display.add_theme_color_override("font_color", Color.WHITE)
	username_display.add_theme_color_override("font_outline_color", Color.BLACK)
	username_display.add_theme_constant_override("outline_size", 4)
	container.add_child(username_display)

	lobby_code_display = Button.new()
	lobby_code_display.name = "LobbyCodeDisplay"
	lobby_code_display.flat = true
	lobby_code_display.mouse_filter = Control.MOUSE_FILTER_STOP
	lobby_code_display.add_theme_font_size_override("font_size", 20)
	lobby_code_display.add_theme_color_override("font_color", Color.WHITE)
	lobby_code_display.add_theme_color_override("font_hover_color", Color(0.85, 0.85, 0.85, 1.0))
	lobby_code_display.add_theme_color_override("font_outline_color", Color.BLACK)
	lobby_code_display.add_theme_constant_override("outline_size", 4)
	lobby_code_display.visible = false
	lobby_code_display.pressed.connect(_on_lobby_code_display_pressed)
	container.add_child(lobby_code_display)

	_update_username_display()


# Shows the player's Steam name, or a fallback if Steam is not connected.
func _update_username_display() -> void:
	if not username_display:
		return
	if steam_connected:
		username_display.text = Steam.getFriendPersonaName(Steam.getSteamID())
	else:
		username_display.text = "Player (offline)"


# Shows the lobby code button with the current code, for the host or a player who just joined.
func _show_lobby_code_display() -> void:
	if not lobby_code_display:
		return
	_lobby_code_copied_timer = 0.0
	lobby_code_display.text = "Code: " + str(lobby_id) + "  (click to copy)"
	lobby_code_display.visible = true


# Hides the lobby code button, for example when leaving a lobby to join another.
func _hide_lobby_code_display() -> void:
	if lobby_code_display:
		lobby_code_display.visible = false


# Copies the lobby code to the clipboard and briefly shows a confirmation.
func _on_lobby_code_display_pressed() -> void:
	if lobby_id == 0 or not lobby_code_display:
		return
	DisplayServer.clipboard_set(str(lobby_id))
	lobby_code_display.text = "Copied!"
	_lobby_code_copied_timer = 1.2


# Shows a warning on screen if Steam did not connect.
func _show_steam_status_warning() -> void:
	if steam_connected:
		return
	var canvas: CanvasLayer = get_node_or_null("CanvasLayer")
	if not canvas:
		return
	var label := Label.new()
	label.name = "SteamStatusWarning"
	label.text = "Not logged into Steam, online play disabled"
	label.position = Vector2(14, 14)
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 4096
	canvas.add_child(label)


# Runs Steam callbacks, finds the local player and updates floor items each frame.
func _process(delta):
	Steam.run_callbacks()
	local_player = null
	for child in get_children():
		if child is CharacterBody2D and child.is_in_group("players"):
			if not multiplayer.has_multiplayer_peer() or child.is_multiplayer_authority():
				local_player = child
				break
	_update_floor_item_water_sinking(delta)
	if _lobby_code_copied_timer > 0.0:
		_lobby_code_copied_timer -= delta
		if _lobby_code_copied_timer <= 0.0 and lobby_code_display and lobby_id != 0:
			lobby_code_display.text = "Code: " + str(lobby_id) + "  (click to copy)"


# Sends the world seed, settings and destroyed objects to a joining player.
func _sync_world_to_peer(peer_id: int):
	var world_gen = get_node_or_null("WorldGen")
	var env_gen = get_node_or_null("EnvironmentGen")
	if not world_gen:
		return
	if world_gen.world_seed == 0:
		world_gen.world_seed = randi()
	synced_world_seed = world_gen.world_seed
	sync_world_rpc.rpc_id(
		peer_id,
		synced_world_seed,
		world_gen.tile_size,
		world_gen.biome_noise_frequency,
		world_gen.forest_threshold,
		destroyed_env_objects,
		env_object_hits
	)
	if env_gen:
		env_gen.set_world_seed(synced_world_seed)

# Receives the host's world settings and generates the same world.
@rpc("any_peer", "call_remote", "reliable")


func sync_world_rpc(
	new_seed: int,
	synced_tile_size: int,
	frequency: float,
	threshold: float,
	destroyed: Dictionary,
	hits: Dictionary,
):
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		return
	var world_gen = get_node_or_null("WorldGen")
	var env_gen = get_node_or_null("EnvironmentGen")
	if world_gen:
		world_gen.set_world_settings(new_seed, synced_tile_size, frequency, threshold)
	if env_gen:
		env_gen.set_world_seed(new_seed)
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		env_gen.apply_env_state(destroyed, hits)

# Host function. Adds damage to a tree or rock and destroys it when it has taken enough.
@rpc("any_peer", "call_remote", "reliable")


func request_hit_env_object(env_id: String, damage: int, max_hits: int):
	if multiplayer.has_multiplayer_peer() and not is_host:
		return
	var current_hits = int(env_object_hits.get(env_id, 0)) + damage
	if current_hits >= max_hits:
		destroyed_env_objects[env_id] = true
		env_object_hits.erase(env_id)
		sync_destroy_env_object.rpc(env_id)
	else:
		env_object_hits[env_id] = current_hits
		sync_env_object_hits.rpc(env_id, current_hits)

# Removes a destroyed tree or rock on every player's game.
@rpc("authority", "call_local", "reliable")


func sync_destroy_env_object(env_id: String):
	destroyed_env_objects[env_id] = true
	env_object_hits.erase(env_id)
	var env_gen = get_node_or_null("EnvironmentGen")
	if env_gen:
		env_gen.mark_destroyed(env_id)

# Updates the hits a tree or rock has taken on every player's game.
@rpc("authority", "call_local", "reliable")


func sync_env_object_hits(env_id: String, hits: int):
	env_object_hits[env_id] = hits
	var env_gen = get_node_or_null("EnvironmentGen")
	if env_gen:
		env_gen.set_object_hits(env_id, hits)


# Starts joining the Steam lobby with the given ID.
func join_lobby(new_lobby_id: int):
	is_joining = true
	Steam.joinLobby(new_lobby_id)


# Creates a Steam lobby and starts hosting.
func host_lobby():
	if is_host:
		return
	is_host = true
	Steam.initRelayNetworkAccess()
	await get_tree().create_timer(2.0).timeout
	Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, 4)


# Called when the lobby exists. Starts the network host and shows the lobby ID.
func _on_lobby_created(result: int, new_lobby_id: int):
	if result != 1:
		is_host = false
		return
	lobby_id = new_lobby_id
	_show_lobby_code_display()
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
	if has_node("1"):
		var old = get_node("1")
		var ms = old.get_node_or_null("MultiplayerSynchronizer")
		if ms:
			ms.set_process(false)
			ms.set_physics_process(false)
		old.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	_spawn_player(multiplayer.get_unique_id())
	var world_gen = get_node_or_null("WorldGen")
	if world_gen:
		if world_gen.world_seed == 0:
			world_gen.world_seed = randi()
		synced_world_seed = world_gen.world_seed
	var env_gen = get_node_or_null("EnvironmentGen")
	if env_gen:
		env_gen.set_world_seed(synced_world_seed)
	peer_to_steam_id[multiplayer.get_unique_id()] = Steam.getSteamID()


# Called when the lobby has been joined. Connects to the host.
func _on_lobby_joined(new_lobby_id: int, _permissions: int, _locked: bool, response: int):
	print("Lobby joined response: ", response)
	if not is_joining:
		return
	lobby_id = new_lobby_id
	_show_lobby_code_display()
	_clear_world_state()
	_clear_inventory()
	await get_tree().create_timer(1.0).timeout
	peer = SteamMultiplayerPeer.new()
	peer.server_relay = true
	var lobby_owner = Steam.getLobbyOwner(lobby_id)
	print("Lobby owner: ", lobby_owner)
	print("My steam ID: ", Steam.getSteamID())
	peer.create_client(lobby_owner)
	print("Peer status after create_client: ", peer.get_connection_status())
	multiplayer.multiplayer_peer = peer
	is_joining = false
	multiplayer.server_disconnected.connect(_on_host_disconnected)
	multiplayer.peer_disconnected.connect(_remove_player)
	if has_node("1"):
		get_node("1").queue_free()
		await get_tree().process_frame
	var wait_time = 0.0
	while peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING and wait_time < 15.0:
		await get_tree().create_timer(0.5).timeout
		wait_time += 0.5
		print("Still connecting... ", wait_time, "s  status: ", peer.get_connection_status())
	print("Final peer status: ", peer.get_connection_status())
	print("Unique ID: ", multiplayer.get_unique_id())
	var my_id = multiplayer.get_unique_id()
	if my_id != 0 and my_id != 1:
		_spawn_player(my_id)
	else:
		print("ERROR: never connected after 15 seconds")


# Host function. A player connected, so spawn them and send them the world.
func _on_peer_connected(id: int):
	print("Peer connected on host: ", id)
	_spawn_player(id)
	_sync_world_to_peer(id)
	var weather = get_node_or_null("Weather")
	if weather:
		weather.sync_weather_state.rpc_id(
			id, weather.current_weather, weather.time_of_day, weather.weather_timer,
		)
	await get_tree().create_timer(6.0).timeout
	if not multiplayer.get_peers().has(id):
		return
	var ids_to_send: Array[int] = []
	for child in get_children():
		if child.name.is_valid_int():
			ids_to_send.append(child.name.to_int())
	sync_players_to_client.rpc_id(id, ids_to_send)
	sync_floor_items_to_peer(id)
	var fishing_manager = get_node_or_null("/root/FishingManager")
	if fishing_manager:
		fishing_manager.sync_fishing_state_to_peer(id)
	sync_placed_blocks_to_peer(id)
	sync_chickens_and_enemies_to_peer(id)
	var chat = get_node_or_null("CanvasLayer/Chat_Box")
	if chat:
		await get_tree().create_timer(1.0).timeout
		var steam_id = peer_to_steam_id.get(id, 0)
		var player_name = ""
		if steam_id != 0:
			player_name = Steam.getFriendPersonaName(steam_id)
		if player_name == "" or player_name == null:
			player_name = "A player"
		chat._broadcast_message.rpc(player_name + " joined the world")


# Quits the game when the host leaves.
func _on_host_disconnected():
	get_tree().quit()


# Removes all items, trees, rocks and blocks, for example when joining a new game.
func _clear_world_state():
	for item_id in floor_items:
		if is_instance_valid(floor_items[item_id]):
			floor_items[item_id].queue_free()
	floor_items.clear()
	for block_id in placed_blocks:
		if is_instance_valid(placed_blocks[block_id]):
			placed_blocks[block_id].queue_free()
	placed_blocks.clear()
	for tree_id in trees:
		if is_instance_valid(trees[tree_id]):
			trees[tree_id].queue_free()
	trees.clear()
	for rock_id in rocks:
		if is_instance_valid(rocks[rock_id]):
			rocks[rock_id].queue_free()
	rocks.clear()
	destroyed_env_objects.clear()
	env_object_hits.clear()


# Empties the hotbar and backpack.
func _clear_inventory():
	for i in Inventory.slots.size():
		Inventory.slots[i] = {"item": "", "count": 0, "texture": null}
	for i in Inventory.inv_slots.size():
		Inventory.inv_slots[i] = {"item": "", "count": 0, "texture": null}
	Inventory.inventory_changed.emit()

# Spawns the players who were already in the game for a joining player.
@rpc("authority", "call_remote", "reliable")


func sync_players_to_client(ids: Array[int]):
	for id in ids:
		_spawn_player(id)


# Creates a player character with the given network ID.
func _spawn_player(id: int):
	if has_node(str(id)):
		return
	if player_scene == null:
		print("ERROR: player_scene is null! Assign it in the inspector.")
		return
	var player = player_scene.instantiate()
	player.name = str(id)
	player.set_multiplayer_authority(id, true)
	add_child(player)
	player.global_position = _find_safe_spawn(Vector2(0, 0))


# Removes a player who left.
func _remove_player(id: int):
	if not has_node(str(id)):
		return
	get_node(str(id)).queue_free()

# Removes a player who left on every other player's game.
@rpc("authority", "call_remote", "reliable")


func remove_player_on_clients(id: int):
	if has_node(str(id)):
		get_node(str(id)).queue_free()


# Returns a new ID for a tree.
func spawn_tree_with_id(world_position: Vector2) -> int:
	var id = next_tree_id
	next_tree_id += 1
	return id


# Returns a new ID for a rock.
func spawn_rock_with_id(world_position: Vector2) -> int:
	var id = next_rock_id
	next_rock_id += 1
	return id


# Removes a tree from the world.
func remove_tree(tree_id: int):
	if trees.has(tree_id):
		if is_instance_valid(trees[tree_id]):
			trees[tree_id].queue_free()
		trees.erase(tree_id)

# Removes a tree on every player's game.
@rpc("authority", "call_local", "reliable")


func sync_remove_tree(tree_id: int):
	remove_tree(tree_id)


# Removes a rock from the world.
func remove_rock(rock_id: int):
	if rocks.has(rock_id):
		if is_instance_valid(rocks[rock_id]):
			rocks[rock_id].queue_free()
		rocks.erase(rock_id)

# Removes a rock on every player's game.
@rpc("authority", "call_local", "reliable")


func sync_remove_rock(rock_id: int):
	remove_rock(rock_id)

# Creates a placed block on every player's game.
@rpc("authority", "call_local", "reliable")


func place_block_rpc(
	block_id: int,
	item_name: String,
	pos_x: float,
	pos_y: float,
	rotation_angle: float = 0.0,
):
	_do_place_block(block_id, item_name, pos_x, pos_y, rotation_angle)


# Host function. Gives a new block an ID and tells everyone to create it.
func host_place_block(
	item_name: String,
	world_position: Vector2,
	rotation_angle: float = 0.0,
	tex: Texture2D = null,
) -> int:
	var id = next_block_id
	next_block_id += 1
	if item_name == "Wardrobe":
		if multiplayer.has_multiplayer_peer():
			place_wardrobe_rpc.rpc(id, world_position.x, world_position.y)
		else:
			_do_place_wardrobe(id, world_position.x, world_position.y)
		return id
	if multiplayer.has_multiplayer_peer():
		place_block_rpc.rpc(id, item_name, world_position.x, world_position.y, rotation_angle)
	else:
		_do_place_block(id, item_name, world_position.x, world_position.y, rotation_angle)
	return id

# Creates a placed wardrobe on every player's game.
@rpc("authority", "call_local", "reliable")


func place_wardrobe_rpc(block_number: int, pos_x: float, pos_y: float):
	_do_place_wardrobe(block_number, pos_x, pos_y)


# Creates a wardrobe block.
func _do_place_wardrobe(block_number: int, pos_x: float, pos_y: float):
	if placed_blocks.has(block_number):
		return
	var wardrobe_scene = preload("res://Scenes/wardrobe.tscn")
	var wardrobe = wardrobe_scene.instantiate()
	wardrobe.setup_placed(block_number)
	placed_blocks[block_number] = wardrobe
	add_child(wardrobe)
	wardrobe.global_position = Vector2(pos_x, pos_y)


# Creates a block of the right kind at a position.
func _do_place_block(
	block_id: int,
	item_name: String,
	pos_x: float,
	pos_y: float,
	rotation_angle: float = 0.0,
):
	if placed_blocks.has(block_id):
		return
	if item_name == "Wardrobe":
		var wardrobe_scene = preload("res://Scenes/wardrobe.tscn")
		var wardrobe = wardrobe_scene.instantiate()
		wardrobe.setup_placed(block_id)
		wardrobe.global_position = Vector2(pos_x, pos_y)
		placed_blocks[block_id] = wardrobe
		add_child(wardrobe)
		return
	var block_scene = preload("res://Scenes/placed_block.tscn")
	var block = block_scene.instantiate()
	block.setup(item_name, _get_item_texture(item_name), block_id, 0.0)
	block.global_position = Vector2(pos_x, pos_y)
	placed_blocks[block_id] = block
	add_child(block)


# Finds the picture of an item from the inventory.
func _get_item_texture(item_name: String) -> Texture2D:
	for slot in Inventory.slots:
		if slot["item"] == item_name and slot["texture"] != null:
			return slot["texture"]
	for slot in Inventory.inv_slots:
		if slot["item"] == item_name and slot["texture"] != null:
			return slot["texture"]
	return Inventory.get_texture(item_name)


# Removes a placed block from the world.
func remove_placed_block(block_id: int):
	if placed_blocks.has(block_id):
		if is_instance_valid(placed_blocks[block_id]):
			placed_blocks[block_id].queue_free()
		placed_blocks.erase(block_id)

# Removes a placed block on every player's game.
@rpc("authority", "call_local", "reliable")


func sync_remove_placed_block(block_id: int):
	remove_placed_block(block_id)

# Sent by a client. The host places the block.
@rpc("any_peer", "call_remote", "reliable")


func request_place_block(item_name: String, pos_x: float, pos_y: float, rotation_angle: float = 0.0):
	if not is_host:
		return
	host_place_block(item_name, Vector2(pos_x, pos_y), rotation_angle)

# Sent by a client. The host breaks the block.
@rpc("any_peer", "call_remote", "reliable")


func request_break_block(block_id: int):
	if not is_host:
		return
	process_block_hit(block_id)


# Sends every placed block to a player who has just joined.
func sync_placed_blocks_to_peer(peer_id: int):
	if not multiplayer.get_peers().has(peer_id):
		return
	for block_id in placed_blocks:
		var block = placed_blocks[block_id]
		if is_instance_valid(block):
			if block.get_script() and block.get_script().resource_path.contains("wardrobe"):
				place_wardrobe_rpc.rpc_id(peer_id, block_id, block.global_position.x, block.global_position.y)
			else:
				place_block_rpc.rpc_id(
					peer_id, block_id, block.item_name,
					block.global_position.x, block.global_position.y, 0.0,
				)


# Host function. Adds a hit to a block and breaks it when it has taken enough.
func process_block_hit(block_id: int):
	if not placed_blocks.has(block_id):
		return
	var block = placed_blocks[block_id]
	if not is_instance_valid(block):
		return
	block.hits += 1
	if block.hits >= block.max_hits:
		var drop_pos = block.global_position + Vector2(randf_range(-20, 20), randf_range(-20, 20))
		var drop_item = block.get("item_name") if block.get("item_name") != "" else "Wardrobe"
		host_spawn_floor_item(drop_pos, drop_item)
		if multiplayer.has_multiplayer_peer():
			sync_remove_placed_block.rpc(block_id)
		else:
			remove_placed_block(block_id)

# Sent by a client. The host processes the hit.
@rpc("any_peer", "call_local", "reliable")


func register_block_hit(block_id: int):
	if not is_host:
		return
	process_block_hit(block_id)

# Adds one to a floor pile's count on every player's game.
@rpc("authority", "call_local", "reliable")


func increment_floor_item_rpc(item_id: int):
	if floor_items.has(item_id) and is_instance_valid(floor_items[item_id]):
		floor_items[item_id].stack_count += 1
		floor_items[item_id]._update_label()

# Sent by a client. The host drops the item.
@rpc("any_peer", "call_remote", "reliable")


func request_spawn_floor_item(
	pos_x: float,
	pos_y: float,
	item_type: String = "Wood",
	durability: int = 1,
):
	if not is_host:
		return
	host_spawn_floor_item(Vector2(pos_x, pos_y), item_type, durability)

# Removes a floor item on every player's game.
@rpc("authority", "call_local", "reliable")


func sync_remove_floor_item(item_id: int):
	remove_floor_item(item_id)

# Sent by a client. The host removes the item everywhere.
@rpc("any_peer", "call_remote", "reliable")


func request_remove_floor_item(item_id: int):
	if not is_host:
		return
	sync_remove_floor_item.rpc(item_id)


# Leaves the Steam lobby when the window is closed.
func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if lobby_id != 0:
			Steam.leaveLobby(lobby_id)
		get_tree().quit()


# The host button was pressed.
func _on_host_button_pressed():
	host_lobby()


# Enables the join button only when a lobby ID has been typed.
func _on_id_prompt_text_changed(new_text):
	join_button.disabled = new_text.length() == 0


# Leaves any current lobby, clears the world and joins the lobby typed in.
func _on_join_button_pressed():
	var new_lobby_id = id_prompt.text.to_int()
	if lobby_id != 0:
		Steam.leaveLobby(lobby_id)
		lobby_id = 0
		_hide_lobby_code_display()
		if multiplayer.multiplayer_peer:
			multiplayer.multiplayer_peer = null
		is_host = false
		_clear_world_state()
		_clear_inventory()
		var to_remove = []
		for child in get_children():
			if child.name.is_valid_int():
				to_remove.append(child)
		for child in to_remove:
			child.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		_spawn_player(1)
	join_lobby(new_lobby_id)

# Sent by a client. The host damages the target player.
@rpc("any_peer", "call_remote", "reliable")


func request_deal_damage(target_id: int, amount: int):
	if not is_host:
		return
	if has_node(str(target_id)):
		var target = get_node(str(target_id))
		if target is CharacterBody2D and target.is_in_group("players"):
			deal_damage_to_player.rpc_id(target_id, amount)


# Damages a player, on the host directly or by asking the player's own game.
func apply_damage_to_player(target: Node, amount: int, enemy: Node = null) -> void:
	if not target or not is_instance_valid(target):
		return
	if not target.is_in_group("players"):
		return
	if not multiplayer.has_multiplayer_peer() or target.is_multiplayer_authority():
		if target.has_method("defend_enemy_attack"):
			target.defend_enemy_attack(amount, enemy)
		elif target.has_method("take_damage"):
			target.take_damage(amount)
		return
	var enemy_id: int = int(enemy.get("enemy_id")) if enemy and "enemy_id" in enemy else -1
	enemy_attack_player.rpc_id(target.name.to_int(), amount, enemy_id)

# Sent by the host. The player's game reacts to an enemy attack, including blocking.
@rpc("authority", "call_remote", "reliable")


func enemy_attack_player(amount: int, enemy_id: int):
	var target := get_node_or_null(str(multiplayer.get_unique_id()))
	if not target or not is_instance_valid(target):
		return
	if not target.is_in_group("players") or not target.is_multiplayer_authority():
		return
	var enemy := _find_night_enemy(enemy_id)
	if target.has_method("defend_enemy_attack"):
		target.defend_enemy_attack(amount, enemy)
	elif target.has_method("take_damage"):
		target.take_damage(amount)


# Returns the enemy with the given ID, or null.
func _find_night_enemy(enemy_id: int) -> Node:
	for enemy in get_tree().get_nodes_in_group("night_enemies"):
		if enemy.get("enemy_id") == enemy_id:
			return enemy
	return null

# Sent by a client. The host damages the enemy.
@rpc("any_peer", "call_remote", "reliable")


func request_damage_night_enemy(enemy_id: int, amount: int):
	if not is_host:
		return
	var enemy = _find_night_enemy(enemy_id)
	if enemy and enemy.has_method("take_damage"):
		enemy.take_damage(amount)


# Returns the boss with the given ID, or null.
func _find_boss(boss_id: int) -> Node:
	for boss in get_tree().get_nodes_in_group("bosses"):
		if is_instance_valid(boss) and int(boss.get("enemy_id")) == boss_id:
			return boss
	return null

# Sent by a client. The host damages the boss.
@rpc("any_peer", "call_remote", "reliable")


func request_damage_boss(boss_id: int, amount: int):
	if not is_host:
		return
	var boss = _find_boss(boss_id)
	if boss and boss.has_method("take_damage"):
		boss.take_damage(amount)

# Sent by the host. Damages the local player.
@rpc("authority", "call_remote", "reliable")


func deal_damage_to_player(amount: int):
	var target := get_node_or_null(str(multiplayer.get_unique_id()))
	if target and is_instance_valid(target) and target.is_in_group("players") \
		and target.is_multiplayer_authority():
		target.take_damage(amount)

# Sent by a client. The host chops the tree.
@rpc("any_peer", "call_remote", "reliable")


func request_chop_env_tree(env_id: String, held_item: String):
	if not is_host:
		return
	var env_gen = get_node_or_null("EnvironmentGen")
	if not env_gen:
		return
	if not env_gen.active_objects.has(env_id):
		return
	var tree = env_gen.active_objects[env_id]
	if not is_instance_valid(tree):
		return
	var sender_id = multiplayer.get_remote_sender_id()
	tree.do_chop(sender_id, held_item)

# Sent by the host. Wears down the axe on the player's own game.
@rpc("authority", "call_remote", "reliable")


func consume_axe_on_client():
	var hotbar = get_tree().root.get_node_or_null("Scene/CanvasLayer/Hotbar")
	if not hotbar:
		return
	var slot_index = hotbar.current_slot - 1
	var current = Inventory.slots[slot_index]
	if current["item"] in ["Axe", "Stone Axe"]:
		current["count"] -= 1
		if current["count"] <= 0:
			Inventory.remove_item(slot_index, false)
		else:
			Inventory.inventory_changed.emit()

# Sent by a client. The host mines the rock.
@rpc("any_peer", "call_remote", "reliable")


func request_mine_env_rock(env_id: String, held_item: String):
	if not is_host:
		return
	var env_gen = get_node_or_null("EnvironmentGen")
	if not env_gen:
		return
	if not env_gen.active_objects.has(env_id):
		return
	var rock = env_gen.active_objects[env_id]
	if not is_instance_valid(rock):
		return
	var sender_id = multiplayer.get_remote_sender_id()
	rock.do_mine(sender_id, held_item)

# Sent by the host. Wears down the pickaxe on the player's own game.
@rpc("authority", "call_remote", "reliable")


func consume_pickaxe_on_client():
	var hotbar = get_tree().root.get_node_or_null("Scene/CanvasLayer/Hotbar")
	if not hotbar:
		return
	var slot_index = hotbar.current_slot - 1
	var current = Inventory.slots[slot_index]
	if current["item"] in ["Pickaxe", "Stone Pickaxe"]:
		current["count"] -= 1
		if current["count"] <= 0:
			Inventory.remove_item(slot_index, false)
		else:
			Inventory.inventory_changed.emit()

# Sent by a client. The host breaks the wardrobe and drops it.
@rpc("any_peer", "call_remote", "reliable")


func request_break_wardrobe(block_number: int, drop_x: float, drop_y: float):
	if not is_host:
		return
	var drop_pos = Vector2(drop_x, drop_y)
	host_spawn_floor_item(drop_pos, "Wardrobe", 1)
	for child in get_children():
		if child.get("block_id") == block_number:
			if child.has_method("remove_wardrobe_rpc"):
				child.remove_wardrobe_rpc.rpc(block_number)
			break


# Host function. Drops many items at once.
func host_spawn_floor_items_batch(positions: Array, item_type: String, durability: int = 1):
	for world_position in positions:
		host_spawn_floor_item(world_position, item_type, durability)

# Sent by a client. The host drops many items at once.
@rpc("any_peer", "call_remote", "reliable")


func request_spawn_floor_items_batch(
	positions_x: Array,
	positions_y: Array,
	item_type: String,
	durability: int = 1,
):
	if not is_host:
		return
	for i in positions_x.size():
		host_spawn_floor_item(Vector2(positions_x[i], positions_y[i]), item_type, durability)


# Host function. Spawns a chicken near a position.
func host_spawn_chicken(world_position: Vector2) -> void:
	if AnimalSpawner:
		AnimalSpawner._spawn_chicken(_find_safe_spawn(world_position))

# Removes the enemies of a combat room on every player's game.
@rpc("authority", "call_local", "reliable")


func despawn_room_entities_rpc(combat_room_id: int):
	for enemy in get_tree().get_nodes_in_group("night_enemies"):
		if is_instance_valid(enemy) and int(enemy.get_meta("combat_room_id", -999)) == combat_room_id:
			enemy.queue_free()
	for boss in get_tree().get_nodes_in_group("bosses"):
		if is_instance_valid(boss) and int(boss.get_meta("combat_room_id", -999)) == combat_room_id:
			boss.queue_free()

# Sent by a client. The host resets the cave room where the player died.
@rpc("any_peer", "call_remote", "reliable")


func request_room_death_reset(px: float, py: float):
	if not is_host:
		return
	var cave_gen = get_node_or_null("CaveWorldGen")
	if cave_gen and cave_gen.has_method("notify_player_died"):
		cave_gen.notify_player_died(Vector2(px, py))

# Sent by a client. The host spawns a boss.
@rpc("any_peer", "call_remote", "reliable")


func request_spawn_boss(key: String):
	if not is_host:
		return
	BossManager.spawn_by_key(key)

# Shows or hides the message that the boss room is waiting for players.
@rpc("authority", "call_local", "reliable")


func set_boss_wait_ui(waiting: bool, missing_count: int):
	var canvas: CanvasLayer = get_node_or_null("CanvasLayer")
	if not canvas:
		return
	var label: Label = canvas.get_node_or_null("BossWaitLabel")
	if waiting:
		if not label:
			label = Label.new()
			label.name = "BossWaitLabel"
			label.add_theme_font_size_override("font_size", 28)
			label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
			label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
			label.add_theme_constant_override("outline_size", 5)
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.set_anchors_preset(Control.PRESET_TOP_WIDE)
			label.offset_top = 90.0
			label.offset_bottom = 140.0
			label.z_index = 4096
			canvas.add_child(label)
		var word: String = "player" if missing_count == 1 else "players"
		label.text = "Waiting for %d more %s to enter..." % [missing_count, word]
		label.visible = true
	elif label:
		label.visible = false

# Sent by a client. The host kills the target player.
@rpc("any_peer", "call_remote", "reliable")


func request_kill_player(target_id: int):
	if not is_host:
		return
	if has_node(str(target_id)):
		var target = get_node(str(target_id))
		if target is CharacterBody2D and target.is_in_group("players"):
			deal_damage_to_player.rpc_id(target_id, target.max_health)


# Searches near a position for a spot that is not inside anything solid.
func _find_safe_spawn(origin: Vector2, max_attempts: int = 30) -> Vector2:
	var space = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 16.0
	query.shape = shape
	query.collision_mask = 1
	query.transform = Transform2D(0, origin)
	if space.intersect_shape(query).size() == 0:
		return origin
	for i in max_attempts:
		var angle = randf_range(0, TAU)
		var radius = randf_range(60.0, 80.0 + i * 10.0)
		var candidate = origin + Vector2(cos(angle), sin(angle)) * radius
		query.transform = Transform2D(0, candidate)
		if space.intersect_shape(query).size() == 0:
			return candidate
	return origin + Vector2(randf_range(-200, 200), randf_range(-200, 200))


# Sends every chicken and enemy to a player who has just joined.
func sync_chickens_and_enemies_to_peer(peer_id: int):
	if not multiplayer.get_peers().has(peer_id):
		return
	for chicken in get_tree().get_nodes_in_group("chickens"):
		if is_instance_valid(chicken):
			spawn_chicken_on_client_rpc.rpc_id(
				peer_id, chicken.global_position.x, chicken.global_position.y, chicken.chicken_id,
			)
	for enemy in get_tree().get_nodes_in_group("night_enemies"):
		if is_instance_valid(enemy):
			spawn_enemy_on_client_rpc.rpc_id(
				peer_id, enemy.global_position.x, enemy.global_position.y, enemy.enemy_id,
			)
	for boss in get_tree().get_nodes_in_group("bosses"):
		if is_instance_valid(boss):
			spawn_boss_on_client_rpc.rpc_id(
				peer_id, boss.global_position.x, boss.global_position.y, boss.get("enemy_id"),
			)

# Creates a chicken on a client's game.
@rpc("authority", "call_remote", "reliable")


func spawn_chicken_on_client_rpc(px: float, py: float, chicken_number: int):
	var node_name = "Chicken_" + str(chicken_number)
	if has_node(node_name):
		return
	var chicken_scene = preload("res://Scenes/chicken.tscn")
	var chicken = chicken_scene.instantiate()
	chicken.chicken_id = chicken_number
	chicken.name = node_name
	chicken.global_position = Vector2(px, py)
	chicken.set_multiplayer_authority(1)
	add_child(chicken)
	chicken.set_meta("sync_ready", false)
	await get_tree().create_timer(2.0).timeout
	if is_instance_valid(chicken):
		chicken.set_meta("sync_ready", true)

# Creates an enemy on a client's game.
@rpc("authority", "call_remote", "reliable")


func spawn_enemy_on_client_rpc(px: float, py: float, enemy_number: int):
	var node_name = "Enemy_" + str(enemy_number)
	if has_node(node_name):
		return
	var enemy_scene = preload("res://Scenes/night_enemy.tscn")
	var enemy = enemy_scene.instantiate()
	enemy.enemy_id = enemy_number
	enemy.name = node_name
	enemy.global_position = Vector2(px, py)
	enemy.set_multiplayer_authority(1)
	add_child(enemy)
	enemy.set_meta("sync_ready", false)
	await get_tree().create_timer(2.0).timeout
	if is_instance_valid(enemy):
		enemy.set_meta("sync_ready", true)

# Creates a boss on a client's game.
@rpc("authority", "call_remote", "reliable")


func spawn_boss_on_client_rpc(px: float, py: float, boss_number: int):
	var node_name = "Boss_" + str(boss_number)
	if has_node(node_name):
		return
	var boss_scene = preload("res://Scenes/spider_queen.tscn")
	var boss = boss_scene.instantiate()
	boss.set("enemy_id", boss_number)
	boss.name = node_name
	boss.global_position = Vector2(px, py)
	boss.set_multiplayer_authority(1)
	add_child(boss)
	boss.set_meta("sync_ready", false)
	await get_tree().create_timer(2.0).timeout
	if is_instance_valid(boss):
		boss.set_meta("sync_ready", true)

# Removes every chicken and enemy on every player's game.
@rpc("authority", "call_local", "reliable")


func clear_chickens_and_enemies_rpc():
	for chicken in get_tree().get_nodes_in_group("chickens"):
		if is_instance_valid(chicken):
			chicken.queue_free()
	for enemy in get_tree().get_nodes_in_group("night_enemies"):
		if is_instance_valid(enemy):
			enemy.queue_free()

# Sent by a client. The host finds a safe position and sends it back.
@rpc("any_peer", "call_remote", "reliable")


func request_respawn(player_id: int):
	if not is_host:
		return
	var spawn_pos = _find_safe_spawn(Vector2(0, 0))
	_preload_spawn_area(spawn_pos)
	send_respawn_position.rpc_id(player_id, spawn_pos.x, spawn_pos.y)

# Sent by the host. Loads the area and moves the player to the respawn position.
@rpc("authority", "call_remote", "reliable")


func send_respawn_position(px: float, py: float):
	var spawn_pos = Vector2(px, py)
	_preload_spawn_area(spawn_pos)
	var target := get_node_or_null(str(multiplayer.get_unique_id()))
	if target and is_instance_valid(target) and target.is_in_group("players") \
		and target.is_multiplayer_authority():
		target._do_respawn(spawn_pos)


# Asks the world generator to paint the chunks around a position.
func _preload_spawn_area(spawn_pos: Vector2) -> void:
	var world_gen = get_node_or_null("WorldGen")
	if world_gen and world_gen.has_method("queue_chunks_around_world_pos"):
		world_gen.queue_chunks_around_world_pos(spawn_pos, 2)
	var env_gen = get_node_or_null("EnvironmentGen")
	if env_gen and env_gen.has_method("queue_chunks_around_world_pos"):
		env_gen.queue_chunks_around_world_pos(spawn_pos, 2)


# Makes floor items that lie in water fade and sink.
func _update_floor_item_water_sinking(delta: float) -> void:
	var world_gen = get_node_or_null("WorldGen")
	var cave_gen = get_node_or_null("CaveWorldGen")
	for item_id in floor_items.keys():
		var item = floor_items[item_id]
		if not is_instance_valid(item) or not item.visible:
			continue
		var in_water := false
		if cave_gen and cave_gen.get("in_cave"):
			var tc: Vector2i = cave_gen.world_to_tile(item.global_position)
			in_water = cave_gen._water_tiles.has(tc)
		elif world_gen and world_gen.has_method("is_water_at"):
			in_water = world_gen.is_water_at(item.global_position)
		var c: Color = item.modulate
		if in_water:
			item.global_position.y += 18.0 * delta
			c.a = max(c.a - 0.18 * delta, 0.35)
		else:
			c.a = move_toward(c.a, 1.0, delta)
		item.modulate = c

# Sent by a client. The host records which Steam account owns the connection.
@rpc("any_peer", "call_remote", "reliable")


func register_steam_id(steam_id: int):
	if not is_host:
		return
	var sender = multiplayer.get_remote_sender_id()
	peer_to_steam_id[sender] = steam_id
	sync_peer_steam_ids.rpc(peer_to_steam_id)

# Sent by the host. Shares the list of Steam IDs with every player.
@rpc("authority", "call_local", "reliable")


func sync_peer_steam_ids(mapping: Dictionary):
	peer_to_steam_id = mapping

# Updates a chicken's position and state on a client's game.
@rpc("any_peer", "call_remote", "unreliable_ordered")


func sync_chicken_state_rpc(chicken_number: int, px: float, py: float, s: int) -> void:
	var chicken = get_node_or_null("Chicken_" + str(chicken_number))
	if not chicken or not is_instance_valid(chicken):
		return
	if not chicken.get_meta("sync_ready", false):
		return
	chicken.global_position = Vector2(px, py)
	chicken.state = s
	match s:
		0, 2: chicken.sprite.play("walk_down")
		1, 4: chicken.sprite.play("idle")

# Updates an enemy's position, state and health on a client's game.
@rpc("any_peer", "call_remote", "unreliable_ordered")


func sync_enemy_state_rpc(enemy_number: int, px: float, py: float, s: int, h: int) -> void:
	var enemy = get_node_or_null("Enemy_" + str(enemy_number))
	if not enemy or not is_instance_valid(enemy):
		return
	if not enemy.get_meta("sync_ready", false):
		return
	enemy.global_position = Vector2(px, py)
	enemy.state = s
	enemy.health = h
	if s == 0:
		enemy.sprite.play("walk_down")
	else:
		enemy.sprite.play("idle")

# Updates a boss's position and health on a client's game.
@rpc("any_peer", "call_remote", "unreliable_ordered")


func sync_boss_state_rpc(boss_number: int, px: float, py: float, h: int) -> void:
	var boss = get_node_or_null("Boss_" + str(boss_number))
	if not boss or not is_instance_valid(boss):
		return
	if not boss.get_meta("sync_ready", false):
		return
	boss.global_position = Vector2(px, py)
	boss.health = h

# Flashes a chicken red on every player's game.
@rpc("authority", "call_local", "reliable")


func chicken_flash_hit_rpc(chicken_number: int) -> void:
	var chicken = get_node_or_null("Chicken_" + str(chicken_number))
	if chicken and is_instance_valid(chicken):
		chicken._flash_hit()

# Plays a chicken's death on every player's game.
@rpc("authority", "call_local", "reliable")


func chicken_die_rpc(chicken_number: int) -> void:
	var chicken = get_node_or_null("Chicken_" + str(chicken_number))
	if chicken and is_instance_valid(chicken):
		chicken._play_die_sequence()

# Sets how faded a drowning chicken looks on every player's game.
@rpc("authority", "call_local", "reliable")


func chicken_drowning_alpha_rpc(chicken_number: int, alpha: float) -> void:
	var chicken = get_node_or_null("Chicken_" + str(chicken_number))
	if chicken and is_instance_valid(chicken):
		chicken._set_drowning_alpha(alpha)
