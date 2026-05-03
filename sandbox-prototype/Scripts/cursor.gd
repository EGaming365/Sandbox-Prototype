extends Sprite2D

var cooldown_pct: float = 0.0
var show_bar: bool = false
var bar_timer: float = 0.0

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)

func show_cooldown(pct: float):
	cooldown_pct = pct
	show_bar = true
	bar_timer = 0.1

func _process(delta):
	position = get_viewport().get_mouse_position()
	if bar_timer > 0:
		bar_timer -= delta
	if bar_timer <= 0:
		show_bar = false
	queue_redraw()

func _draw():
	if not show_bar:
		return
	var bar_width = 10.0
	var bar_height = 4.0
	var offset = Vector2(-bar_width / 2, -10)
	# Dark gray background
	draw_rect(Rect2(offset, Vector2(bar_width, bar_height)), Color(0.15, 0.15, 0.15, 0.95))
	# Fill goes from dark gray (full cooldown) to light gray (almost ready)
	var fill_color = Color(0.2 + (0.6 * (1.0 - cooldown_pct)), 0.2 + (0.6 * (1.0 - cooldown_pct)), 0.2 + (0.6 * (1.0 - cooldown_pct)), 0.95)
	draw_rect(Rect2(offset, Vector2(bar_width * cooldown_pct, bar_height)), fill_color)
