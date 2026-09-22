# Crafting menu.
# Builds a list of recipes with a Craft button for each one and enables the button only when the player has the ingredients.

extends Control

# True to show the advanced recipes, false for the basic recipes.
@export var is_advanced: bool = false
# Recipes currently displayed.
var recipes = []


# Start hidden with the recipe list already built.
func _ready():
	hide()
	_build_ui()


# Shows the menu with either the basic or the advanced recipes.
func open(show_advanced_recipes: bool = false):
	is_advanced = show_advanced_recipes
	recipes = Crafting.advanced_recipes if show_advanced_recipes else Crafting.basic_recipes
	_build_ui()
	show()


# Hides the menu.
func close():
	hide()


# Rebuilds the list, with one row per recipe containing an icon, the ingredient text and a Craft button.
func _build_ui():
	var recipe_list = $PanelContainer/VBoxContainer
	# Remove the old rows first.
	for child in recipe_list.get_children():
		child.queue_free()

	# Pick the recipe list for this menu.
	var recipes_to_show = Crafting.advanced_recipes if is_advanced else Crafting.basic_recipes
	for recipe in recipes_to_show:
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)

		# Picture of the item that will be crafted.
		var icon = TextureRect.new()
		icon.texture = Crafting.get_item_texture(recipe["result"])
		icon.custom_minimum_size = Vector2(32, 32)
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH
		row.add_child(icon)

		# Text showing the ingredients and what they make.
		var label = Label.new()
		var ingredient_text = ""
		for item in recipe["ingredients"]:
			ingredient_text += str(recipe["ingredients"][item]) + "x " + item + "  "
		label.text = ingredient_text + "→  " + str(recipe["result_count"]) + "x " + recipe["result"]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)

		# Button that crafts the item when pressed.
		var craft_button = Button.new()
		craft_button.text = "Craft"
		craft_button.pressed.connect(func(): _on_craft_pressed(recipe, craft_button))
		row.add_child(craft_button)

		recipe_list.add_child(row)


# Crafts the item if the player has the ingredients and briefly shows the result on the button.
func _on_craft_pressed(recipe: Dictionary, craft_button: Button):
	if Crafting.can_craft(recipe):
		Crafting.craft(recipe)
		craft_button.text = "Done!"
		await get_tree().create_timer(0.5).timeout
		craft_button.text = "Craft"
	else:
		craft_button.text = "Need more!"
		await get_tree().create_timer(0.5).timeout
		craft_button.text = "Craft"


# While visible, disables each Craft button the player cannot afford.
func _process(_delta):
	if visible:
		var recipe_list = $PanelContainer/VBoxContainer
		for row in recipe_list.get_children():
			if row is HBoxContainer:
				var craft_button = row.get_child(2)
				var recipe = _get_recipe_for_row(row)
				if recipe and craft_button:
					craft_button.disabled = not Crafting.can_craft(recipe)


# Finds the recipe belonging to a row by matching its result name in the row's label.
func _get_recipe_for_row(row: HBoxContainer):
	var label = row.get_child(1) as Label
	var recipes_to_check = Crafting.advanced_recipes if is_advanced else Crafting.basic_recipes
	for recipe in recipes_to_check:
		if label.text.contains(recipe["result"]):
			return recipe
	return null
