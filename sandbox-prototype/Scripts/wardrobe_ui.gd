extends Control

@onready var tab_buttons: HBoxContainer = $PanelContainer/HBoxContainer/Left/Tab_Buttons
@onready var grid: GridContainer = $PanelContainer/HBoxContainer/Left/ScrollContainer/MarginContainer/GridContainer

var tabs = ["Body", "Accessories", "Hair", "Shirt", "Pants"]
var current_tab: String = "Body"
var selected_options: Dictionary = {
	"Body": "Skin 1",
	"Accessories": "None",
	"Hair": "Basic",
	"Shirt": "Basic",
	"Pants": "Basic",
}

func _ready():
	visible = false
	_setup_tabs()
	var panel = $PanelContainer
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _setup_tabs():
	for child in tab_buttons.get_children():
		child.queue_free()
	for tab_name in tabs:
		var btn = Button.new()
		btn.text = tab_name
		btn.flat = true
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_tab_pressed.bind(tab_name))
		tab_buttons.add_child(btn)
	_on_tab_pressed("Body")

func _on_tab_pressed(tab_name: String):
	current_tab = tab_name
	_highlight_active_tab()
	_load_tab_contents(tab_name)

func _highlight_active_tab():
	for btn in tab_buttons.get_children():
		if btn.text == current_tab:
			btn.add_theme_color_override("font_color", Color.WHITE)
			var style = StyleBoxFlat.new()
			style.bg_color = Color(0.2, 0.2, 0.2, 0.8)
			style.border_width_bottom = 2
			style.border_color = Color.WHITE
			btn.add_theme_stylebox_override("normal", style)
			btn.add_theme_stylebox_override("hover", style)
		else:
			btn.remove_theme_color_override("font_color")
			btn.remove_theme_stylebox_override("normal")
			btn.remove_theme_stylebox_override("hover")

func _load_tab_contents(tab_name: String):
	for child in grid.get_children():
		child.queue_free()
	match tab_name:
		"Body":
			_add_options(["Skin 1", "Skin 2", "Skin 3", "Skin 4"])
		"Accessories":
			_add_options(["None", "Hat", "Glasses", "Earring"])
		"Hair":
			_add_options(["None", "Basic"])
		"Shirt":
			_add_options(["None", "Basic"])
		"Pants":
			_add_options(["None", "Basic"])

func _add_options(option_names: Array):
	for opt_name in option_names:
		var btn = Button.new()
		btn.text = opt_name
		btn.custom_minimum_size = Vector2(80, 80)
		btn.pressed.connect(_on_option_pressed.bind(opt_name))
		if selected_options.get(current_tab, "") == opt_name:
			btn.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2))
			btn.add_theme_stylebox_override("normal", _make_highlight_style())
		grid.add_child(btn)

func _make_highlight_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.4, 0.2, 0.4)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.2, 0.8, 0.2)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style

func _on_option_pressed(option_name: String):
	var player = _get_local_player()
	if not player:
		return
	selected_options[current_tab] = option_name
	match current_tab:
		"Hair":
			var sprite = player.get_node_or_null("Hair_Sprite")
			if sprite:
				sprite.visible = option_name != "None"
				if sprite.visible:
					sprite.play(player.anim.animation)
		"Shirt":
			var sprite = player.get_node_or_null("Shirt_Sprite")
			if sprite:
				sprite.visible = option_name != "None"
				if sprite.visible:
					sprite.play(player.anim.animation)
		"Pants":
			var sprite = player.get_node_or_null("Pants_Sprite")
			if sprite:
				sprite.visible = option_name != "None"
				if sprite.visible:
					sprite.play(player.anim.animation)
	player.apply_cosmetics(
		player.hair_sprite.visible,
		player.shirt_sprite.visible,
		player.pants_sprite.visible
	)
	_load_tab_contents(current_tab)

func _get_local_player() -> Node:
	for child in get_tree().root.get_node("Scene").get_children():
		if child is CharacterBody2D:
			if multiplayer.has_multiplayer_peer():
				if child.is_multiplayer_authority():
					return child
			else:
				return child
	return null

func open():
	visible = true

func close():
	visible = false
	for node in get_tree().get_nodes_in_group("placed_blocks"):
		if node.has_method("close_ui"):
			node.close_ui()

func _input(event):
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var panel = $PanelContainer
		var rect = Rect2(panel.global_position, panel.size)
		if not rect.has_point(event.position):
			close()
