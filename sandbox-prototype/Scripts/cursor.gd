extends Sprite2D

@export var controller_cursor_speed: float = 900.0

var cooldowns: Array = []
var _virtual_pos: Vector2 = Vector2.ZERO


func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	_virtual_pos = get_viewport().get_mouse_position()


func show_cooldown(progress_fraction: float, cooldown_id: String = "default"):
	for cooldown in cooldowns:
		if cooldown["id"] == cooldown_id:
			cooldown["pct"] = progress_fraction
			if progress_fraction <= 0.01:
				cooldowns.erase(cooldown)
			return
	if progress_fraction > 0.01:
		cooldowns.append({"id": cooldown_id, "pct": progress_fraction})


func _process(delta):
	var input_vector := Input.get_vector("cursor_left", "cursor_right", "cursor_up", "cursor_down")
	if input_vector != Vector2.ZERO:
		_virtual_pos += input_vector * controller_cursor_speed * delta
		var viewport_size := get_viewport().get_visible_rect().size
		_virtual_pos.x = clamp(_virtual_pos.x, 0.0, viewport_size.x)
		_virtual_pos.y = clamp(_virtual_pos.y, 0.0, viewport_size.y)
		Input.warp_mouse(_virtual_pos)
	else:
		_virtual_pos = get_viewport().get_mouse_position()
	position = get_viewport().get_mouse_position()
	queue_redraw()


func _draw():
	if cooldowns.is_empty():
		return
	var bar_width = 10.0
	var bar_height = 4.0
	var bar_spacing = 6.0
	for i in cooldowns.size():
		var progress_fraction = cooldowns[i]["pct"]
		var offset = Vector2(-bar_width / 2, -10 - (i * bar_spacing))
		draw_rect(
			Rect2(offset, Vector2(bar_width, bar_height)),
			Color(0.15, 0.15, 0.15, 0.95),
		)
		var brightness = 0.2 + (0.6 * (1.0 - progress_fraction))
		draw_rect(
			Rect2(offset, Vector2(bar_width * progress_fraction, bar_height)),
			Color(brightness, brightness, brightness, 0.95),
		)
