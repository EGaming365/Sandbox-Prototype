extends Control

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _draw():
	draw_line(Vector2(0, 0), Vector2(500, 500), Color.BLUE, 3.0)
	draw_line(Vector2(500, 0), Vector2(0, 500), Color.RED, 3.0)
