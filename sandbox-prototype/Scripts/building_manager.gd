# Building manager autoload.
# Stores which items can be placed in the world and how many hits each placed block can take.

extends Node

# Placeable items. Each entry holds an unused texture slot and the number of hits needed to break the block.
var placeable_items = {
	"Wood Plank": { "texture": null, "max_hits": 2 },
	"Stone Wall": { "texture": null, "max_hits": 5 },
	"Wood Door": { "texture": null, "max_hits": 3 },
	"Crafting_Bench": { "texture": null, "max_hits": 2 },
	"Wardrobe": { "texture": null, "max_hits": 1 },
	"Torch": { "texture": null, "max_hits": 1 },
}


# Returns true if the item can be placed as a block.
func is_placeable(item_name: String) -> bool:
	return placeable_items.has(item_name)


# Returns how many hits the placed block can take, or 1 for items that are not listed.
func get_max_hits(item_name: String) -> int:
	if placeable_items.has(item_name):
		return placeable_items[item_name]["max_hits"]
	return 1
