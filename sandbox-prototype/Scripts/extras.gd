# Extras menu.
# A screen with two sections. The Game section holds the settings sliders, and the Collection section shows a fish book with the fish the player has caught, their records and details.
# It also shows notifications for the aurora and for daily events.

extends Control

# Section currently shown: game or collection.
var current_section: String = "game"
# Names of the fish the player has caught at least once.
var discovered_fish: Array = []
# Biggest and smallest weight caught for each fish.
var fish_records: Dictionary = {}
# Reserved for counting catches. It is not currently used.
var fish_catch_counts: Dictionary = {}
# Normal colour of each tab's underline mark, used to darken and lighten it.
var mark_base_colors: Dictionary = {}
# Normal colour of each tab button.
var btn_base_colors: Dictionary = {}
# The fish slot that is currently selected.
var selected_fish_btn: Button = null
# True while an aurora is happening.
var aurora_active: bool = false

# Number of columns in the fish book grid.
@export var fish_columns: int = 6
# Size in pixels of each fish slot.
@export var fish_slot_size: int = 116
# Gap in pixels between fish slots.
@export var fish_slot_separation: int = 6
# Seconds a notification stays fully visible.
@export var notification_duration: float = 4.0
# Seconds a notification takes to fade out.
@export var notification_fade_time: float = 1.0
# Vertical position of notifications relative to the screen centre.
@export var notification_y_offset: float = -600.0


# Starts hidden, connects the tabs, remembers the colours, sets up the sliders and shows the Game section.
func _ready():
	hide()
	_connect_nav()
	_cache_base_colors()
	_setup_settings_sliders()
	_switch_section("game")
	get_viewport().gui_focus_changed.connect(func(_c): pass)


# Sets up the volume, darkness and render distance sliders and connects each one to the settings manager.
func _setup_settings_sliders():
	var volume_slider := $PanelContainer/MarginContainer/GameSection/Volume/HSlider as HSlider
	volume_slider.min_value = 0.0
	volume_slider.max_value = 100.0
	volume_slider.step = 1.0
	volume_slider.value = SettingsManager.master_volume
	volume_slider.value_changed.connect(func(should_show): SettingsManager.set_master_volume(should_show))

	var darkness_slider := $PanelContainer/MarginContainer/GameSection/Darkness/HSlider as HSlider
	darkness_slider.min_value = 0.0
	darkness_slider.max_value = 100.0
	darkness_slider.step = 1.0
	darkness_slider.value = SettingsManager.darkness
	darkness_slider.value_changed.connect(func(should_show): SettingsManager.set_darkness(should_show))

	var render_slider := $PanelContainer/MarginContainer/GameSection/Render/HSlider as HSlider
	render_slider.min_value = 1.0
	render_slider.max_value = 10.0
	render_slider.step = 1.0
	render_slider.value = float(SettingsManager.render_distance)
	render_slider.value_changed.connect(func(should_show): SettingsManager.set_render_distance(int(should_show)))

# True for the frame in which the menu opened, so the same key press does not close it again.
var _just_opened: bool = false


# Opens the menu, or closes it if it is already open.
func toggle():
	if visible:
		close_ui()
	else:
		show()
		_just_opened = true
		_switch_section(current_section)


# Hides the menu, clears the fish details and hides the online buttons.
func close_ui():
	hide()
	_close_info_panel()
	_set_online_ui(false)


# Shows or hides the host and join buttons in the main scene.
func _set_online_ui(should_show: bool) -> void:
	var scene_root = get_tree().root.get_node_or_null("Scene")
	if scene_root and scene_root.has_method("set_online_ui_visible"):
		scene_root.set_online_ui_visible(should_show)


# Closes the menu with the exit key and keeps the tab marks in the correct colour.
func _process(_delta):
	if _just_opened:
		_just_opened = false
		return
	if not visible:
		return
	if Input.is_action_just_pressed("exit"):
		close_ui()
		get_viewport().set_input_as_handled()
		return
	if Input.is_action_just_pressed("click"):
		if get_viewport().is_input_handled():
			return
		var mouse = get_global_mouse_position()
		var panel_rect = $PanelContainer.get_global_rect()
		var nav_rect = $PanelContainer/VBoxContainer/HBoxContainer.get_global_rect()
		var safe_rect = panel_rect.merge(nav_rect)
		if not safe_rect.has_point(mouse):
			close_ui()
			get_viewport().set_input_as_handled()


# Closes the menu when the player clicks outside its panel.
func _input(event):
	if _just_opened or not visible:
		return
	if event.is_action_pressed("click"):
		var mouse = get_global_mouse_position()
		var panel_rect = $PanelContainer.get_global_rect()
		var nav_rect = $PanelContainer/VBoxContainer/HBoxContainer.get_global_rect()
		if not panel_rect.merge(nav_rect).has_point(mouse):
			close_ui()
			get_viewport().set_input_as_handled()


# Turns the aurora on or off, updates the HUD icon and shows a notification when it starts.
func set_aurora(state: bool):
	aurora_active = state
	var hud = get_tree().root.get_node_or_null("Scene/CanvasLayer/RightUI")
	if hud and hud.has_method("set_aurora_icon"):
		hud.set_aurora_icon(state)
	if state:
		_show_aurora_notification()


# Builds and fades out an on screen message announcing the aurora, mentioning any weather that hides it.
func _show_aurora_notification():
	var canvas = get_tree().root.get_node_or_null("Scene/CanvasLayer")
	if not canvas:
		return
	var weather = get_tree().root.get_node_or_null("Scene/Weather")
	var is_raining = weather and (weather.current_weather == weather.WeatherType.RAIN or \
		weather.current_weather == weather.WeatherType.THUNDER or \
		weather.current_weather == weather.WeatherType.THUNDERSTORM)

	var vbox = VBoxContainer.new()
	vbox.anchor_left = 0.5
	vbox.anchor_top = 0.5
	vbox.anchor_right = 0.5
	vbox.anchor_bottom = 0.5
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.z_index = 20

	var row1 = HBoxContainer.new()
	row1.alignment = BoxContainer.ALIGNMENT_CENTER

	var part1 = Label.new()
	part1.text = "Tonight is the illusive "
	part1.add_theme_font_size_override("font_size", 22)
	part1.add_theme_color_override("font_color", Color.WHITE)
	part1.add_theme_color_override("font_outline_color", Color.BLACK)
	part1.add_theme_constant_override("outline_size", 5)
	row1.add_child(part1)

	var part2 = Label.new()
	part2.text = "Aurora Borealis"
	part2.add_theme_font_size_override("font_size", 22)
	part2.add_theme_color_override("font_color", Color(0.18, 0.85, 0.65))
	part2.add_theme_color_override("font_outline_color", Color.BLACK)
	part2.add_theme_constant_override("outline_size", 5)
	row1.add_child(part2)

	var part3 = Label.new()
	part3.text = "! Luck is Drastically Increased."
	part3.add_theme_font_size_override("font_size", 22)
	part3.add_theme_color_override("font_color", Color.WHITE)
	part3.add_theme_color_override("font_outline_color", Color.BLACK)
	part3.add_theme_constant_override("outline_size", 5)
	row1.add_child(part3)

	vbox.add_child(row1)

	if is_raining:
		var row2 = Label.new()
		row2.text = "It has started raining."
		row2.add_theme_font_size_override("font_size", 22)
		row2.add_theme_color_override("font_color", Color.WHITE)
		row2.add_theme_color_override("font_outline_color", Color.BLACK)
		row2.add_theme_constant_override("outline_size", 5)
		row2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(row2)

	canvas.add_child(vbox)
	await get_tree().process_frame
	vbox.offset_left = -vbox.size.x / 2.0
	vbox.offset_right = vbox.size.x / 2.0
	vbox.offset_top = -vbox.size.y / 2.0 + notification_y_offset
	vbox.offset_bottom = vbox.size.y / 2.0 + notification_y_offset

	var tween = vbox.create_tween()
	tween.tween_interval(notification_duration)
	tween.tween_property(vbox, "modulate:a", 0.0, notification_fade_time)
	tween.tween_callback(vbox.queue_free)


# Builds and fades out an on screen message for a daily event such as a rainbow or a divine blessing.
func show_day_event_notification(event_name: String):
	var canvas = get_tree().root.get_node_or_null("Scene/CanvasLayer")
	if not canvas:
		return
	var vbox = VBoxContainer.new()
	vbox.anchor_left = 0.5
	vbox.anchor_top = 0.5
	vbox.anchor_right = 0.5
	vbox.anchor_bottom = 0.5
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.z_index = 20

	var title = Label.new()
	var title_color: Color
	var detail_text: String
	match event_name:
		"Divine Blessing":
			title.text = "You have received a Divine Blessing!"
			title_color = Color(1.0, 0.85, 0.18)
			detail_text = "Fishing Mutation Chances are Increased."
		"Rainbow":
			title.text = "A Rainbow has appeared!"
			title_color = Color(0.914, 0.455, 0.639, 1.0)
			detail_text = "Luck has increased."
		_:
			title.text = event_name
			title_color = Color(1.0, 1.0, 1.0)
			detail_text = "A day event has begun."

	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", title_color)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 5)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var detail = Label.new()
	detail.text = detail_text
	detail.add_theme_font_size_override("font_size", 20)
	detail.add_theme_color_override("font_color", Color.WHITE)
	detail.add_theme_color_override("font_outline_color", Color.BLACK)
	detail.add_theme_constant_override("outline_size", 5)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(detail)

	canvas.add_child(vbox)
	await get_tree().process_frame
	vbox.offset_left = -vbox.size.x / 2.0
	vbox.offset_right = vbox.size.x / 2.0
	vbox.offset_top = -vbox.size.y / 2.0 + notification_y_offset
	vbox.offset_bottom = vbox.size.y / 2.0 + notification_y_offset

	var tween = vbox.create_tween()
	tween.tween_interval(notification_duration)
	tween.tween_property(vbox, "modulate:a", 0.0, notification_fade_time)
	tween.tween_callback(vbox.queue_free)


# Remembers the normal colours of the tab buttons and their marks.
func _cache_base_colors():
	for section_name in ["Game", "Collection"]:
		var button = $PanelContainer/VBoxContainer/HBoxContainer.get_node(section_name) as Button
		var mark = button.get_node(section_name + "Mark") as ColorRect
		mark_base_colors[section_name] = mark.color
		var normal_style = button.get_theme_stylebox("normal")
		if normal_style is StyleBoxFlat:
			btn_base_colors[section_name] = normal_style.bg_color
		else:
			btn_base_colors[section_name] = Color(0.2, 0.2, 0.2, 1.0)
		var hover_style = StyleBoxFlat.new()
		hover_style.bg_color = btn_base_colors[section_name].lightened(0.3)
		button.add_theme_stylebox_override("hover", hover_style)
		var pressed_style = StyleBoxFlat.new()
		pressed_style.bg_color = btn_base_colors[section_name].darkened(0.3)
		button.add_theme_stylebox_override("pressed", pressed_style)


# Connects the tab buttons so they switch sections and highlight when hovered or pressed.
func _connect_nav():
	$PanelContainer/VBoxContainer/HBoxContainer/Game.pressed.connect(func(): _switch_section("game"))
	get_node("PanelContainer/VBoxContainer/HBoxContainer/Collection").pressed.connect(
		func(): _switch_section("collection")
	)
	for section_name in ["Game", "Collection"]:
		var button = $PanelContainer/VBoxContainer/HBoxContainer.get_node(section_name) as Button
		var capture = section_name
		button.mouse_entered.connect(func(): _update_mark(capture))
		button.mouse_exited.connect(func(): _update_mark(capture))
		button.button_down.connect(func(): _update_mark(capture))
		button.button_up.connect(func(): _update_mark(capture))


# Makes a tab's mark darker when pressed and lighter when hovered.
func _update_mark(btn_name: String):
	var button = $PanelContainer/VBoxContainer/HBoxContainer.get_node(btn_name) as Button
	var mark = button.get_node(btn_name + "Mark") as ColorRect
	if button.button_pressed or Input.is_action_pressed("click") and button.is_hovered():
		mark.color = mark_base_colors[btn_name].darkened(0.3)
	elif button.is_hovered():
		mark.color = mark_base_colors[btn_name].lightened(0.3)
	else:
		mark.color = mark_base_colors[btn_name]


# Shows the chosen section and hides the other. The Collection section rebuilds the fish book.
func _switch_section(section: String):
	current_section = section
	var sections = {
		"game":       $PanelContainer/MarginContainer/GameSection,
		"collection": $PanelContainer/MarginContainer/CollectionSection,
	}
	for key in sections:
		sections[key].visible = (key == section)
	var marks = {
		"game":       $PanelContainer/VBoxContainer/HBoxContainer/Game/GameMark,
		"collection": $PanelContainer/VBoxContainer/HBoxContainer/Collection/CollectionMark,
	}
	for key in marks:
		marks[key].visible = (key == section)
	if section == "collection":
		_build_fish_panel()
	# The online buttons only belong on the Game tab, so they follow it here too.
	if visible:
		_set_online_ui(section == "game")


# Returns the panel that holds the fish grid.
func _get_panel() -> Node:
	return $PanelContainer/MarginContainer/CollectionSection/Panel


# Returns the panel that shows details of the selected fish.
func _get_info() -> Node:
	return $PanelContainer/MarginContainer/CollectionSection/Info


# Clears the fish book and fills it again.
func _build_fish_panel():
	_clear_panel()
	var panel = _get_panel()
	var info = _get_info()
	call_deferred("_populate_fish_panel", panel, info)


# Creates a scrolling grid with a slot for every fish in the game.
func _populate_fish_panel(panel: Control, info: Control):
	var columns = fish_columns
	var slot_size = fish_slot_size
	var separation = fish_slot_separation
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
	scroll.scroll_vertical_custom_step = 28.0
	panel.add_child(scroll)
	call_deferred("_style_fish_scrollbar", scroll)

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

	var rarity_order = {
		"Trash": 0, "Common": 1, "Uncommon": 2, "Unusual": 3, "Rare": 4,
		"Epic": 5, "Legendary": 6, "Mythic": 7, "Exotic": 8,
	}
	var sorted_fish = FishingManager.FISH_TABLE.duplicate()
	sorted_fish.sort_custom(func(a, b):
		var ra = rarity_order.get(a.get("rarity", "Common"), 0)
		var rb = rarity_order.get(b.get("rarity", "Common"), 0)
		return ra < rb
	)

	for fish in sorted_fish:
		_add_fish_slot(grid, fish, info)


# Returns the style of a fish slot, with an optional coloured border.
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


# Adds one fish slot. Fish that have not been caught are hidden, and clicking a slot shows its details.
func _add_fish_slot(grid: GridContainer, fish: Dictionary, info: Control):
	var discovered = fish["name"] in discovered_fish
	var rarity_color = _rarity_color(fish.get("rarity", ""))

	var button = Button.new()
	button.custom_minimum_size = Vector2(106, 126)
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	button.clip_contents = true
	button.set_meta("rarity_color", rarity_color)

	var normal_style = _make_slot_style(false, rarity_color)
	var hover_style = _make_slot_style(true, rarity_color)
	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override("hover", hover_style)
	button.add_theme_stylebox_override("pressed", hover_style)

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
		button.add_child(tr)

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
	button.add_child(lbl)

	var f = fish
	button.pressed.connect(func():
		_deselect_fish_btn()
		selected_fish_btn = button
		var sel_style = _make_slot_style(true, rarity_color)
		button.add_theme_stylebox_override("normal", sel_style)
		button.add_theme_stylebox_override("hover", sel_style)
		button.add_theme_stylebox_override("pressed", sel_style)
		_show_fish_detail(f, info, discovered)
	)
	grid.add_child(button)


# Removes the highlight from the selected fish slot.
func _deselect_fish_btn():
	if selected_fish_btn == null:
		return
	var prev_color = selected_fish_btn.get_meta("rarity_color", Color.WHITE)
	selected_fish_btn.add_theme_stylebox_override("normal", _make_slot_style(false, prev_color))
	selected_fish_btn.add_theme_stylebox_override("hover", _make_slot_style(true, prev_color))
	selected_fish_btn.add_theme_stylebox_override("pressed", _make_slot_style(true, prev_color))
	selected_fish_btn = null


# Fills the details panel with the fish's name, rarity, habitat, records and the amount owned.
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
	var mutations_container = get_node(
		"PanelContainer/MarginContainer/CollectionSection/Info/MutationsContainer",
	)

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

	habitat_label.text = "Location: " + fish.get("habitat", "?").capitalize()
	habitat_label.modulate = Color(0.7, 0.7, 0.7)
	habitat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	avg_weight_label.text = (
		"Avg Weight: " + _format_weight(fish.get("base_weight_kg", 0.0)) if discovered else ""
	)
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


# Removes every slot from the fish grid.
func _clear_panel():
	selected_fish_btn = null
	var panel = _get_panel()
	for child in panel.get_children():
		child.queue_free()


# Returns the colour for a rarity, from Trash up to the rarest fish.
func _rarity_color(rarity: String) -> Color:
	match rarity:
		"Trash":     return Color(0.439, 0.439, 0.439, 1.0)
		"Common":    return Color(0.557, 0.733, 0.749, 1.0)
		"Uncommon":  return Color(0.0, 0.792, 0.325, 1.0)
		"Unusual":   return Color(0.753, 0.529, 0.776, 1.0)
		"Rare":      return Color(0.498, 0.659, 1.0, 1.0)
		"Epic":      return Color(0.517, 0.0, 0.528, 1.0)
		"Legendary": return Color(1.0, 0.8, 0.1)
		"Mythic":    return Color(1.0, 0.243, 0.471, 1.0)
		"Exotic":    return Color(0.0, 0.949, 1.0, 1.0)
	return Color.WHITE


# Returns the weight of the fish the player currently holds, as text.
func _get_fish_owned(fish_name: String) -> String:
	for slot in Inventory.slots:
		if slot["item"] == fish_name:
			return Inventory.get_fish_weight_display(fish_name, slot["count"])
	for slot in Inventory.inv_slots:
		if slot["item"] == fish_name:
			return Inventory.get_fish_weight_display(fish_name, slot["count"])
	return "None"


# Records a caught fish and updates its biggest and smallest weight. Albino fish count as their normal fish.
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


# Returns the biggest and smallest catch as text, or 'None' if the fish has not been caught.
func _get_fish_catches(fish_name: String) -> Array:
	if not fish_name in fish_records:
		return ["None", "None"]
	var fish_record = fish_records[fish_name]
	return [
		_format_weight(fish_record["biggest"]),
		_format_weight(fish_record["smallest"])
	]


# Formats a weight in grams below one kilogram and in kilograms above.
func _format_weight(kg: float) -> String:
	if kg < 1.0:
		return str(int(kg * 1000)) + "g"
	return str(snappedf(kg, 0.01)) + "kg"


# Makes the scrollbar of the fish grid wider and moves it beside the grid.
func _style_fish_scrollbar(scroll: ScrollContainer):
	var bar := scroll.get_v_scroll_bar()
	if not bar:
		return
	bar.custom_minimum_size.x = 18
	bar.size.x = 18
	bar.position.x = scroll.size.x + 8


# Clears the fish details and removes the selection.
func _close_info_panel():
	var info = _get_info()
	for child in info.get_children():
		if child is Label:
			child.text = ""
	$PanelContainer/MarginContainer/CollectionSection/Panel5.color = Color(0, 0, 0, 0)
	_deselect_fish_btn()
