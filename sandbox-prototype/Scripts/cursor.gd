extends Sprite2D

var cooldowns: Array = []

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)

func show_cooldown(pct: float, id: String = "default"):
	for c in cooldowns:
		if c["id"] == id:
			c["pct"] = pct
			if pct <= 0.01:
				cooldowns.erase(c)
			return
	if pct > 0.01:
		cooldowns.append({"id": id, "pct": pct})

func _process(_delta):
	position = get_viewport().get_mouse_position()
	queue_redraw()

func _draw():
	if cooldowns.is_empty():
		return
	var bar_width = 10.0
	var bar_height = 4.0
	var spacing = 6.0
	for i in cooldowns.size():
		var pct = cooldowns[i]["pct"]
		var offset = Vector2(-bar_width / 2, -10 - (i * spacing))
		draw_rect(Rect2(offset, Vector2(bar_width, bar_height)), Color(0.15, 0.15, 0.15, 0.95))
		var brightness = 0.2 + (0.6 * (1.0 - pct))
		draw_rect(Rect2(offset, Vector2(bar_width * pct, bar_height)), Color(brightness, brightness, brightness, 0.95))
