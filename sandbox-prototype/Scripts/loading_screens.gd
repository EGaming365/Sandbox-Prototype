# Full screen loading overlay with an animated 'Please wait' message.
# Other scripts call show_loading and hide_loading to cover slow operations such as world generation.

extends CanvasLayer

# Label showing the main loading message.
var title_label: Label
# Label showing the animated 'Please wait' text.
var sub_label: Label

# True while the overlay is visible and animating.
var is_loading: bool = false
# Time since the dots last changed.
var dot_timer: float = 0.0
# Number of dots currently shown after the message (0 to 3).
var dot_count: int = 0
# Seconds between each change in the number of dots.
var dot_interval: float = 0.5


# Find the labels and keep the overlay hidden until it is needed.
func _ready():
	title_label = $VBoxContainer/TitleLabel
	sub_label = $VBoxContainer/SubLabel
	hide()


# Animates the trailing dots while loading is in progress.
func _process(delta):
	if not is_loading:
		return
	dot_timer += delta
	if dot_timer >= dot_interval:
		dot_timer = 0.0
		# Cycle the dot count through 0, 1, 2, 3 and back to 0.
		dot_count = (dot_count + 1) % 4
		sub_label.text = "Please wait" + ".".repeat(dot_count)


# Shows the overlay with the given title. If a time is supplied it hides itself afterwards.
func show_loading(title: String, auto_hide_seconds: float = 0.0):
	is_loading = true
	title_label.text = title
	sub_label.text = "Please wait"
	dot_count = 0
	dot_timer = 0.0
	show()
	if auto_hide_seconds > 0.0:
		# Wait for the requested time, then hide the overlay automatically.
		await get_tree().create_timer(auto_hide_seconds).timeout
		hide_loading()


# Stops the animation and hides the overlay.
func hide_loading():
	is_loading = false
	hide()
