# Village guide NPC.
# Shows a prompt when the player is close and opens a typewriter style dialogue box when they right click.
# The dialogue includes a hint for the player's next achievement.

extends CharacterBody2D
# Name shown at the top of the dialogue box.
@export var npc_name: String = "Eric the Guide"
# Portrait shown beside the dialogue text.
@export var npc_portrait: Texture2D
# The greeting the NPC says before any achievement hint.
@export var dialogue_line: String = "Hello traveller!"
# Distance in pixels within which the player can talk.
@export var talk_range: float = 96.0
# Speed of the typewriter text effect.
@export var chars_per_second: float = 45.0
# Prompt telling the player they can talk.
var _label: Label = null
# Dialogue box.
var _talk_panel: PanelContainer = null
# Label showing the NPC's name.
var _name_label: Label = null
# Label showing the dialogue text.
var _body_label: Label = null
# Picture of the NPC in the dialogue box.
var _portrait_rect: TextureRect = null
# True while the local player is close enough to talk.
var _player_in_range: bool = false
# True while the dialogue box is open.
var _talking: bool = false
# How many characters of the dialogue are currently revealed.
var _reveal_chars: float = 0.0
# Full text of the conversation currently being shown, including the achievement hint.
var _current_dialogue: String = ""


# Joins the village NPC group and builds the body, prompt and dialogue box.
func _ready() -> void:
	add_to_group("village_npcs")
	z_index = 2
	_make_body()
	_make_prompt()
	_make_talk_panel()


# Updates the prompt and reveals the dialogue text one letter at a time.
func _process(delta: float) -> void:
	var player := _get_local_player()
	_player_in_range = player != null \
		and player.global_position.distance_to(global_position) <= talk_range
	if _label:
		_label.visible = _player_in_range and not _talking
		_label.global_position = global_position + Vector2(-42, -92)
	# Close the dialogue if the player walks away, otherwise reveal more text each frame, and let the exit key close it.
	if _talking:
		if not _player_in_range:
			_close_talk()
			return
		if _reveal_chars < _current_dialogue.length():
			_reveal_chars = min(_reveal_chars + chars_per_second * delta, _current_dialogue.length())
			_body_label.visible_characters = int(_reveal_chars)
		if Input.is_action_just_pressed("exit"):
			_close_talk()


# Right click either advances the dialogue or starts it when the player is close.
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


# Draws the NPC from two coloured rectangles and adds a collision shape.
func _make_body() -> void:
	var body_rect := ColorRect.new()
	body_rect.color = Color(0.24, 0.48, 0.82, 1.0)
	body_rect.size = Vector2(36, 56)
	body_rect.position = Vector2(-18, -56)
	body_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(body_rect)
	var head_rect := ColorRect.new()
	head_rect.color = Color(0.95, 0.74, 0.52, 1.0)
	head_rect.size = Vector2(30, 28)
	head_rect.position = Vector2(-15, -84)
	head_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(head_rect)
	var collision_shape := CollisionShape2D.new()
	var collision_rectangle := RectangleShape2D.new()
	collision_rectangle.size = Vector2(36, 56)
	collision_shape.shape = collision_rectangle
	collision_shape.position = Vector2(0, -28)
	add_child(collision_shape)


# Creates the 'Right-click to talk' label, hidden until needed.
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


# Builds the dialogue box with a portrait on the left and the name and text on the right.
func _make_talk_panel() -> void:
	_talk_panel = PanelContainer.new()
	_talk_panel.visible = false
	_talk_panel.top_level = true
	_talk_panel.custom_minimum_size = Vector2(440, 140)
	add_child(_talk_panel)
	var margin_container := MarginContainer.new()
	margin_container.add_theme_constant_override("margin_left", 14)
	margin_container.add_theme_constant_override("margin_top", 12)
	margin_container.add_theme_constant_override("margin_right", 14)
	margin_container.add_theme_constant_override("margin_bottom", 12)
	_talk_panel.add_child(margin_container)
	var portrait_and_text_row := HBoxContainer.new()
	portrait_and_text_row.add_theme_constant_override("separation", 12)
	margin_container.add_child(portrait_and_text_row)
	_portrait_rect = TextureRect.new()
	_portrait_rect.custom_minimum_size = Vector2(80, 80)
	_portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_portrait_rect.texture = npc_portrait
	portrait_and_text_row.add_child(_portrait_rect)
	var text_column := VBoxContainer.new()
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	portrait_and_text_row.add_child(text_column)
	_name_label = Label.new()
	_name_label.text = npc_name
	_name_label.add_theme_font_size_override("font_size", 18)
	text_column.add_child(_name_label)
	_body_label = Label.new()
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.visible_characters = 0
	text_column.add_child(_body_label)


# Starts the dialogue with a freshly built message and tells the player they are talking.
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


# Returns the greeting followed by the hint for the player's next achievement, or a congratulation if they have them all.
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


# Finds the achievement manager in the scene, or returns null if there is none.
func _get_achievement_manager() -> Node:
	var scene := get_tree().root.get_node_or_null("Scene")
	if not scene:
		return null
	return scene.get_node_or_null("Achivementmanager")


# Shows the full text immediately if it is still being typed, otherwise closes the dialogue.
func _advance_talk() -> void:
	if _reveal_chars < _current_dialogue.length():
		_reveal_chars = _current_dialogue.length()
		_body_label.visible_characters = int(_reveal_chars)
		return
	_close_talk()


# Ends the dialogue and lets the player move again.
func _close_talk() -> void:
	var player := _get_local_player()
	if player:
		player.set("talking_to_npc", false)
	_talking = false
	_talk_panel.visible = false


# Returns the player controlled by this game instance, or null.
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
