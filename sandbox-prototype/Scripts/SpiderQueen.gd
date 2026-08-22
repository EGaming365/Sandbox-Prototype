extends CharacterBody2D

const ENABLED := true

const BOSS_NAME := "spider_queen"
const BOSS_DISPLAY_NAME := "Spider Queen"
const MAX_HEALTH := 30
const MOVE_SPEED := 60.0
const CONTACT_DAMAGE := 2
const CONTACT_COOLDOWN := 0.8
const CONTACT_RADIUS := 70.0
const PUSH_AWAY_FORCE := 200.0
const IDEAL_DISTANCE := 90.0
const JUMP_DURATION := 0.6
const JUMP_LAND_RADIUS := 50.0
const KNOCKBACK_FORCE := 400.0
const SCATTER_COUNT := 10
const SCATTER_SPREAD_DEG := 70.0
const SCATTER_SPEED := 280.0
const SCATTER_ROW_DELAY := 0.5
const EGG_COUNT := 3
const EGG_SCATTER_RADIUS := 80.0
const LAND_BURST_COUNT := 24
const LAND_BURST_SPEED := 220.0
const RAPID_FIRE_COUNT := 40
const RAPID_FIRE_INTERVAL := 0.08
const RAPID_FIRE_SPEED := 320.0
const RAPID_FIRE_JITTER_DEG := 30.0

const EGG_SCENE := preload("res://Scenes/spider_queen_egg.tscn")
const NIGHT_ENEMY_SCENE := preload("res://Scenes/night_enemy.tscn")

const BAR_WIDTH: float = 640.0
const BAR_HEIGHT: float = 32.0

@export var enemy_id: int = -1
@export var boss_visual_scale: float = 3.0
@export var bullet_visual_scale: float = 3.0
@export var draw_size: float = 40.0

var health: int = MAX_HEALTH
var max_health: int = MAX_HEALTH
var _player: Node2D
var _contact_cooldown: float = 0.0
var _bullet_texture: Texture2D = preload("res://Assets/Projectile_Basic.png")

enum State { IDLE, SCATTER_SHOT, SUMMON_EGGS, JUMP, RAPID_FIRE }
var _state: State = State.IDLE
var _attack_timer: float = 3.0

var _jump_origin: Vector2
var _jump_target: Vector2
var _jump_timer: float = 0.0
var _is_airborne: bool = false

var _scatter_row: int = 0
var _scatter_timer: float = 0.0

var _rapid_fire_remaining: int = 0
var _rapid_fire_timer: float = 0.0

var _bar_container: Control = null
var _bar_fill: ProgressBar = null
var _bar_label: Label = null

signal boss_died

func _is_host() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()

func _ready() -> void:
	if not ENABLED:
		queue_free()
		return
	health = MAX_HEALTH
	max_health = MAX_HEALTH
	scale = Vector2(boss_visual_scale, boss_visual_scale)
	add_to_group("bosses")
	_player = get_tree().get_first_node_in_group("players")
	_setup_health_bar()

func _setup_health_bar() -> void:
	var canvas := get_tree().root.get_node_or_null("Scene/CanvasLayer")
	if not canvas:
		return
	var container: Control = canvas.get_node_or_null("BossHealthBar")
	if not container:
		container = Control.new()
		container.name = "BossHealthBar"
		container.set_anchors_preset(Control.PRESET_TOP_WIDE)
		container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		canvas.add_child(container)

		var layout := VBoxContainer.new()
		layout.name = "Layout"
		layout.anchor_left = 0.5
		layout.anchor_right = 0.5
		layout.offset_left = -BAR_WIDTH / 2.0
		layout.offset_right = BAR_WIDTH / 2.0
		layout.offset_top = 24.0
		layout.alignment = BoxContainer.ALIGNMENT_CENTER
		layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(layout)

		var label := Label.new()
		label.name = "NameLabel"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 30)
		label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		label.add_theme_constant_override("outline_size", 5)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layout.add_child(label)

		var fill := ProgressBar.new()
		fill.name = "Bar"
		fill.custom_minimum_size = Vector2(BAR_WIDTH, BAR_HEIGHT)
		fill.min_value = 0.0
		fill.max_value = 1.0
		fill.value = 1.0
		fill.show_percentage = false
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bg_style := StyleBoxFlat.new()
		bg_style.bg_color = Color(0.05, 0.05, 0.05, 0.85)
		bg_style.set_border_width_all(3)
		bg_style.border_color = Color(0, 0, 0, 1)
		fill.add_theme_stylebox_override("background", bg_style)
		var fill_style := StyleBoxFlat.new()
		fill_style.bg_color = Color(0.75, 0.05, 0.1, 1.0)
		fill.add_theme_stylebox_override("fill", fill_style)
		layout.add_child(fill)

	var layout_node: Control = container.get_node_or_null("Layout")
	_bar_container = container
	_bar_label = layout_node.get_node_or_null("NameLabel") if layout_node else null
	_bar_fill = layout_node.get_node_or_null("Bar") if layout_node else null
	if _bar_label:
		_bar_label.text = BOSS_DISPLAY_NAME
	if _bar_fill:
		_bar_fill.value = 1.0
	_bar_container.visible = true

func _draw() -> void:
	var half := draw_size * 0.5
	draw_rect(Rect2(-half, -half, draw_size, draw_size), Color.WHITE)

func _physics_process(delta: float) -> void:
	if not ENABLED:
		return
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("players")
		return
	_contact_cooldown = max(_contact_cooldown - delta, 0.0)
	_check_contact_damage()
	_update_health_bar()
	if health <= 0:
		_die()
		return
	if not _is_host():
		return
	_attack_timer -= delta
	match _state:
		State.IDLE:
			_move_toward_player(delta)
			if _attack_timer <= 0.0:
				_pick_attack()
		State.SCATTER_SHOT:
			_tick_scatter(delta)
		State.SUMMON_EGGS:
			pass
		State.JUMP:
			_tick_jump(delta)
		State.RAPID_FIRE:
			_tick_rapid_fire(delta)
	if multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0:
		if is_inside_tree() and get_meta("sync_ready", false):
			var scene_node := get_tree().root.get_node_or_null("Scene")
			if scene_node:
				scene_node.sync_boss_state_rpc.rpc(enemy_id, global_position.x, global_position.y, health)

func _check_contact_damage() -> void:
	if _contact_cooldown > 0.0:
		return
	if global_position.distance_to(_player.global_position) > CONTACT_RADIUS:
		return
	_contact_cooldown = CONTACT_COOLDOWN
	var scene_node := get_tree().root.get_node_or_null("Scene")
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		if scene_node:
			scene_node.request_deal_damage.rpc_id(1, _player.name.to_int(), CONTACT_DAMAGE)
	else:
		if _player.has_method("defend_enemy_attack"):
			_player.defend_enemy_attack(CONTACT_DAMAGE, null)
		elif _player.has_method("take_damage"):
			_player.take_damage(CONTACT_DAMAGE)

func _move_toward_player(delta: float) -> void:
	var to_player := _player.global_position - global_position
	var dist := to_player.length()
	if dist < 0.01:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	var dir := to_player / dist
	if dist < IDEAL_DISTANCE:
		velocity = -dir * PUSH_AWAY_FORCE
	elif dist > IDEAL_DISTANCE + 20.0:
		velocity = dir * MOVE_SPEED
	else:
		velocity = velocity.move_toward(Vector2.ZERO, MOVE_SPEED * delta * 10.0)
	move_and_slide()

func _pick_attack() -> void:
	match randi() % 4:
		0: _do_scatter_shot()
		1: _do_summon_eggs()
		2: _do_jump()
		3: _do_rapid_fire()

func _set_idle(cooldown: float) -> void:
	_state = State.IDLE
	_attack_timer = cooldown

func _fire_scatter_row(row_offset_fraction: float) -> void:
	var base_angle := global_position.angle_to_point(_player.global_position)
	var spread := deg_to_rad(SCATTER_SPREAD_DEG)
	var step := (spread * 2.0) / float(SCATTER_COUNT - 1)
	var offset := step * 0.5 * row_offset_fraction
	for i in SCATTER_COUNT:
		var angle := base_angle - spread + step * i + offset
		_fire_bullet(angle, SCATTER_SPEED)

func _do_scatter_shot() -> void:
	_state = State.SCATTER_SHOT
	_fire_scatter_row(0.0)
	_scatter_row = 1
	_scatter_timer = SCATTER_ROW_DELAY

func _tick_scatter(delta: float) -> void:
	if _scatter_row != 1:
		return
	_scatter_timer -= delta
	if _scatter_timer > 0.0:
		return
	_fire_scatter_row(1.0)
	_scatter_row = 0
	_set_idle(2.5)

func _do_summon_eggs() -> void:
	_state = State.SUMMON_EGGS
	for i in EGG_COUNT:
		var offset := Vector2(randf_range(-EGG_SCATTER_RADIUS, EGG_SCATTER_RADIUS), randf_range(-EGG_SCATTER_RADIUS, EGG_SCATTER_RADIUS))
		var egg := EGG_SCENE.instantiate()
		get_parent().add_child(egg)
		egg.global_position = global_position + offset
		egg.enemy_scene = NIGHT_ENEMY_SCENE
	_set_idle(4.0)

func _do_jump() -> void:
	_state = State.JUMP
	_jump_origin = global_position
	_jump_target = _player.global_position + Vector2(randf_range(-30, 30), randf_range(-30, 30))
	_jump_timer = 0.0
	_is_airborne = true

func _tick_jump(delta: float) -> void:
	_jump_timer += delta
	var t := clampf(_jump_timer / JUMP_DURATION, 0.0, 1.0)
	var flat := _jump_origin.lerp(_jump_target, t)
	global_position = flat + Vector2(0, -120.0 * sin(t * PI))
	if t >= 1.0 and _is_airborne:
		_is_airborne = false
		_land_burst()
		_apply_landing_knockback()
		_set_idle(3.5)

func _apply_landing_knockback() -> void:
	if not is_instance_valid(_player):
		return
	var dist := global_position.distance_to(_player.global_position)
	if dist > JUMP_LAND_RADIUS:
		return
	var dir := _player.global_position - global_position
	if dir.length() < 0.01:
		dir = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	dir = dir.normalized()
	if _player.has_method("apply_knockback"):
		_player.apply_knockback(dir, KNOCKBACK_FORCE)
	elif "velocity" in _player:
		_player.velocity = dir * KNOCKBACK_FORCE
	else:
		_player.global_position += dir * (JUMP_LAND_RADIUS - dist + 20.0)

func _land_burst() -> void:
	for i in LAND_BURST_COUNT:
		_fire_bullet((TAU / LAND_BURST_COUNT) * i, LAND_BURST_SPEED)

func _do_rapid_fire() -> void:
	_state = State.RAPID_FIRE
	_rapid_fire_remaining = RAPID_FIRE_COUNT
	_rapid_fire_timer = 0.0

func _tick_rapid_fire(delta: float) -> void:
	_rapid_fire_timer -= delta
	if _rapid_fire_timer > 0.0:
		return
	if _rapid_fire_remaining <= 0:
		_set_idle(2.0)
		return
	var base_angle := global_position.angle_to_point(_player.global_position)
	var jitter := deg_to_rad(RAPID_FIRE_JITTER_DEG)
	_fire_bullet(base_angle + randf_range(-jitter, jitter), RAPID_FIRE_SPEED)
	_rapid_fire_remaining -= 1
	_rapid_fire_timer = RAPID_FIRE_INTERVAL

func _fire_bullet(angle: float, spd: float, dmg: int = 1) -> void:
	var b := BossBullet.new(_bullet_texture, Vector2.from_angle(angle), spd, dmg, bullet_visual_scale)
	get_parent().add_child(b)
	b.global_position = global_position

func _update_health_bar() -> void:
	if not _bar_fill or not is_instance_valid(_bar_fill):
		return
	if max_health <= 0:
		return
	_bar_fill.value = clampf(float(health) / float(max_health), 0.0, 1.0)

func take_damage(amount: int) -> void:
	if not ENABLED:
		return
	health -= amount
	if health <= 0:
		_die()

func _die() -> void:
	if _bar_container and is_instance_valid(_bar_container):
		_bar_container.visible = false
	emit_signal("boss_died")
	queue_free()
