extends Control

var current_section: String = "game"
var current_collection_sub: String = "recipes"
var discovered_fish: Array = []
var fish_records: Dictionary = {}
var fish_catch_counts: Dictionary = {}
var mark_base_colors: Dictionary = {}
var btn_base_colors: Dictionary = {}
var selected_fish_btn: Button = null
var aurora_active: bool = false

func toggle():
	if visible:
		hide()
		_close_info_panel()
	else:
		show()
		_switch_section(current_section)
		_switch_collection_sub(current_collection_sub)

func _ready():
	hide()
	_connect_nav()
	_cache_base_colors()
	_switch_section("game")
	_switch_collection_sub("recipes")
	get_viewport().gui_focus_changed.connect(func(_c): pass)

func _process(_delta):
	pass

func _input(event):
	if Input.is_action_just_pressed("exit"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	if not visible:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if get_viewport().is_input_handled():
			return
		var mouse = get_global_mouse_position()
		var panel_rect = $PanelContainer.get_global_rect()
		var nav_rect = $PanelContainer/VBoxContainer/HBoxContainer.get_global_rect()
		var safe_rect = panel_rect.merge(nav_rect)
		if not safe_rect.has_point(mouse):
			hide()

func set_aurora(state: bool):
	aurora_active = state
	var hud = get_tree().root.get_node_or_null("Scene/CanvasLayer/RightUI")
	if hud and hud.has_method("set_aurora_icon"):
		hud.set_aurora_icon(state)
	if state:
		_show_aurora_notification()

func _show_aurora_notification():
	var canvas = get_tree().root.get_node_or_null("Scene/CanvasLayer")
	if not canvas:
		return
	var container = HBoxContainer.new()
	container.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	container.offset_top = 60
	container.z_index = 20
	container.alignment = BoxContainer.ALIGNMENT_CENTER

	var part1 = Label.new()
	part1.text = "Tonight is the illusive "
	part1.add_theme_font_size_override("font_size", 22)
	part1.add_theme_color_override("font_color", Color.WHITE)
	part1.add_theme_color_override("font_outline_color", Color.BLACK)
	part1.add_theme_constant_override("outline_size", 5)
	container.add_child(part1)

	var part2 = Label.new()
	part2.text = "Aurora Borealis"
	part2.add_theme_font_size_override("font_size", 22)
	part2.add_theme_color_override("font_color", Color(0.18, 0.85, 0.65))
	part2.add_theme_color_override("font_outline_color", Color.BLACK)
	part2.add_theme_constant_override("outline_size", 5)
	container.add_child(part2)

	var part3 = Label.new()
	part3.text = "! Luck is Drastically Increased."
	part3.add_theme_font_size_override("font_size", 22)
	part3.add_theme_color_override("font_color", Color.WHITE)
	part3.add_theme_color_override("font_outline_color", Color.BLACK)
	part3.add_theme_constant_override("outline_size", 5)
	container.add_child(part3)

	canvas.add_child(container)
	var tween = container.create_tween()
	tween.tween_interval(4.0)
	tween.tween_property(container, "modulate:a", 0.0, 1.0)
	tween.tween_callback(container.queue_free)

func _cache_base_colors():
	for n in ["Game", "Settings", "Collection", "Mastery", "Blank"]:
		var btn = $PanelContainer/VBoxContainer/HBoxContainer.get_node(n) as Button
		var mark = btn.get_node(n + "Mark") as ColorRect
		mark_base_colors[n] = mark.color
		var normal_style = btn.get_theme_stylebox("normal")
		if normal_style is StyleBoxFlat:
			btn_base_colors[n] = normal_style.bg_color
		else:
			btn_base_colors[n] = Color(0.2, 0.2, 0.2, 1.0)
		var hover_style = StyleBoxFlat.new()
		hover_style.bg_color = btn_base_colors[n].lightened(0.3)
		btn.add_theme_stylebox_override("hover", hover_style)
		var pressed_style = StyleBoxFlat.new()
		pressed_style.bg_color = btn_base_colors[n].darkened(0.3)
		btn.add_theme_stylebox_override("pressed", pressed_style)

func _connect_nav():
	$PanelContainer/VBoxContainer/HBoxContainer/Game.pressed.connect(func(): _switch_section("game"))
	$PanelContainer/VBoxContainer/HBoxContainer/Settings.pressed.connect(func(): _switch_section("settings"))
	$PanelContainer/VBoxContainer/HBoxContainer/Collection.pressed.connect(func(): _switch_section("collection"))
	$PanelContainer/VBoxContainer/HBoxContainer/Mastery.pressed.connect(func(): _switch_section("mastery"))
	$PanelContainer/VBoxContainer/HBoxContainer/Blank.pressed.connect(func(): _switch_section("blank"))
	for n in ["Game", "Settings", "Collection", "Mastery", "Blank"]:
		var btn = $PanelContainer/VBoxContainer/HBoxContainer.get_node(n) as Button
		var capture = n
		btn.mouse_entered.connect(func(): _update_mark(capture))
		btn.mouse_exited.connect(func(): _update_mark(capture))
		btn.button_down.connect(func(): _update_mark(capture))
		btn.button_up.connect(func(): _update_mark(capture))
	$PanelContainer/MarginContainer/CollectionSection/HBoxContainer/Recipes.pressed.connect(func(): _switch_collection_sub("recipes"))
	$PanelContainer/MarginContainer/CollectionSection/HBoxContainer/Fish.pressed.connect(func(): _switch_collection_sub("fish"))

func _update_mark(btn_name: String):
	var btn = $PanelContainer/VBoxContainer/HBoxContainer.get_node(btn_name) as Button
	var mark = btn.get_node(btn_name + "Mark") as ColorRect
	if btn.button_pressed or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and btn.is_hovered():
		mark.color = mark_base_colors[btn_name].darkened(0.3)
	elif btn.is_hovered():
		mark.color = mark_base_colors[btn_name].lightened(0.3)
	else:
		mark.color = mark_base_colors[btn_name]

func _switch_section(section: String):
	current_section = section
	var sections = {
		"game":       $PanelContainer/MarginContainer/GameSection,
		"settings":   $PanelContainer/MarginContainer/SettingsSection,
		"collection": $PanelContainer/MarginContainer/CollectionSection,
		"mastery":    $PanelContainer/MarginContainer/MasterySection,
		"blank":      $PanelContainer/MarginContainer/BlankSection,
	}
	for key in sections:
		sections[key].visible = (key == section)
	var marks = {
		"game":       $PanelContainer/VBoxContainer/HBoxContainer/Game/GameMark,
		"settings":   $PanelContainer/VBoxContainer/HBoxContainer/Settings/SettingsMark,
		"collection": $PanelContainer/VBoxContainer/HBoxContainer/Collection/CollectionMark,
		"mastery":    $PanelContainer/VBoxContainer/HBoxContainer/Mastery/MasteryMark,
		"blank":      $PanelContainer/VBoxContainer/HBoxContainer/Blank/BlankMark,
	}
	for key in marks:
		marks[key].visible = (key == section)

func _switch_collection_sub(sub: String):
	current_collection_sub = sub
	var subnav = $PanelContainer/MarginContainer/CollectionSection/HBoxContainer
	for btn in subnav.get_children():
		btn.modulate = Color(1.5, 1.8, 1.5, 1.0) if btn.name.to_lower() == sub else Color(0.6, 0.6, 0.6, 1.0)
	match sub:
		"recipes":
			_build_recipes_panel()
		"fish":
			_build_fish_panel()

func _get_panel() -> Node:
	return $PanelContainer/MarginContainer/CollectionSection/Panel

func _get_info() -> Node:
	return $PanelContainer/MarginContainer/CollectionSection/Info

func _build_fish_panel():
	_clear_panel()
	var panel = _get_panel()
	var info = _get_info()
	call_deferred("_populate_fish_panel", panel, info)

func _populate_fish_panel(panel: Control, info: Control):
	var columns = 6
	var slot_size = 116
	var separation = 6
	var total_width = columns * slot_size + (columns - 1) * separation

	var scroll = ScrollContainer.new()
	scroll.anchor_left = 0.0
	scroll.anchor_top = 0.0
	scroll.anchor_right = 0.0
	scroll.anchor_bottom = 1.0
	scroll.offset_left = 0.0
	scroll.offset_top = 0.0
	scroll.offset_right = total_width
	scroll.offset_bottom = 0.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	panel.add_child(scroll)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	vbox.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	scroll.add_child(vbox)

	var grid = GridContainer.new()
	grid.columns = columns
	grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	grid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	grid.add_theme_constant_override("h_separation", separation)
	grid.add_theme_constant_override("v_separation", separation)
	vbox.add_child(grid)

	var rarity_order = {"Trash": 0, "Common": 1, "Uncommon": 2, "Unusual": 3, "Rare": 4, "Epic": 5, "Legendary": 6}
	var sorted_fish = FishingManager.FISH_TABLE.duplicate()
	sorted_fish.sort_custom(func(a, b):
		var ra = rarity_order.get(a.get("rarity", "Common"), 0)
		var rb = rarity_order.get(b.get("rarity", "Common"), 0)
		return ra < rb
	)

	for fish in sorted_fish:
		_add_fish_slot(grid, fish, info)

func _make_slot_style(border: bool, border_color: Color) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.125, 0.125, 0.125, 1.0)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.border_width_left = 4 if border else 0
	style.border_width_right = 4 if border else 0
	style.border_width_top = 4 if border else 0
	style.border_width_bottom = 4 if border else 0
	if border:
		style.border_color = border_color
	return style

func _add_fish_slot(grid: GridContainer, fish: Dictionary, info: Control):
	var discovered = fish["name"] in discovered_fish
	var rarity_color = _rarity_color(fish.get("rarity", ""))

	var btn = Button.new()
	btn.custom_minimum_size = Vector2(106, 126)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	btn.clip_contents = true
	btn.set_meta("rarity_color", rarity_color)

	var normal_style = _make_slot_style(false, rarity_color)
	var hover_style = _make_slot_style(true, rarity_color)
	btn.add_theme_stylebox_override("normal", normal_style)
	btn.add_theme_stylebox_override("hover", hover_style)
	btn.add_theme_stylebox_override("pressed", hover_style)

	var tex: Texture2D
	if discovered:
		tex = Inventory.get_texture(fish["name"])
		if not tex:
			tex = FishingManager.catch_textures.get(fish.get("rarity", "Common"))
	else:
		tex = load("res://Assets/Fish_Mystery.png")

	if tex:
		var tr = TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.anchor_left = 0.0
		tr.anchor_top = 0.0
		tr.anchor_right = 1.0
		tr.anchor_bottom = 1.0
		tr.offset_left = 4
		tr.offset_right = -4
		tr.offset_top = 4
		tr.offset_bottom = -4
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(tr)

	var lbl = Label.new()
	lbl.text = fish["name"] if discovered else "???"
	lbl.modulate = rarity_color
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	lbl.anchor_left = 0.0
	lbl.anchor_top = 0.0
	lbl.anchor_right = 1.0
	lbl.anchor_bottom = 1.0
	lbl.offset_left = 2
	lbl.offset_right = -2
	lbl.offset_bottom = -2
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(lbl)

	var f = fish
	btn.pressed.connect(func():
		_deselect_fish_btn()
		selected_fish_btn = btn
		var sel_style = _make_slot_style(true, rarity_color)
		btn.add_theme_stylebox_override("normal", sel_style)
		btn.add_theme_stylebox_override("hover", sel_style)
		btn.add_theme_stylebox_override("pressed", sel_style)
		_show_fish_detail(f, info, discovered)
	)
	grid.add_child(btn)

func _deselect_fish_btn():
	if selected_fish_btn == null:
		return
	var prev_color = selected_fish_btn.get_meta("rarity_color", Color.WHITE)
	selected_fish_btn.add_theme_stylebox_override("normal", _make_slot_style(false, prev_color))
	selected_fish_btn.add_theme_stylebox_override("hover", _make_slot_style(true, prev_color))
	selected_fish_btn.add_theme_stylebox_override("pressed", _make_slot_style(true, prev_color))
	selected_fish_btn = null

func _show_fish_detail(fish: Dictionary, detail: Control, discovered: bool):
	var rarity_color = _rarity_color(fish.get("rarity", ""))
	$PanelContainer/MarginContainer/CollectionSection/Panel5.color = rarity_color

	var name_label = $PanelContainer/MarginContainer/CollectionSection/Info/NameLabel
	var rarity_label = $PanelContainer/MarginContainer/CollectionSection/Info/RarityLabel
	var fish_image = $PanelContainer/MarginContainer/CollectionSection/Info/FishImage
	var habitat_label = $PanelContainer/MarginContainer/CollectionSection/Info/HabitatLabel
	var avg_weight_label = $PanelContainer/MarginContainer/CollectionSection/Info/AvgWeightLabel
	var hint_label = $PanelContainer/MarginContainer/CollectionSection/Info/HintLabel
	var stats_container = $PanelContainer/MarginContainer/CollectionSection/Info/StatsContainer
	var mutations_container = $PanelContainer/MarginContainer/CollectionSection/Info/MutationsContainer

	name_label.text = fish["name"] if discovered else "???"
	name_label.modulate = rarity_color
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 38)

	rarity_label.text = fish.get("rarity", "?")
	rarity_label.modulate = rarity_color
	rarity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var tex = Inventory.get_texture(fish["name"])
	if not tex:
		tex = FishingManager.catch_textures.get(fish.get("rarity", "Common"))
	if not tex:
		tex = load("res://Assets/Fish_Mystery.png")
	fish_image.texture = tex
	fish_image.modulate = Color(0, 0, 0, 1) if not discovered else Color(1, 1, 1, 1)

	habitat_label.text = "Habitat: " + fish.get("habitat", "?").capitalize()
	habitat_label.modulate = Color(0.7, 0.7, 0.7)
	habitat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	avg_weight_label.text = "Avg Weight: " + _format_weight(fish.get("base_weight_kg", 0.0)) if discovered else ""
	avg_weight_label.modulate = Color(0.7, 0.7, 0.7)
	avg_weight_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	hint_label.text = fish.get("hint", "")
	hint_label.modulate = Color(0.5, 0.5, 0.5)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.autowrap_mode = 3

	for child in stats_container.get_children():
		child.queue_free()
	for child in mutations_container.get_children():
		child.queue_free()

	if discovered:
		var base_name = fish["name"]
		var total_caught = fish_catch_counts.get(base_name, 0)
		var albino_caught = fish_catch_counts.get("albino_" + base_name, 0)
		var catches = _get_fish_catches(fish["name"])

		var biggest_label = Label.new()
		biggest_label.text = "Biggest: " + catches[0]
		stats_container.add_child(biggest_label)

		var smallest_label = Label.new()
		smallest_label.text = "Smallest: " + catches[1]
		stats_container.add_child(smallest_label)

		var caught_label = Label.new()
		caught_label.text = "Caught: " + str(total_caught)
		stats_container.add_child(caught_label)

		var mutations_title = Label.new()
		mutations_title.text = "Mutations:"
		mutations_title.add_theme_font_size_override("font_size", 14)
		mutations_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		mutations_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mutations_container.add_child(mutations_title)

		var albino_label = Label.new()
		albino_label.text = "Albino (" + str(albino_caught) + ")"
		albino_label.modulate = Color(0.3, 1.0, 0.3) if albino_caught > 0 else Color(1.0, 0.3, 0.3)
		albino_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		albino_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mutations_container.add_child(albino_label)

func _clear_panel():
	selected_fish_btn = null
	var panel = _get_panel()
	for child in panel.get_children():
		child.queue_free()

func _build_recipes_panel():
	_clear_panel()
	var panel = _get_panel()
	var label = Label.new()
	label.text = "Recipes coming soon"
	panel.add_child(label)

func _rarity_color(rarity: String) -> Color:
	match rarity:
		"Trash":     return Color(0.439, 0.439, 0.439, 1.0)
		"Common":    return Color(0.557, 0.733, 0.749, 1.0)
		"Uncommon":  return Color(0.0, 0.792, 0.325, 1.0)
		"Unusual":   return Color(0.753, 0.529, 0.776, 1.0)
		"Rare":      return Color(0.19, 0.28, 0.648, 1.0)
		"Epic":      return Color(0.651, 0.0, 0.664, 1.0)
		"Legendary": return Color(1.0, 0.8, 0.1)
		"Mythic":    return Color(1.0, 0.243, 0.471, 1.0)
		"Exotic":    return Color(0.0, 0.949, 1.0, 1.0)
	return Color.WHITE

func _get_fish_owned(fish_name: String) -> String:
	for slot in Inventory.slots:
		if slot["item"] == fish_name:
			return Inventory.get_fish_weight_display(fish_name, slot["count"])
	for slot in Inventory.inv_slots:
		if slot["item"] == fish_name:
			return Inventory.get_fish_weight_display(fish_name, slot["count"])
	return "None"

func discover_fish(fish_name: String, weight_kg: float):
	var base_name = fish_name.replace("Albino ", "")
	if not base_name in discovered_fish:
		discovered_fish.append(base_name)
	if not base_name in fish_records:
		fish_records[base_name] = {"biggest": weight_kg, "smallest": weight_kg}
	else:
		if weight_kg > fish_records[base_name]["biggest"]:
			fish_records[base_name]["biggest"] = weight_kg
		if weight_kg < fish_records[base_name]["smallest"]:
			fish_records[base_name]["smallest"] = weight_kg
	if not base_name in fish_catch_counts:
		fish_catch_counts[base_name] = 0
	fish_catch_counts[base_name] += 1
	if "Albino" in fish_name:
		var albino_key = "albino_" + base_name
		if not albino_key in fish_catch_counts:
			fish_catch_counts[albino_key] = 0
		fish_catch_counts[albino_key] += 1

func _get_fish_catches(fish_name: String) -> Array:
	if not fish_name in fish_records:
		return ["None", "None"]
	var rec = fish_records[fish_name]
	return [
		_format_weight(rec["biggest"]),
		_format_weight(rec["smallest"])
	]

func _format_weight(kg: float) -> String:
	if kg < 1.0:
		return str(int(kg * 1000)) + "g"
	return str(snappedf(kg, 0.01)) + "kg"

func _close_info_panel():
	var info = _get_info()
	for child in info.get_children():
		if child is Label:
			child.text = ""
	$PanelContainer/MarginContainer/CollectionSection/Panel5.color = Color(0, 0, 0, 0)
	_deselect_fish_btn()
