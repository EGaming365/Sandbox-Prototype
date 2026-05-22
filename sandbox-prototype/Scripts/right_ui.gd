extends Control
@onready var weather_icon: TextureRect = $WeatherIcon
@onready var hunger_bar: ProgressBar = $HBoxContainer/HungerBar
@onready var thirst_bar: ProgressBar = $HBoxContainer/ThirstBar
@onready var time_icon: TextureRect = $TimeIcon
@onready var disastor_icon: TextureRect = $DisastorIcon
var tex_clear = preload("res://Assets/Weather_Clear.png")
var tex_rain = preload("res://Assets/Weather_Rain.png")
var tex_thunder = preload("res://Assets/Weather_Thunder.png")
var tex_thunderstorm = preload("res://Assets/Weather_Thunderstorm.png")
var tex_day = preload("res://Assets/Time_Day.png")
var tex_night = preload("res://Assets/Time_Night.png")
var tex_morning = preload("res://Assets/Time_Morning.png")
var tex_evening = preload("res://Assets/Time_Evening.png")
var hunger: float = 100.0
var thirst: float = 100.0
var hunger_drain: float = 0.2
var thirst_drain: float = 0.25
var damage_timer: float = 0.0
var damage_interval: float = 3.0
var thirst_refill_rate: float = 18.0
var death_message_sent: bool = false
var regen_interval: float = 5.0
var regen_amount: int = 1
var regen_hunger_min: float = 30.0
var regen_thirst_min: float = 20.0
var regen_timer: float = 0.0
var regen_max_health: float = 10.0
var idle_drain_multiplier: float = 0.1
var healing_drain_multiplier: float = 10.0

func _ready():
	hunger_bar.max_value = 100
	hunger_bar.value = 100
	thirst_bar.max_value = 100
	thirst_bar.value = 100

func _process(delta):
	var weather_node = get_tree().root.get_node_or_null("Scene/Weather")
	if weather_node:
		match weather_node.current_weather:
			0:
				weather_icon.texture = tex_clear
			1:
				weather_icon.texture = tex_rain
			2:
				weather_icon.texture = tex_thunder
			3:
				weather_icon.texture = tex_thunderstorm
		var t = weather_node.time_of_day
		if t >= 0.65 and t < 0.82:
			time_icon.texture = tex_evening
		elif t >= 0.35 and t < 0.65:
			time_icon.texture = tex_day
		elif t >= 0.2 and t < 0.35:
			time_icon.texture = tex_morning
		else:
			time_icon.texture = tex_night

	var world_gen = get_tree().root.get_node_or_null("Scene/WorldGen")
	var in_water = false
	var player: CharacterBody2D = null
	for p in get_tree().get_nodes_in_group("players"):
		if p is CharacterBody2D:
			if not multiplayer.has_multiplayer_peer() or p.is_multiplayer_authority():
				player = p
				break

	if player and world_gen and world_gen.has_method("is_water_at"):
		in_water = world_gen.is_water_at(player.global_position)

	var is_moving = player != null and player.velocity.length() > 0
	var is_healing = player != null and hunger >= regen_hunger_min and thirst >= regen_thirst_min and player.synced_health < player.max_health

	var drain_multiplier: float
	if is_healing:
		drain_multiplier = healing_drain_multiplier
	elif is_moving:
		drain_multiplier = 1.0
	else:
		drain_multiplier = idle_drain_multiplier

	hunger -= hunger_drain * drain_multiplier * delta
	if in_water:
		thirst += thirst_refill_rate * delta
	else:
		thirst -= thirst_drain * drain_multiplier * delta
	hunger = clamp(hunger, 0.0, 100.0)
	thirst = clamp(thirst, 0.0, 100.0)

	if is_instance_valid(hunger_bar):
		hunger_bar.value = hunger
	if is_instance_valid(thirst_bar):
		thirst_bar.value = thirst

	if hunger >= regen_hunger_min and thirst >= regen_thirst_min:
		regen_timer += delta
		if regen_timer >= regen_interval:
			regen_timer = 0.0
			if player:
				player.heal(regen_amount)
	else:
		regen_timer = 0.0

	if hunger > 0.0 and thirst > 0.0:
		damage_timer = 0.0
		death_message_sent = false
		return

	if player == null:
		return

	damage_timer += delta
	if damage_timer < damage_interval:
		return

	damage_timer = 0.0
	var death_cause := ""
	if hunger <= 0.0 and thirst <= 0.0:
		death_cause = "hunger and thirst"
	elif thirst <= 0.0:
		death_cause = "thirst"
	else:
		death_cause = "hunger"

	var prev_health = player.synced_health
	player.take_damage(1)
	if not death_message_sent and (player.synced_health <= 0 or prev_health <= 1):
		death_message_sent = true
		_send_death_message(death_cause)

func _send_death_message(cause: String):
	var chat = get_tree().root.get_node_or_null("Scene/CanvasLayer/Chat_Box")
	if not chat:
		return
	var player_name = Steam.getFriendPersonaName(Steam.getSteamID()) if (multiplayer.has_multiplayer_peer() and Steam != null) else "Player"
	var msg = player_name + " died of " + cause
	if multiplayer.has_multiplayer_peer():
		chat._broadcast_message.rpc(msg)
	else:
		chat._add_message(msg)

func reset_stats():
	hunger = 100.0
	thirst = 100.0
	hunger_bar.value = 100.0
	thirst_bar.value = 100.0
