extends CharacterBody2D
@export var npc_name: String = "Eric the Guide"
@export var npc_portrait: Texture2D
@export var dialogue_line: String = "Hello traveller!"
@export var talk_range: float = 96.0
@export var chars_per_second: float = 45.0
var _label: Label = null
var _talk_panel: PanelContainer = null
var _name_label: Label = null
var _body_label: Label = null
var _portrait_rect: TextureRect = null
var _player_in_range: bool = false
var _talking: bool = false
var _reveal_chars: float = 0.0
var _current_dialogue: String = ""


func _ready() -> void:
	add_to_group("village_npcs")
	z_index = 2
	_make_body()
	_make_prompt()
	_make_talk_panel()


func _process(delta: float) -> void:
	var player := _get_local_player()
	_player_in_range = player != null \
		and player.global_position.distance_to(global_position) <= talk_range
	if _label:
		_label.visible = _player_in_range and not _talking
		_label.global_position = global_position + Vector2(-42, -92)
	if _talking:
		if not _player_in_range:
			_close_talk()
			return
		if _reveal_chars < _current_dialogue.length():
			_reveal_chars = min(_reveal_chars + chars_per_second * delta, _current_dialogue.length())
			_body_label.visible_characters = int(_reveal_chars)
		if Input.is_action_just_pressed("exit"):
			_close_talk()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if _talking:
			if _player_in_range:
				_advance_talk()
		elif _player_in_range:
			var player := _get_local_player()
			if player and player.get("is_spectator") == true:
				return
			_open_talk()


func _make_body() -> void:
	var body := ColorRect.new()
	body.color = Color(0.24, 0.48, 0.82, 1.0)
	body.size = Vector2(36, 56)
	body.position = Vector2(-18, -56)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(body)
	var head := ColorRect.new()
	head.color = Color(0.95, 0.74, 0.52, 1.0)
	head.size = Vector2(30, 28)
	head.position = Vector2(-15, -84)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(head)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(36, 56)
	shape.shape = rect
	shape.position = Vector2(0, -28)
	add_child(shape)


func _make_prompt() -> void:
	_label = Label.new()
	_label.text = "Right-click to talk"
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	_label.visible = false
	_label.top_level = true
	add_child(_label)


func _make_talk_panel() -> void:
	_talk_panel = PanelContainer.new()
	_talk_panel.visible = false
	_talk_panel.top_level = true
	_talk_panel.custom_minimum_size = Vector2(440, 140)
	add_child(_talk_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	_talk_panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)
	_portrait_rect = TextureRect.new()
	_portrait_rect.custom_minimum_size = Vector2(80, 80)
	_portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_portrait_rect.texture = npc_portrait
	row.add_child(_portrait_rect)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(box)
	_name_label = Label.new()
	_name_label.text = npc_name
	_name_label.add_theme_font_size_override("font_size", 18)
	box.add_child(_name_label)
	_body_label = Label.new()
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.visible_characters = 0
	box.add_child(_body_label)


func _open_talk() -> void:
	var player := _get_local_player()
	if player:
		player.set("talking_to_npc", true)
	_talking = true
	_reveal_chars = 0.0
	_current_dialogue = _build_dialogue()
	_body_label.text = _current_dialogue
	_body_label.visible_characters = 0
	_talk_panel.visible = true
	_talk_panel.global_position = global_position + Vector2(-220, -220)


func _build_dialogue() -> String:
	var achievements := _get_achievement_manager()
	if not achievements:
		return dialogue_line
	var next_id: String = achievements.get_next_ordered_achievement()
	if next_id == "":
		return dialogue_line + " You've unlocked everything I know how to teach, well done!"
	var data: Dictionary = achievements.ACHIEVEMENT_DATA.get(next_id, {})
	var hint: String = data.get("hint", "")
	if hint == "":
		return dialogue_line
	return dialogue_line + " Your next goal: " + hint


func _get_achievement_manager() -> Node:
	var scene := get_tree().root.get_node_or_null("Scene")
	if not scene:
		return null
	return scene.get_node_or_null("Achivementmanager")


func _advance_talk() -> void:
	if _reveal_chars < _current_dialogue.length():
		_reveal_chars = _current_dialogue.length()
		_body_label.visible_characters = int(_reveal_chars)
		return
	_close_talk()


func _close_talk() -> void:
	var player := _get_local_player()
	if player:
		player.set("talking_to_npc", false)
	_talking = false
	_talk_panel.visible = false


func _get_local_player() -> CharacterBody2D:
	var scene := get_tree().root.get_node_or_null("Scene")
	if not scene:
		return null
	var player: Variant = scene.get("local_player")
	if player and is_instance_valid(player):
		return player
	for child in scene.get_children():
		if child is CharacterBody2D and child.is_in_group("players"):
			if not multiplayer.has_multiplayer_peer() or child.is_multiplayer_authority():
				return child
	return null
