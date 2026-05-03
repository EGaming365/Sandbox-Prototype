extends Node

var placeable_items = {
	"Wood Plank": { "texture": null, "max_hits": 2 },
	"Stone Wall":  { "texture": null, "max_hits": 5 },
	"Wood Door":   { "texture": null, "max_hits": 3 },
}

func is_placeable(item_name: String) -> bool:
	return placeable_items.has(item_name)

func get_max_hits(item_name: String) -> int:
	if placeable_items.has(item_name):
		return placeable_items[item_name]["max_hits"]
	return 1
