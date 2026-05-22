extends CanvasLayer

var title_label: Label
var sub_label: Label

var is_loading: bool = false
var dot_timer: float = 0.0
var dot_count: int = 0
var dot_interval: float = 0.5

func _ready():
	title_label = $VBoxContainer/TitleLabel
	sub_label = $VBoxContainer/SubLabel
	hide()

func _process(delta):
	if not is_loading:
		return
	dot_timer += delta
	if dot_timer >= dot_interval:
		dot_timer = 0.0
		dot_count = (dot_count + 1) % 4
		sub_label.text = "Please wait" + ".".repeat(dot_count)

func show_loading(title: String, auto_hide_seconds: float = 0.0):
	is_loading = true
	title_label.text = title
	sub_label.text = "Please wait"
	dot_count = 0
	dot_timer = 0.0
	show()
	if auto_hide_seconds > 0.0:
		await get_tree().create_timer(auto_hide_seconds).timeout
		hide_loading()

func hide_loading():
	is_loading = false
	hide()
