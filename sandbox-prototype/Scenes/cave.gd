extends Node2D

@export var prompt_offset: Vector2 = Vector2(-80, -90)
@export var prompt_enter: String = "Right-click to enter cave"
@export var prompt_exit: String = "Right-click to exit cave"

var _player_inside: bool = false
var _local_player: CharacterBody2D = null
var _label: Label = null
var _cave_world_gen: Node = null

func _ready():
	var area: Area2D = get_node_or_null("Area2D")
	if area:
		area.body_entered.connect(_on_body_entered)
		area.body_exited.connect(_on_body_exited)
	else:
		push_error("Cave: Area2D child not found")

	_label = Label.new()
	_label.text = prompt_enter
	_label.position = prompt_offset
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.visible = false
	add_child(_label)

	_cave_world_gen = get_tree().root.get_node_or_null("Scene/CaveWorldGen")
	if not _cave_world_gen:
		push_error("Cave: CaveWorldGen not found at Scene/CaveWorldGen")

func _process(_delta):
	if not _player_inside or not _local_player or not _cave_world_gen:
		return

	if Input.is_action_just_pressed("right_click"):
		if _cave_world_gen.in_cave:
			_cave_world_gen.exit_cave(_local_player)
			_label.text = prompt_enter
		else:
			_cave_world_gen.enter_cave(_local_player)
			_label.text = prompt_exit

func _on_body_entered(body: Node):
	if not _is_local_player(body):
		return
	_local_player = body
	_player_inside = true
	if _label:
		_label.text = prompt_exit if (_cave_world_gen and _cave_world_gen.in_cave) else prompt_enter
		_label.visible = true

func _on_body_exited(body: Node):
	if not _is_local_player(body):
		return
	_player_inside = false
	if _label:
		_label.visible = false

func _is_local_player(body: Node) -> bool:
	if not body is CharacterBody2D:
		return false
	if multiplayer.has_multiplayer_peer() and not body.is_multiplayer_authority():
		return false
	return true
