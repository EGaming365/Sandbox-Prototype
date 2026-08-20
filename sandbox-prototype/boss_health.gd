extends Control

var _panel: PanelContainer
var _name_label: Label
var _bar_bg: ColorRect
var _bar_fill: ColorRect
var _current_boss: Node = null

const BAR_WIDTH: float = 360.0
const BAR_HEIGHT: float = 22.0

func _ready() -> void:
	top_level = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	visible = false

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	_panel.add_child(box)
	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 20)
	_name_label.add_theme_color_override("font_color", Color.WHITE)
	_name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_name_label.add_theme_constant_override("outline_size", 4)
	box.add_child(_name_label)
	var bar_holder := Control.new()
	bar_holder.custom_minimum_size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	bar_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(bar_holder)
	_bar_bg = ColorRect.new()
	_bar_bg.color = Color(0.1, 0.1, 0.1, 0.85)
	_bar_bg.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_holder.add_child(_bar_bg)
	_bar_fill = ColorRect.new()
	_bar_fill.color = Color(0.75, 0.1, 0.15, 1.0)
	_bar_fill.size = Vector2(BAR_WIDTH - 4.0, BAR_HEIGHT - 4.0)
	_bar_fill.position = Vector2(2, 2)
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_holder.add_child(_bar_fill)

func _process(_delta: float) -> void:
	if not _current_boss or not is_instance_valid(_current_boss):
		_current_boss = _find_active_boss()
		if not _current_boss:
			visible = false
			return
		_name_label.text = _display_name_for(_current_boss)
		visible = true
	_update_position()
	_update_health()

func _find_active_boss() -> Node:
	for b in get_tree().get_nodes_in_group("bosses"):
		if is_instance_valid(b):
			return b
	return null

func _display_name_for(boss: Node) -> String:
	var raw: Variant = boss.get("BOSS_NAME")
	if raw == null:
		return str(boss.name)
	return str(raw).replace("_", " ").capitalize()

func _update_position() -> void:
	var vp_size := get_viewport_rect().size
	global_position = Vector2((vp_size.x - BAR_WIDTH) * 0.5, 24.0)

func _update_health() -> void:
	var health_val: Variant = _current_boss.get("health")
	var max_val: Variant = _current_boss.get("MAX_HEALTH")
	if health_val == null or max_val == null or float(max_val) <= 0.0:
		return
	var ratio: float = clampf(float(health_val) / float(max_val), 0.0, 1.0)
	_bar_fill.size = Vector2((BAR_WIDTH - 4.0) * ratio, BAR_HEIGHT - 4.0)
