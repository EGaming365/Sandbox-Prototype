extends Control

@export var is_advanced: bool = false
var recipes = []

func _ready():
	hide()
	_build_ui()

func open(advanced: bool = false):
	is_advanced = advanced
	recipes = Crafting.advanced_recipes if advanced else Crafting.basic_recipes
	_build_ui()
	show()

func close():
	hide()

func _build_ui():
	# Clear existing
	for child in $VBoxContainer.get_children():
		child.queue_free()

	var title = $VBoxContainer/Title if $VBoxContainer.has_node("Title") else null

	var recipes_to_show = Crafting.advanced_recipes if is_advanced else Crafting.basic_recipes

	for recipe in recipes_to_show:
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)

		# Icon
		var icon = TextureRect.new()
		icon.texture = Crafting.get_item_texture(recipe["result"])
		icon.custom_minimum_size = Vector2(32, 32)
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH
		row.add_child(icon)

		# Label
		var label = Label.new()
		var ingredient_text = ""
		for item in recipe["ingredients"]:
			ingredient_text += str(recipe["ingredients"][item]) + "x " + item + "  "
		label.text = ingredient_text + "→  " + str(recipe["result_count"]) + "x " + recipe["result"]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)

		# Craft button
		var btn = Button.new()
		btn.text = "Craft"
		btn.pressed.connect(func(): _on_craft_pressed(recipe, btn))
		row.add_child(btn)

		$VBoxContainer.add_child(row)

func _on_craft_pressed(recipe: Dictionary, btn: Button):
	if Crafting.can_craft(recipe):
		Crafting.craft(recipe)
		# Flash green
		btn.text = "Done!"
		await get_tree().create_timer(0.5).timeout
		btn.text = "Craft"
	else:
		# Flash red
		btn.text = "Need more!"
		await get_tree().create_timer(0.5).timeout
		btn.text = "Craft"

func _process(_delta):
	if visible:
		# Refresh button states every frame
		for row in $VBoxContainer.get_children():
			if row is HBoxContainer:
				var btn = row.get_child(2)
				var recipe = _get_recipe_for_row(row)
				if recipe and btn:
					btn.disabled = not Crafting.can_craft(recipe)

func _get_recipe_for_row(row: HBoxContainer):
	var label = row.get_child(1) as Label
	var recipes_to_check = Crafting.advanced_recipes if is_advanced else Crafting.basic_recipes
	for recipe in recipes_to_check:
		if label.text.contains(recipe["result"]):
			return recipe
	return null
