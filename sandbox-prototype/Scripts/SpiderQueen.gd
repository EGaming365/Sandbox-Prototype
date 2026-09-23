# Spider Queen boss.
# Chases the nearest player and randomly picks an attack: a spread of bullets, summoning eggs, a jump with a shockwave, or a burst of rapid fire.
# Only the host runs the boss's behaviour. Other players receive its position and health from the host.

extends CharacterBody2D

# Master switch that removes the boss immediately when turned off.
const ENABLED := true

# Key used to spawn this boss.
const BOSS_NAME := "spider_queen"
# Name shown above the health bar.
const BOSS_DISPLAY_NAME := "Spider Queen"
# Health the boss starts with.
const MAX_HEALTH := 30
# Walking speed in pixels per second.
const MOVE_SPEED := 60.0
# Damage dealt when the boss touches a player.
const CONTACT_DAMAGE := 2
# Seconds between contact hits.
const CONTACT_COOLDOWN := 0.8
# Distance in pixels at which the boss counts as touching a player.
const CONTACT_RADIUS := 70.0
# Speed at which the boss backs away when the player is too close.
const PUSH_AWAY_FORCE := 200.0
# Distance in pixels the boss tries to keep from the player.
const IDEAL_DISTANCE := 90.0
# Seconds a jump takes.
const JUMP_DURATION := 0.6
# Distance from the landing spot in which the player is knocked back.
const JUMP_LAND_RADIUS := 50.0
# Strength of the knockback when the boss lands.
const KNOCKBACK_FORCE := 400.0
# Bullets in each row of the scatter shot.
const SCATTER_COUNT := 10
# Half angle of the scatter shot in degrees.
const SCATTER_SPREAD_DEG := 70.0
# Speed of scatter shot bullets.
const SCATTER_SPEED := 280.0
# Seconds between the two rows of the scatter shot.
const SCATTER_ROW_DELAY := 0.5
# Number of eggs summoned at once.
const EGG_COUNT := 3
# How far from the boss eggs can land.
const EGG_SCATTER_RADIUS := 80.0
# Bullets fired in a ring when the boss lands.
const LAND_BURST_COUNT := 24
# Speed of the landing ring bullets.
const LAND_BURST_SPEED := 220.0
# Bullets fired in a rapid fire attack.
const RAPID_FIRE_COUNT := 40
# Seconds between rapid fire bullets.
const RAPID_FIRE_INTERVAL := 0.08
# Speed of rapid fire bullets.
const RAPID_FIRE_SPEED := 320.0
# Random spread of rapid fire bullets in degrees.
const RAPID_FIRE_JITTER_DEG := 30.0

# Scene created when eggs are summoned.
const EGG_SCENE := preload("res://Scenes/spider_queen_egg.tscn")
# Enemy that hatches from each egg.
const NIGHT_ENEMY_SCENE := preload("res://Scenes/night_enemy.tscn")

# Picture used to draw the boss, forced to draw_size regardless of its native resolution.
const BOSS_TEXTURE := preload("res://Assets/Spider_Queen.png")

# Width of the boss health bar in pixels.
const BAR_WIDTH: float = 640.0
# Height of the boss health bar in pixels.
const BAR_HEIGHT: float = 32.0

# ID used to keep the boss in sync between players.
@export var enemy_id: int = -1
# Size multiplier for the boss.
@export var boss_visual_scale: float = 3.0
# Size multiplier for the boss's bullets.
@export var bullet_visual_scale: float = 3.0
# Size of the square the boss sprite is drawn into.
@export var draw_size: float = 40.0

# Current health.
var health: int = MAX_HEALTH
# Maximum health, used to fill the health bar.
var max_health: int = MAX_HEALTH
# The player the boss is currently targeting.
var _player: Node2D
# Seconds until the boss can hurt a player by touching them again.
var _contact_cooldown: float = 0.0
# Picture used for the boss's bullets.
var _bullet_texture: Texture2D = preload("res://Assets/Projectile_Basic.png")

# The boss's behaviours: walking around, or one of its four attacks.
enum State { IDLE, SCATTER_SHOT, SUMMON_EGGS, JUMP, RAPID_FIRE }
# The behaviour the boss is currently in.
var _state: State = State.IDLE
# Seconds until the boss picks its next attack.
var _attack_timer: float = 3.0

# Where the jump started.
var _jump_origin: Vector2
# Where the jump will land.
var _jump_target: Vector2
# Seconds since the jump started.
var _jump_timer: float = 0.0
# True while the boss is in the air.
var _is_airborne: bool = false

# Which row of the scatter shot is next. 1 means the second row is waiting.
var _scatter_row: int = 0
# Seconds until the second scatter row fires.
var _scatter_timer: float = 0.0

# Rapid fire bullets still to fire.
var _rapid_fire_remaining: int = 0
# Seconds until the next rapid fire bullet.
var _rapid_fire_timer: float = 0.0

# Container of the health bar on screen.
var _bar_container: Control = null
# The filled part of the health bar.
var _bar_fill: ProgressBar = null
# Label showing the boss's name.
var _bar_label: Label = null

# Emitted when the boss is defeated.
signal boss_died


# Returns true for the host or in a single player game. Only the host controls the boss.
func _is_host() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()


# Returns the closest player to the boss, or null if there are none.
func _find_nearest_player() -> Node2D:
	var nearest: Node2D = null
	var nearest_dist := INF
	for player_node in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(player_node):
			continue
		var player_distance := global_position.distance_to((player_node as Node2D).global_position)
		if player_distance < nearest_dist:
			nearest_dist = player_distance
			nearest = player_node
	return nearest


# Starts the boss at full health, registers it in the bosses group and creates the health bar.
func _ready() -> void:
	if not ENABLED:
		queue_free()
		return
	health = MAX_HEALTH
	max_health = MAX_HEALTH
	scale = Vector2(boss_visual_scale, boss_visual_scale)
	add_to_group("bosses")
	_player = _find_nearest_player()
	_setup_health_bar()


# Finds or builds the health bar on the HUD, shared by every boss, with a name label and a red bar.
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


# Draws the boss as the Spider_Queen sprite, forced into a draw_size square no matter the image's native resolution.
func _draw() -> void:
	var half := draw_size * 0.5
	draw_texture_rect(BOSS_TEXTURE, Rect2(-half, -half, draw_size, draw_size), false)


# Runs the boss each physics frame: updates the health bar, then the host handles movement, damage and attacks.
func _physics_process(delta: float) -> void:
	if not ENABLED:
		return
	_update_health_bar()
	if health <= 0:
		_die()
		return
	if not _is_host():
		return
	_player = _find_nearest_player()
	if not is_instance_valid(_player):
		return
	_contact_cooldown = max(_contact_cooldown - delta, 0.0)
	_check_contact_damage()
	_attack_timer -= delta
	# Carry out the current behaviour.
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
	# Send the boss's position and health to the other players.
	if multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0:
		if is_inside_tree() and get_meta("sync_ready", false):
			var scene_node := get_tree().root.get_node_or_null("Scene")
			if scene_node:
				scene_node.sync_boss_state_rpc.rpc(enemy_id, global_position.x, global_position.y, health)


# Hurts the first player who is touching the boss, then waits for the cooldown.
func _check_contact_damage() -> void:
	var scene_node := get_tree().root.get_node_or_null("Scene")
	for player_node in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(player_node):
			continue
		if global_position.distance_to((player_node as Node2D).global_position) > CONTACT_RADIUS:
			continue
		if _contact_cooldown > 0.0:
			return
		_contact_cooldown = CONTACT_COOLDOWN
		if scene_node and scene_node.has_method("apply_damage_to_player"):
			scene_node.apply_damage_to_player(player_node, CONTACT_DAMAGE, self)
		elif player_node.has_method("defend_enemy_attack"):
			player_node.defend_enemy_attack(CONTACT_DAMAGE, self)
		elif player_node.has_method("take_damage"):
			player_node.take_damage(CONTACT_DAMAGE)
		return


# Walks towards the player, backs away if too close, and slows to a stop at the ideal distance.
func _move_toward_player(delta: float) -> void:
	var to_player := _player.global_position - global_position
	var distance_to_player := to_player.length()
	if distance_to_player < 0.01:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	var direction := to_player / distance_to_player
	if distance_to_player < IDEAL_DISTANCE:
		velocity = -direction * PUSH_AWAY_FORCE
	elif distance_to_player > IDEAL_DISTANCE + 20.0:
		velocity = direction * MOVE_SPEED
	else:
		velocity = velocity.move_toward(Vector2.ZERO, MOVE_SPEED * delta * 10.0)
	move_and_slide()


# Chooses one of the four attacks at random.
func _pick_attack() -> void:
	match randi() % 4:
		0: _do_scatter_shot()
		1: _do_summon_eggs()
		2: _do_jump()
		3: _do_rapid_fire()


# Returns to walking and sets how long to wait before the next attack.
func _set_idle(cooldown: float) -> void:
	_state = State.IDLE
	_attack_timer = cooldown


# Fires a fan of bullets towards the player. The second row is shifted so it fills the gaps in the first.
func _fire_scatter_row(row_offset_fraction: float) -> void:
	var base_angle := global_position.angle_to_point(_player.global_position)
	var spread := deg_to_rad(SCATTER_SPREAD_DEG)
	var step := (spread * 2.0) / float(SCATTER_COUNT - 1)
	var offset := step * 0.5 * row_offset_fraction
	for i in SCATTER_COUNT:
		var angle := base_angle - spread + step * i + offset
		_fire_bullet(angle, SCATTER_SPEED)


# Starts the scatter shot by firing the first row.
func _do_scatter_shot() -> void:
	_state = State.SCATTER_SHOT
	_fire_scatter_row(0.0)
	_scatter_row = 1
	_scatter_timer = SCATTER_ROW_DELAY


# Fires the second row after a short delay and then goes back to walking.
func _tick_scatter(delta: float) -> void:
	if _scatter_row != 1:
		return
	_scatter_timer -= delta
	if _scatter_timer > 0.0:
		return
	_fire_scatter_row(1.0)
	_scatter_row = 0
	_set_idle(2.5)


# Drops eggs around the boss that hatch into enemies.
func _do_summon_eggs() -> void:
	_state = State.SUMMON_EGGS
	for i in EGG_COUNT:
		var offset := Vector2(
			randf_range(-EGG_SCATTER_RADIUS, EGG_SCATTER_RADIUS),
			randf_range(-EGG_SCATTER_RADIUS, EGG_SCATTER_RADIUS),
		)
		var egg := EGG_SCENE.instantiate()
		get_parent().add_child(egg)
		egg.global_position = global_position + offset
		egg.enemy_scene = NIGHT_ENEMY_SCENE
	_set_idle(4.0)


# Starts a jump towards the player's position.
func _do_jump() -> void:
	_state = State.JUMP
	_jump_origin = global_position
	_jump_target = _player.global_position + Vector2(randf_range(-30, 30), randf_range(-30, 30))
	_jump_timer = 0.0
	_is_airborne = true


# Moves the boss along an arc. On landing it fires a ring of bullets and knocks the player back.
func _tick_jump(delta: float) -> void:
	_jump_timer += delta
	var jump_progress := clampf(_jump_timer / JUMP_DURATION, 0.0, 1.0)
	var ground_position := _jump_origin.lerp(_jump_target, jump_progress)
	global_position = ground_position + Vector2(0, -120.0 * sin(jump_progress * PI))
	if jump_progress >= 1.0 and _is_airborne:
		_is_airborne = false
		_land_burst()
		_apply_landing_knockback()
		_set_idle(3.5)


# Pushes the player away if they are close to where the boss landed.
func _apply_landing_knockback() -> void:
	if not is_instance_valid(_player):
		return
	var distance_to_player := global_position.distance_to(_player.global_position)
	if distance_to_player > JUMP_LAND_RADIUS:
		return
	var direction := _player.global_position - global_position
	if direction.length() < 0.01:
		direction = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	direction = direction.normalized()
	if _player.has_method("apply_knockback"):
		_player.apply_knockback(direction, KNOCKBACK_FORCE)
	elif "velocity" in _player:
		_player.velocity = direction * KNOCKBACK_FORCE
	else:
		_player.global_position += direction * (JUMP_LAND_RADIUS - distance_to_player + 20.0)


# Fires bullets in a full circle.
func _land_burst() -> void:
	for i in LAND_BURST_COUNT:
		_fire_bullet((TAU / LAND_BURST_COUNT) * i, LAND_BURST_SPEED)


# Starts the rapid fire attack.
func _do_rapid_fire() -> void:
	_state = State.RAPID_FIRE
	_rapid_fire_remaining = RAPID_FIRE_COUNT
	_rapid_fire_timer = 0.0


# Fires one slightly random bullet each interval until the attack is finished.
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


# Creates a bullet travelling at the given angle and speed.
func _fire_bullet(angle: float, bullet_speed: float, bullet_damage: int = 1) -> void:
	var bullet := BossBullet.new(_bullet_texture, Vector2.from_angle(angle), bullet_speed, bullet_damage, bullet_visual_scale)
	get_parent().add_child(bullet)
	bullet.global_position = global_position


# Sets the health bar to the fraction of health remaining.
func _update_health_bar() -> void:
	if not _bar_fill or not is_instance_valid(_bar_fill):
		return
	if max_health <= 0:
		return
	_bar_fill.value = clampf(float(health) / float(max_health), 0.0, 1.0)


# Reduces the boss's health and starts its death when it reaches zero.
func take_damage(amount: int) -> void:
	if not ENABLED:
		return
	health -= amount
	if health <= 0:
		_die()


# Hides the health bar, announces the boss has died and removes it.
func _die() -> void:
	if _bar_container and is_instance_valid(_bar_container):
		_bar_container.visible = false
	emit_signal("boss_died")
	queue_free()
