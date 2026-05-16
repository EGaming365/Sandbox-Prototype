extends Sprite2D

var cooldown_pct: float = 0.0
var show_bar: bool = false
var _cooldown_duration: float = 0.0
var _cooldown_elapsed: float = 0.0

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)

func show_cooldown(duration: float):
	_cooldown_duration = duration
	_cooldown_elapsed = 0.0
	cooldown_pct = 1.0
	show_bar = true

func _process(delta):
	position = get_viewport().get_mouse_position()
	if show_bar:
		_cooldown_elapsed += delta
		cooldown_pct = 1.0 - clamp(_cooldown_elapsed / _cooldown_duration, 0.0, 1.0)
		if _cooldown_elapsed >= _cooldown_duration:
			show_bar = false
			cooldown_pct = 0.0
	queue_redraw()

func _draw():
	if not show_bar:
		return
	var bar_width = 10.0
	var bar_height = 4.0
	var offset = Vector2(-bar_width / 2, -10)
	draw_rect(Rect2(offset, Vector2(bar_width, bar_height)), Color(0.15, 0.15, 0.15, 0.95))
	var brightness = 0.2 + (0.6 * (1.0 - cooldown_pct))
	draw_rect(Rect2(offset, Vector2(bar_width * cooldown_pct, bar_height)), Color(brightness, brightness, brightness, 0.95))
