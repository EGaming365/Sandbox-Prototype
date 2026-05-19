extends Control

const ADMIN_STEAM_ID: int = 76561199247129478
const MAX_MESSAGES: int = 20
const HIDE_DELAY: float = 5.0

var messages: Array = []
var hide_timer: float = 0.0
var is_open: bool = false
var wood_texture: Texture2D = preload("res://Assets/Wood.png")
var axe_texture: Texture2D = preload("res://Assets/Axe.png")
var sword_texture: Texture2D = preload("res://Assets/Sword.png")
var pickaxe_texture: Texture2D = preload("res://Assets/Pickaxe.png")
var stone_texture: Texture2D = preload("res://Assets/Stone.png")
var stone_axe_texture: Texture2D = preload("res://Assets/Stone_Axe.png")
var stone_sword_texture: Texture2D = preload("res://Assets/Stone_Sword.png")
var stone_pickaxe_texture: Texture2D = preload("res://Assets/Stone_Pickaxe.png")
var wardrobe_texture: Texture2D = preload("res://Assets/Wardrobe.png")

@onready var scroll_container: ScrollContainer = $ChatContainer/ScrollContainer
@onready var messages_container: VBoxContainer = $ChatContainer/ScrollContainer/Messages
@onready var input_row: HBoxContainer = $ChatContainer/InputRow
@onready var input_field: LineEdit = $ChatContainer/InputRow/InputField

var _chat_close_cooldown: float = 0.0

func _get_steam_name_for_peer(peer_id: int) -> String:
	var my_steam_id = Steam.getSteamID()
	if peer_id == multiplayer.get_unique_id():
		return Steam.getFriendPersonaName(my_steam_id)
	var scene_node = get_tree().root.get_node_or_null("Scene")
	if scene_node:
		var steam_id = scene_node.peer_to_steam_id.get(peer_id, 0)
		if steam_id != 0:
			return Steam.getFriendPersonaName(steam_id)
	return "Unknown"

func _handle_command(text: String):
	var parts = text.split(" ")
	var cmd = parts[0].to_lower()
	var my_steam_id = Steam.getSteamID()
	match cmd:
		"/give":
			if my_steam_id != ADMIN_STEAM_ID:
				_add_message("[System] No permission.")
				return
			if parts.size() < 3:
				_add_message("[System] Usage: /give <player_name> <item_name> [amount]")
				return
			var amount = 1
			var item_name: String
			var target_name = parts[1]
			if parts[parts.size() - 1].is_valid_int() and parts.size() >= 4:
				amount = parts[parts.size() - 1].to_int()
				if amount <= 0:
					_add_message("[System] Amount must be greater than 0.")
					return
				item_name = " ".join(parts.slice(2, parts.size() - 1))
			else:
				item_name = " ".join(parts.slice(2))
			match item_name.to_lower():
				"wood": item_name = "Wood"
				"wood plank": item_name = "Wood Plank"
				"axe": item_name = "Axe"
				"sword": item_name = "Sword"
				"crafting bench": item_name = "Crafting_Bench"
				"stone": item_name = "Stone"
				"pickaxe": item_name = "Pickaxe"
				"wardrobe": item_name = "Wardrobe"
			_give_item_to_player(target_name, item_name, amount)
		"/weather":
			if my_steam_id != ADMIN_STEAM_ID:
				_add_message("[System] No permission.")
				return
			if parts.size() < 2:
				_add_message("[System] Usage: /weather <clear|rain|thunder|thunderstorm>")
				return
			var weather_node = get_tree().root.get_node_or_null("Scene/Weather")
			if not weather_node:
				_add_message("[System] WeatherSystem not found.")
				return
			match parts[1].to_lower():
				"clear":
					weather_node._set_weather(weather_node.WeatherType.CLEAR)
				"rain":
					weather_node._set_weather(weather_node.WeatherType.RAIN)
				"thunder":
					weather_node._set_weather(weather_node.WeatherType.THUNDER)
				"thunderstorm":
					weather_node._set_weather(weather_node.WeatherType.THUNDERSTORM)
				_:
					_add_message("[System] Unknown weather. Use: clear, rain, thunder, thunderstorm")
					return
			if multiplayer.has_multiplayer_peer():
				weather_node.sync_weather_state.rpc(weather_node.current_weather, weather_node.time_of_day, weather_node.weather_timer)
			_add_message("[System] Weather set to: " + parts[1].to_lower())
		"/tp", "/teleport":
			if my_steam_id != ADMIN_STEAM_ID:
				_add_message("[System] No permission.")
				return
			if parts.size() < 3:
				_add_message("[System] Usage: /tp <player> <x> <y>  OR  /tp <player> here  OR  /tp <player> <target_player>")
				return
			var scene_node = get_tree().root.get_node("Scene")
			var subject_matches = []
			for child in scene_node.get_children():
				if child is CharacterBody2D:
					var peer_id = child.get_multiplayer_authority()
					var sname = _get_steam_name_for_peer(peer_id)
					if sname.to_lower().begins_with(parts[1].to_lower()):
						subject_matches.append({"node": child, "peer_id": peer_id, "name": sname})
			if subject_matches.size() == 0:
				_add_message("[System] Player '" + parts[1] + "' not found.")
				return
			elif subject_matches.size() > 1:
				var names = ""
				for m in subject_matches:
					names += m["name"] + ", "
				_add_message("[System] Multiple players found: " + names.trim_suffix(", ") + ". Be more specific.")
				return
			var subject = subject_matches[0]
			var dest: Vector2
			if parts[2].to_lower() == "here":
				var local_player = _get_local_player()
				if not local_player:
					_add_message("[System] Could not find your position.")
					return
				dest = local_player.global_position
			elif parts.size() >= 4 and parts[2].is_valid_float() and parts[3].is_valid_float():
				dest = Vector2((parts[2].to_float() * 100), (parts[3].to_float()) * -100)
			else:
				var target_name = " ".join(parts.slice(2))
				var target_matches = []
				for child in scene_node.get_children():
					if child is CharacterBody2D:
						var peer_id = child.get_multiplayer_authority()
						var sname = _get_steam_name_for_peer(peer_id)
						if sname.to_lower().begins_with(target_name.to_lower()):
							target_matches.append({"node": child, "name": sname})
				if target_matches.size() == 0:
					_add_message("[System] Target '" + target_name + "' not found. Use: here, X Y coords, or a player name.")
					return
				elif target_matches.size() > 1:
					var names = ""
					for m in target_matches:
						names += m["name"] + ", "
					_add_message("[System] Multiple targets found: " + names.trim_suffix(", ") + ". Be more specific.")
					return
				dest = target_matches[0]["node"].global_position
			if subject["peer_id"] == multiplayer.get_unique_id():
				subject["node"].global_position = dest
			else:
				_rpc_teleport.rpc_id(subject["peer_id"], dest)
			_add_message("[System] Teleported " + subject["name"] + " to " + str(dest))
		"/time":
			if my_steam_id != ADMIN_STEAM_ID:
				_add_message("[System] No permission.")
				return
			if parts.size() < 2:
				_add_message("[System] Usage: /time <morning|day|evening|night>")
				return
			var weather_node = get_tree().root.get_node_or_null("Scene/Weather")
			if not weather_node:
				_add_message("[System] WeatherSystem not found.")
				return
			match parts[1].to_lower():
				"morning":
					weather_node.time_of_day = 0.25
				"day":
					weather_node.time_of_day = 0.5
				"evening":
					weather_node.time_of_day = 0.75
				"night":
					weather_node.time_of_day = 0
				_:
					var val = parts[1].to_float()
					if parts[1].is_valid_float() and val >= 0.0 and val < 1.0:
						weather_node.time_of_day = val
					else:
						_add_message("[System] Unknown time. Use: morning, day, evening, night, or a number below 1")
						return
			if multiplayer.has_multiplayer_peer():
				weather_node.sync_weather_state.rpc(weather_node.current_weather, weather_node.time_of_day, weather_node.weather_timer)
			_add_message("[System] Time set to: " + parts[1].to_lower())
		"/spawn":
			if my_steam_id != ADMIN_STEAM_ID:
				_add_message("[System] No permission.")
				return
			if parts.size() < 2:
				_add_message("[System] Usage: /spawn <chicken> [x] [y]")
				return
			if parts[1].to_lower() != "chicken":
				_add_message("[System] Can only spawn: chicken")
				return
			var scene_node = get_tree().root.get_node_or_null("Scene")
			if not scene_node:
				_add_message("[System] Scene not found.")
				return
			var spawn_pos = Vector2.ZERO
			if parts.size() >= 4 and parts[2].is_valid_float() and parts[3].is_valid_float():
				spawn_pos = Vector2((parts[2].to_float() * 100), (parts[3].to_float()) * -100)
			else:
				var local_player = _get_local_player()
				if local_player:
					spawn_pos = local_player.global_position
			if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
				scene_node.host_spawn_chicken(spawn_pos)
			elif not multiplayer.has_multiplayer_peer():
				scene_node.host_spawn_chicken(spawn_pos)
			var display_x = spawn_pos.x / 100.0
			var display_y = spawn_pos.y / -100.0
			_add_message("[System] Spawned chicken at (" + str(display_x).pad_zeros(1) + ", " + str(display_y).pad_zeros(1) + ")")
		"/kill":
			if my_steam_id != ADMIN_STEAM_ID:
				_add_message("[System] No permission.")
				return
			if parts.size() < 2:
				_add_message("[System] Usage: /kill <player_name>")
				return
			var scene_node = get_tree().root.get_node("Scene")
			var target_name = " ".join(parts.slice(1))
			var matches = []
			for child in scene_node.get_children():
				if child is CharacterBody2D:
					var peer_id = child.get_multiplayer_authority()
					var sname = _get_steam_name_for_peer(peer_id)
					if sname.to_lower().begins_with(target_name.to_lower()):
						matches.append({"node": child, "peer_id": peer_id, "name": sname})
			if matches.size() == 0:
				_add_message("[System] Player '" + target_name + "' not found.")
				return
			elif matches.size() > 1:
				var names = ""
				for m in matches:
					names += m["name"] + ", "
				_add_message("[System] Multiple players found: " + names.trim_suffix(", ") + ". Be more specific.")
				return
			var target = matches[0]
			if target["peer_id"] == multiplayer.get_unique_id():
				target["node"].take_damage(target["node"].synced_health)
			else:
				if multiplayer.has_multiplayer_peer():
					scene_node.request_kill_player.rpc_id(1, target["peer_id"])
				else:
					target["node"].take_damage(target["node"].synced_health)
			_add_message("[System] Killed " + target["name"])
		_:
			_add_message("[System] Unknown command: " + cmd)

func _give_item_to_player(target_name: String, item_name: String, amount: int):
	var scene_node = get_tree().root.get_node("Scene")
	var target_peer_id: int = -1
	var found_name: String = ""
	var my_steam_id = Steam.getSteamID()

	if not multiplayer.has_multiplayer_peer():
		found_name = Steam.getFriendPersonaName(my_steam_id)
		if not found_name.to_lower().begins_with(target_name.to_lower()):
			_add_message("[System] Player '" + target_name + "' not found.")
			return
		_do_give_item(item_name, amount)
		_add_message("[System] Gave " + str(amount) + "x " + item_name + " to " + found_name)
		return

	var matches = []
	for child in scene_node.get_children():
		if child is CharacterBody2D:
			var peer_id = child.get_multiplayer_authority()
			var sname = _get_steam_name_for_peer(peer_id)
			if sname.to_lower().begins_with(target_name.to_lower()):
				matches.append({"peer_id": peer_id, "name": sname})

	if matches.size() == 0:
		_add_message("[System] Player '" + target_name + "' not found.")
		return
	elif matches.size() > 1:
		var names = ""
		for m in matches:
			names += m["name"] + ", "
		_add_message("[System] Multiple players found: " + names.trim_suffix(", ") + ". Be more specific.")
		return

	target_peer_id = matches[0]["peer_id"]
	found_name = matches[0]["name"]

	if target_peer_id == multiplayer.get_unique_id():
		_do_give_item(item_name, amount)
	else:
		_rpc_give_item.rpc_id(target_peer_id, item_name, amount)
	_add_message("[System] Gave " + str(amount) + "x " + item_name + " to " + found_name)

@rpc("authority", "call_remote", "reliable")
func _rpc_give_item(item_name: String, amount: int):
	_do_give_item(item_name, amount)

func _get_item_texture(item_name: String) -> Texture2D:
	match item_name.to_lower():
		"wood": return wood_texture
		"wood plank": return Crafting.plank_texture
		"axe": return axe_texture
		"sword": return sword_texture
		"pickaxe": return Crafting.pickaxe_texture
		"crafting_bench": return Crafting.bench_texture
		"stone axe": return stone_axe_texture
		"stone sword": return stone_sword_texture
		"stone pickaxe": return stone_pickaxe_texture
		"stone": return stone_texture
		"wardrobe": return wardrobe_texture
	return null

func _do_give_item(item_name: String, amount: int):
	var tex = _get_item_texture(item_name)
	if tex == null:
		var img = Image.create(32, 32, false, Image.FORMAT_RGB8)
		img.fill(Color.WHITE)
		tex = ImageTexture.create_from_image(img)
	const UNLOCKED_INV_SLOTS = 20
	if item_name in ["Axe", "Sword"]:
		var dur = 80 if item_name == "Axe" else 30
		for i in amount:
			var added = false
			for slot in Inventory.slots:
				if slot["item"] == "":
					slot["item"] = item_name
					slot["count"] = dur
					slot["texture"] = tex
					added = true
					break
			if not added:
				for j in UNLOCKED_INV_SLOTS:
					var slot = Inventory.inv_slots[j]
					if slot["item"] == "":
						slot["item"] = item_name
						slot["count"] = dur
						slot["texture"] = tex
						break
	else:
		var remaining = amount
		for slot in Inventory.slots:
			if remaining <= 0:
				break
			if slot["item"] == item_name and slot["count"] < 99:
				var add = min(99 - slot["count"], remaining)
				slot["count"] += add
				remaining -= add
		for j in UNLOCKED_INV_SLOTS:
			if remaining <= 0:
				break
			var slot = Inventory.inv_slots[j]
			if slot["item"] == item_name and slot["count"] < 99:
				var add = min(99 - slot["count"], remaining)
				slot["count"] += add
				remaining -= add
		for slot in Inventory.slots:
			if remaining <= 0:
				break
			if slot["item"] == "":
				var add = min(99, remaining)
				slot["item"] = item_name
				slot["count"] = add
				slot["texture"] = tex
				remaining -= add
		for j in UNLOCKED_INV_SLOTS:
			if remaining <= 0:
				break
			var slot = Inventory.inv_slots[j]
			if slot["item"] == "":
				var add = min(99, remaining)
				slot["item"] = item_name
				slot["count"] = add
				slot["texture"] = tex
				remaining -= add
	Inventory.inventory_changed.emit()
	Inventory.discover(item_name)

func _get_local_player():
	for child in get_tree().root.get_node("Scene").get_children():
		if child is CharacterBody2D:
			if multiplayer.has_multiplayer_peer():
				if child.is_multiplayer_authority():
					return child
			else:
				return child
	return null

func _ready():
	input_row.visible = false
	scroll_container.visible = false

func _open_chat(prefill: String):
	is_open = true
	input_row.visible = true
	scroll_container.visible = true
	hide_timer = 0.0
	input_field.text = prefill
	input_field.grab_focus()
	input_field.caret_column = input_field.text.length()

func _close_chat():
	is_open = false
	input_row.visible = false
	input_field.clear()
	input_field.release_focus()
	hide_timer = HIDE_DELAY
	_chat_close_cooldown = 0.2
	if messages.is_empty():
		scroll_container.visible = false

func _add_message(msg: String):
	messages.append(msg)
	if messages.size() > MAX_MESSAGES:
		messages.pop_front()
		if messages_container.get_child_count() > 0:
			messages_container.get_child(0).queue_free()
	var label = Label.new()
	label.text = msg
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	messages_container.add_child(label)
	scroll_container.visible = true
	hide_timer = HIDE_DELAY
	await get_tree().process_frame
	scroll_container.scroll_vertical = scroll_container.get_v_scroll_bar().max_value

func _update_messages_visibility():
	scroll_container.visible = not messages.is_empty()

func _on_input_submitted(text: String):
	var trimmed = text.strip_edges()
	if trimmed == "":
		_close_chat()
		return
	if trimmed.begins_with("/"):
		_handle_command(trimmed)
	else:
		_send_chat(trimmed)
	_close_chat()

func _send_chat(text: String):
	var steam_id = Steam.getSteamID()
	var steam_name = Steam.getFriendPersonaName(steam_id)
	var msg = steam_name + ": " + text
	if multiplayer.has_multiplayer_peer():
		_broadcast_message.rpc(msg)
	else:
		_add_message(msg)

func _give_item(item_name: String, amount: int):
	var tex = _get_item_texture(item_name)
	if tex == null:
		var img = Image.create(32, 32, false, Image.FORMAT_RGB8)
		img.fill(Color.WHITE)
		tex = ImageTexture.create_from_image(img)
	if item_name in ["Axe", "Sword"]:
		var dur = 80 if item_name == "Axe" else 30
		for i in amount:
			Inventory.add_item_with_count(item_name, tex, dur)
	else:
		for i in amount:
			Inventory.add_item(item_name, tex)
	_add_message("[System] Gave " + str(amount) + "x " + item_name)

@rpc("any_peer", "call_local", "reliable")
func _broadcast_message(msg: String):
	_add_message(msg)

func _process(delta: float):
	if not is_open:
		if hide_timer > 0.0:
			hide_timer -= delta
			if hide_timer <= 0.0:
				scroll_container.visible = false
	if _chat_close_cooldown > 0.0:
		_chat_close_cooldown -= delta
	if not is_open:
		if _chat_close_cooldown <= 0.0 and Input.is_action_just_pressed("chat"):
			_open_chat("")
			return
	else:
		if Input.is_action_just_pressed("exit"):
			_close_chat()
			get_viewport().set_input_as_handled()

func _input(event):
	if not is_open:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_SLASH:
				_open_chat("/")
				get_viewport().set_input_as_handled()
				return

func _add_system_message(msg: String):
	var my_steam_id = Steam.getSteamID()
	if my_steam_id != ADMIN_STEAM_ID:
		return
	_add_message("[System] " + msg)

@rpc("authority", "call_remote", "reliable")
func _rpc_teleport(dest: Vector2):
	var local_player = _get_local_player()
	if local_player:
		local_player.global_position = dest

@rpc("authority", "call_remote", "reliable")
func _rpc_kill_player():
	var local_player = _get_local_player()
	if local_player:
		local_player.take_damage(local_player.synced_health)
