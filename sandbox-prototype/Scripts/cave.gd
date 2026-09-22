# Cave entrance.
# Shows a prompt when the local player stands at the entrance and lets them enter or leave the cave world with the right mouse button.

extends Node2D

# Position of the prompt text relative to the cave entrance.
@export var prompt_offset: Vector2 = Vector2(-80, -40)
# Text shown when the player can enter the cave.
@export var prompt_enter: String = "Right-click to enter cave"
# Text shown when the player can leave the cave.
@export var prompt_exit: String = "Right-click to exit cave"

# True while the local player is standing inside the entrance area.
var _player_inside: bool = false
# The local player currently inside the entrance area.
var _local_player: CharacterBody2D = null
# Label that displays the enter or exit prompt.
var _label: Label = null
# The cave generator that performs the actual entering and leaving.
var _cave_world_gen: Node = null


# Connects the entrance area to this script and creates the hidden prompt label.
func _ready():
	z_index = 2
	# The Area2D detects when a player walks into the entrance.
	var area: Area2D = get_node_or_null("Area2D")
	if area:
		area.body_entered.connect(_on_body_entered)
		area.body_exited.connect(_on_body_exited)
	else:
		push_error("Cave: Area2D child not found")
	# Create the prompt label, hidden until a player is nearby.
	_label = Label.new()
	_label.text = prompt_enter
	_label.position = prompt_offset
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.visible = false
	add_child(_label)
	# Find the cave generator so it can be used later.
	_cave_world_gen = get_tree().root.get_node_or_null("Scene/CaveWorldGen")
	if not _cave_world_gen:
		push_error("Cave: CaveWorldGen not found at Scene/CaveWorldGen")


# Waits for a right click while the player is inside the entrance area.
func _process(_delta):
	if not _player_inside or not _local_player or not _cave_world_gen:
		return
	# Ignore clicks while the cave is still on its enter cooldown.
	if _cave_world_gen.get("_enter_cooldown") != null and _cave_world_gen._enter_cooldown > 0.0:
		return
	# Leave the cave if already inside, otherwise enter it, and update the prompt to match.
	if Input.is_action_just_pressed("right_click"):
		if _cave_world_gen.in_cave:
			_cave_world_gen.exit_cave(_local_player)
			_label.text = prompt_enter
		else:
			_cave_world_gen.enter_cave(_local_player)
			_label.text = prompt_exit


# Shows the prompt when the local player walks into the entrance area.
func _on_body_entered(body: Node):
	if not _is_local_player(body):
		return
	_local_player = body
	_player_inside = true
	if _label:
		# Show the exit text when already in the cave, otherwise the enter text.
		_label.text = prompt_exit if (_cave_world_gen and _cave_world_gen.in_cave) else prompt_enter
		_label.visible = true


# Hides the prompt when the local player walks away.
func _on_body_exited(body: Node):
	if not _is_local_player(body):
		return
	_player_inside = false
	if _label:
		_label.visible = false


# Returns true only for the player controlled by this game instance, so other players do not trigger the prompt.
func _is_local_player(body: Node) -> bool:
	if not body is CharacterBody2D:
		return false
	if multiplayer.has_multiplayer_peer() and not body.is_multiplayer_authority():
		return false
	return true
