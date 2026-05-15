extends Control

@onready var tab_buttons = $PanelContainer/VBoxContainer/Tab_Buttons
@onready var grid = $PanelContainer/VBoxContainer/HBoxContainer/Left/ScrollContainer/GridContainer
@onready var right_panel = $PanelContainer/VBoxContainer/HBoxContainer/Right

var current_tab: int = 0
var selected_body: int = 0
var selected_accessories: int = -1
var selected_hair: int = -1
var selected_shirt: int = -1
var selected_pants: int = -1

var body_options: Array = []
var accessories_options: Array = []
var hair_options: Array = []
var shirt_options: Array = []
var pants_options: Array = []

var preview_sprite: AnimatedSprite2D = null

var slot_default: StyleBox = preload("res://Resources/hotbar_default.tres")
var slot_selected: StyleBox = preload("res://Resources/hotbar_selected.tres")

func _ready():
	hide()
	_apply_panel_style()
	_setup_tabs()
	_setup_preview()
	_show_tab(0)

func _apply_panel_style():
	var panel = $PanelContainer
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.12, 0.95)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.3, 0.3, 0.3, 1.0)
	panel.add_theme_stylebox_override("panel", style)

func _setup_tabs():
	var tab_names = ["Body", "Accessories", "Hair", "Shirt", "Pants"]
	for child in tab_buttons.get_children():
		child.queue_free()
	for i in tab_names.size():
		var btn = Button.new()
		btn.text = tab_names[i]
		btn.custom_minimum_size = Vector2(80, 32)
		btn.pressed.connect(_show_tab.bind(i))
		tab_buttons.add_child(btn)

func _setup_preview():
	preview_sprite = AnimatedSprite2D.new()
	right_panel.add_child(preview_sprite)

func _show_tab(index: int):
	current_tab = index
	var options = [body_options, accessories_options, hair_options, shirt_options, pants_options]
	var categories = ["body", "accessories", "hair", "shirt", "pants"]
	_build_grid(options[index], categories[index])
	for i in tab_buttons.get_child_count():
		var btn = tab_buttons.get_child(i)
		btn.modulate = Color(1.5, 1.8, 1.5, 1.0) if i == index else Color(0.6, 0.6, 0.6, 1.0)

func _build_grid(options: Array, category: String):
	for child in grid.get_children():
		child.queue_free()
	for i in options.size():
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(64, 64)
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.25, 0.25, 0.25, 1.0)
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_left = 4
		style.corner_radius_bottom_right = 4
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("hover", style)
		if options[i].get("texture"):
			var tex_rect = TextureRect.new()
			tex_rect.texture = options[i]["texture"]
			tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			tex_rect.offset_left = 4
			tex_rect.offset_right = -4
			tex_rect.offset_top = 4
			tex_rect.offset_bottom = -4
			tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			btn.add_child(tex_rect)
		else:
			btn.text = options[i].get("name", str(i))
		btn.pressed.connect(_on_option_selected.bind(category, i))
		grid.add_child(btn)

func _on_option_selected(category: String, index: int):
	match category:
		"body": selected_body = index
		"accessories": selected_accessories = index
		"hair": selected_hair = index
		"shirt": selected_shirt = index
		"pants": selected_pants = index
	_update_preview()

func _update_preview():
	pass

func _process(_delta):
	if not visible:
		return
	if Input.is_action_just_pressed("exit"):
		hide()
		get_viewport().set_input_as_handled()
