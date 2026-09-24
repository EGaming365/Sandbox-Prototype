extends Sprite2D

@export var controller_cursor_speed: float = 900.0
@export var trigger_press_threshold: float = 0.5
@export var trigger_release_threshold: float = 0.3
@export var scroll_step: float = 70.0
@export var repeat_delay: float = 0.16

var cooldowns: Array = []
var _virtual_pos: Vector2 = Vector2.ZERO
var _left_wanted: bool = false
var _right_wanted: bool = false
var _left_down: bool = false
var _right_down: bool = false
var _button_mask: int = 0
var _injecting: bool = false
var _repeat_timer: float = 0.0


func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	for action_name in ["click", "right_click"]:
		for action_event in InputMap.action_get_events(action_name):
			if action_event is InputEventJoypadMotion:
				InputMap.action_erase_event(action_name, action_event)
	_virtual_pos = get_viewport().get_mouse_position()
	if _virtual_pos == Vector2.ZERO:
		_virtual_pos = get_viewport().get_visible_rect().size * 0.5


func _input(event):
	if _injecting:
		return
	if event is InputEventJoypadMotion:
		if event.axis == JOY_AXIS_TRIGGER_RIGHT:
			_left_wanted = _trigger_state(_left_wanted, event.axis_value)
		elif event.axis == JOY_AXIS_TRIGGER_LEFT:
			_right_wanted = _trigger_state(_right_wanted, event.axis_value)


func _trigger_state(was_down: bool, value: float) -> bool:
	if was_down:
		return value > trigger_release_threshold
	return value > trigger_press_threshold


func _send_button(button_index: MouseButton, pressed: bool) -> void:
	var mask := MOUSE_BUTTON_MASK_LEFT if button_index == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	if pressed:
		_button_mask |= mask
	else:
		_button_mask &= ~mask
	var click := InputEventMouseButton.new()
	click.button_index = button_index
	click.pressed = pressed
	click.position = _virtual_pos
	click.global_position = click.position
	click.button_mask = _button_mask
	var action_name := "click" if button_index == MOUSE_BUTTON_LEFT else "right_click"
	if pressed:
		Input.action_press(action_name)
	_injecting = true
	get_viewport().push_input(click, true)
	_injecting = false
	if not pressed:
		Input.action_release(action_name)
		call_deferred("_release_button_focus")


func _release_button_focus() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused and not (focused is LineEdit or focused is TextEdit):
		focused.release_focus()


func _dpad_direction(button: JoyButton) -> bool:
	for device in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(device, button):
			return true
	return false


func _nudge_hovered_control(vertical: int, horizontal: int) -> void:
	var hovered := get_viewport().gui_get_hovered_control()
	var node: Node = hovered
	while node:
		if horizontal != 0 and node is Range and not (node is ScrollBar):
			var range_node := node as Range
			var step := maxf(range_node.step, (range_node.max_value - range_node.min_value) * 0.05)
			range_node.value += step * horizontal
			return
		if vertical != 0:
			if node is ScrollContainer:
				(node as ScrollContainer).scroll_vertical += int(scroll_step) * vertical
				return
			if node is ItemList or node is Tree or node is TextEdit or node is RichTextLabel:
				var bar: VScrollBar = node.get_v_scroll_bar()
				bar.value += scroll_step * vertical
				return
		node = node.get_parent()


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
	if _left_wanted != _left_down:
		_left_down = _left_wanted
		_send_button(MOUSE_BUTTON_LEFT, _left_down)
	if _right_wanted != _right_down:
		_right_down = _right_wanted
		_send_button(MOUSE_BUTTON_RIGHT, _right_down)
	var vertical := 0
	var horizontal := 0
	if _dpad_direction(JOY_BUTTON_DPAD_UP):
		vertical -= 1
	if _dpad_direction(JOY_BUTTON_DPAD_DOWN):
		vertical += 1
	if _dpad_direction(JOY_BUTTON_DPAD_LEFT):
		horizontal -= 1
	if _dpad_direction(JOY_BUTTON_DPAD_RIGHT):
		horizontal += 1
	_repeat_timer -= delta
	if (vertical != 0 or horizontal != 0) and _repeat_timer <= 0.0:
		_repeat_timer = repeat_delay
		_nudge_hovered_control(vertical, horizontal)
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
