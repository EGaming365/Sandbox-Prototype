# Wardrobe menu.
# Lets the player switch the hair, shirt and pants layers of their character on or off.

extends Control

# Row of buttons for choosing a category.
@onready var tab_buttons: HBoxContainer = $PanelContainer/HBoxContainer/Left/Tab_Buttons
# Grid that holds the options for the selected category.
@onready var grid: GridContainer = get_node(
	"PanelContainer/HBoxContainer/Left/ScrollContainer/MarginContainer/GridContainer",
)

# Names of the categories, in the order they appear.
var tabs = ["Hair", "Shirt", "Pants"]
# Category currently shown.
var current_tab: String = "Hair"
# Whether each category is currently switched on or off.
var selected_options: Dictionary = {
	"Hair": "On",
	"Shirt": "On",
	"Pants": "On",
}


# Starts hidden and builds the tabs.
func _ready():
	visible = false
	_setup_tabs()
	var panel = $PanelContainer
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


# Creates one button for each category and shows the Hair category first.
func _setup_tabs():
	for child in tab_buttons.get_children():
		child.queue_free()
	for tab_name in tabs:
		var button = Button.new()
		button.text = tab_name
		button.flat = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_tab_pressed.bind(tab_name))
		tab_buttons.add_child(button)
	_on_tab_pressed("Hair")


# Switches to the category that was clicked.
func _on_tab_pressed(tab_name: String):
	current_tab = tab_name
	_highlight_active_tab()
	_load_tab_contents(tab_name)


# Gives the current tab a highlighted look and resets the others.
func _highlight_active_tab():
	for button in tab_buttons.get_children():
		if button.text == current_tab:
			button.add_theme_color_override("font_color", Color.WHITE)
			var style_box = StyleBoxFlat.new()
			style_box.bg_color = Color(0.2, 0.2, 0.2, 0.8)
			style_box.border_width_bottom = 2
			style_box.border_color = Color.WHITE
			button.add_theme_stylebox_override("normal", style_box)
			button.add_theme_stylebox_override("hover", style_box)
		else:
			button.remove_theme_color_override("font_color")
			button.remove_theme_stylebox_override("normal")
			button.remove_theme_stylebox_override("hover")


# Fills the grid with an On and an Off option for the selected category.
func _load_tab_contents(tab_name: String):
	for child in grid.get_children():
		child.queue_free()
	_add_options(["On", "Off"])


# Creates a square button for each option and highlights the one currently selected.
func _add_options(option_names: Array):
	for option_label in option_names:
		var button = Button.new()
		button.text = option_label
		button.custom_minimum_size = Vector2(80, 80)
		button.pressed.connect(_on_option_pressed.bind(option_label))
		if selected_options.get(current_tab, "") == option_label:
			button.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2))
			button.add_theme_stylebox_override("normal", _make_highlight_style())
		grid.add_child(button)


# Returns a green bordered style used for the selected option.
func _make_highlight_style() -> StyleBoxFlat:
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0.2, 0.4, 0.2, 0.4)
	style_box.border_width_left = 2
	style_box.border_width_right = 2
	style_box.border_width_top = 2
	style_box.border_width_bottom = 2
	style_box.border_color = Color(0.2, 0.8, 0.2)
	style_box.corner_radius_top_left = 4
	style_box.corner_radius_top_right = 4
	style_box.corner_radius_bottom_left = 4
	style_box.corner_radius_bottom_right = 4
	return style_box


# Switches the chosen layer on or off for the player and updates the shown selection.
func _on_option_pressed(option_name: String):
	var player = _get_local_player()
	if not player:
		return
	selected_options[current_tab] = option_name
	match current_tab:
		"Hair":
			var sprite = player.get_node_or_null("Hair_Sprite")
			if sprite:
				sprite.visible = option_name == "On"
				if sprite.visible:
					sprite.play(player.anim.animation)
		"Shirt":
			var sprite = player.get_node_or_null("Shirt_Sprite")
			if sprite:
				sprite.visible = option_name == "On"
				if sprite.visible:
					sprite.play(player.anim.animation)
		"Pants":
			var sprite = player.get_node_or_null("Pants_Sprite")
			if sprite:
				sprite.visible = option_name == "On"
				if sprite.visible:
					sprite.play(player.anim.animation)
	# Tell the player which clothing layers are visible so the change is shared with other players.
	player.apply_cosmetics(
		player.hair_sprite.visible,
		player.shirt_sprite.visible,
		player.pants_sprite.visible
	)
	_load_tab_contents(current_tab)


# Returns the player controlled by this game instance, or null.
func _get_local_player() -> Node:
	for child in get_tree().root.get_node("Scene").get_children():
		if child is CharacterBody2D and child.is_in_group("players"):
			if multiplayer.has_multiplayer_peer():
				if child.is_multiplayer_authority():
					return child
			else:
				return child
	return null


# Shows the menu.
func open():
	visible = true


# Hides the menu and tells any open wardrobe blocks to close too.
func close():
	visible = false
	for node in get_tree().get_nodes_in_group("placed_blocks"):
		if node.has_method("close_ui"):
			node.close_ui()


# Pressing Escape or clicking outside the panel closes the menu.
func _input(event):
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
	if event.is_action_pressed("click"):
		var panel = $PanelContainer
		var panel_rect = Rect2(panel.global_position, panel.size)
		if not panel_rect.has_point(event.position):
			close()
