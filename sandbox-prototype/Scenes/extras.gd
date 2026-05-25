extends Control

var current_section: String = "game"
var current_collection_sub: String = "recipes"
var discovered_fish: Array = []

var fish_records: Dictionary = {}
var fish_catch_counts: Dictionary = {}

func _ready():
	hide()
	_connect_nav()
	_switch_section("game")
	_switch_collection_sub("recipes")

func toggle():
	if visible:
		hide()
	else:
		show()
		_switch_section(current_section)
		_switch_collection_sub(current_collection_sub)

func _process(_delta):
	if not visible:
		return
	if Input.is_action_just_pressed("click"):
		var mouse = get_global_mouse_position()
		var panel = $PanelContainer
		if not panel.get_global_rect().has_point(mouse):
			var extras_btn = get_tree().root.get_node_or_null("Scene/CanvasLayer/LeftUI")
			if extras_btn:
				var btn = extras_btn.get_node_or_null("HBoxContainer/Button")
				if btn and btn.get_global_rect().has_point(mouse):
					return
			hide()

func _connect_nav():
	$PanelContainer/VBoxContainer/HBoxContainer/Game.pressed.connect(func(): _switch_section("game"))
	$PanelContainer/VBoxContainer/HBoxContainer/Settings.pressed.connect(func(): _switch_section("settings"))
	$PanelContainer/VBoxContainer/HBoxContainer/Collection.pressed.connect(func(): _switch_section("collection"))
	$PanelContainer/VBoxContainer/HBoxContainer/Mastery.pressed.connect(func(): _switch_section("mastery"))
	$PanelContainer/VBoxContainer/HBoxContainer/Blank.pressed.connect(func(): _switch_section("blank"))
	$PanelContainer/VBoxContainer/MarginContainer/CollectionSection/HBoxContainer/Recipes.pressed.connect(func(): _switch_collection_sub("recipes"))
	$PanelContainer/VBoxContainer/MarginContainer/CollectionSection/HBoxContainer/Fish.pressed.connect(func(): _switch_collection_sub("fish"))

func _switch_section(section: String):
	current_section = section
	var sections = {
		"game":       $PanelContainer/VBoxContainer/MarginContainer/GameSection,
		"settings":   $PanelContainer/VBoxContainer/MarginContainer/SettingsSection,
		"collection": $PanelContainer/VBoxContainer/MarginContainer/CollectionSection,
		"mastery":    $PanelContainer/VBoxContainer/MarginContainer/MasterySection,
		"blank":      $PanelContainer/VBoxContainer/MarginContainer/BlankSection,
	}
	for key in sections:
		sections[key].visible = (key == section)
	var nav = $PanelContainer/VBoxContainer/HBoxContainer
	for btn in nav.get_children():
		btn.modulate = Color(1.5, 1.8, 1.5, 1.0) if btn.name.to_lower() == section else Color(0.6, 0.6, 0.6, 1.0)

func _switch_collection_sub(sub: String):
	current_collection_sub = sub
	var subnav = $PanelContainer/VBoxContainer/MarginContainer/CollectionSection/HBoxContainer
	for btn in subnav.get_children():
		btn.modulate = Color(1.5, 1.8, 1.5, 1.0) if btn.name.to_lower() == sub else Color(0.6, 0.6, 0.6, 1.0)
	match sub:
		"recipes":
			_build_recipes_panel()
		"fish":
			_build_fish_panel()

func _get_panel() -> Node:
	return $PanelContainer/VBoxContainer/MarginContainer/CollectionSection/Panel

func _clear_panel():
	var panel = _get_panel()
	for child in panel.get_children():
		child.queue_free()

func _build_recipes_panel():
	_clear_panel()
	var panel = _get_panel()
	var label = Label.new()
	label.text = "Recipes coming soon"
	panel.add_child(label)

func _build_fish_panel():
	_clear_panel()
	var panel = _get_panel()

	var fish_table = FishingManager.FISH_TABLE

	var hbox = HBoxContainer.new()
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(hbox)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(scroll)

	var grid = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)

	var detail = VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(detail)

	for fish in fish_table:
		_add_fish_slot(grid, fish, detail)

func _add_fish_slot(grid: GridContainer, fish: Dictionary, detail: VBoxContainer):
	var discovered = fish["name"] in discovered_fish

	var btn = Button.new()
	btn.custom_minimum_size = Vector2(64, 64)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.3, 0.3, 0.3, 1.0)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)

	var tex = Inventory.get_texture(fish["name"])
	if not tex:
		tex = FishingManager.catch_textures.get(fish.get("rarity", "Common"))
	if tex:
		var tr = TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_FIT_WIDTH
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tr.offset_left = 4
		tr.offset_right = -4
		tr.offset_top = 4
		tr.offset_bottom = -4
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not discovered:
			tr.modulate = Color(0, 0, 0, 1)
		btn.add_child(tr)

	var f = fish
	btn.pressed.connect(func(): _show_fish_detail(f, detail, discovered))
	grid.add_child(btn)

func _show_fish_detail(fish: Dictionary, detail: VBoxContainer, discovered: bool):
	for child in detail.get_children():
		child.queue_free()

	var name_label = Label.new()
	name_label.text = fish["name"] if discovered else "???"
	name_label.add_theme_font_size_override("font_size", 20)
	detail.add_child(name_label)

	if discovered:
		var tex = Inventory.get_texture(fish["name"])
		if not tex:
			tex = FishingManager.catch_textures.get(fish.get("rarity", "Common"))
		if tex:
			var icon = TextureRect.new()
			icon.texture = tex
			icon.custom_minimum_size = Vector2(80, 80)
			icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			detail.add_child(icon)

		var main_hbox = HBoxContainer.new()
		main_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		detail.add_child(main_hbox)

		var left_col = VBoxContainer.new()
		left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		main_hbox.add_child(left_col)

		var right_col = VBoxContainer.new()
		right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		main_hbox.add_child(right_col)

		var base_name = fish["name"]
		var total_caught = fish_catch_counts.get(base_name, 0)
		var albino_caught = fish_catch_counts.get("albino_" + base_name, 0)

		var rarity_label = Label.new()
		rarity_label.text = "Rarity: " + fish.get("rarity", "?")
		rarity_label.modulate = _rarity_color(fish.get("rarity", ""))
		left_col.add_child(rarity_label)

		var habitat_label = Label.new()
		habitat_label.text = "Habitat: " + fish.get("habitat", "?").capitalize()
		left_col.add_child(habitat_label)

		var avg_kg = fish.get("base_weight_kg", 0.0)
		var weight_label = Label.new()
		weight_label.text = "Avg Weight: " + _format_weight(avg_kg)
		left_col.add_child(weight_label)

		var catches = _get_fish_catches(fish["name"])
		var biggest_label = Label.new()
		biggest_label.text = "Biggest: " + catches[0]
		left_col.add_child(biggest_label)

		var smallest_label = Label.new()
		smallest_label.text = "Smallest: " + catches[1]
		left_col.add_child(smallest_label)

		var caught_label = Label.new()
		caught_label.text = "Caught: " + str(total_caught)
		left_col.add_child(caught_label)

		var mutations_title = Label.new()
		mutations_title.text = "Mutations:"
		mutations_title.add_theme_font_size_override("font_size", 14)
		right_col.add_child(mutations_title)

		var albino_label = Label.new()
		albino_label.text = "Albino (" + str(albino_caught) + ")"
		albino_label.modulate = Color(0.3, 1.0, 0.3) if albino_caught > 0 else Color(1.0, 0.3, 0.3)
		right_col.add_child(albino_label)
	else:
		var hint = Label.new()
		hint.text = "Catch this fish to reveal it"
		hint.modulate = Color(0.5, 0.5, 0.5)
		detail.add_child(hint)

func _rarity_color(rarity: String) -> Color:
	match rarity:
		"Common":    return Color(0.8, 0.8, 0.8)
		"Uncommon":  return Color(0.3, 1.0, 0.3)
		"Rare":      return Color(0.3, 0.5, 1.0)
		"Legendary": return Color(1.0, 0.8, 0.1)
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
