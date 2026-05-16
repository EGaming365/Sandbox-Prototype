extends Control

@onready var weather_icon: TextureRect = $WeatherIcon
@onready var hunger_bar: ProgressBar = $HBoxContainer/HungerBar
@onready var thirst_bar: ProgressBar = $HBoxContainer/ThirstBar
@onready var time_icon: TextureRect = $TimeIcon

var tex_clear = preload("res://Assets/Weather_Clear.png")
var tex_rain = preload("res://Assets/Weather_Rain.png")
var tex_day = preload("res://Assets/Time_Day.png")
var tex_night = preload("res://Assets/Time_Night.png")
var tex_morning = preload("res://Assets/Time_Morning.png")
var tex_evening = preload("res://Assets/Time_Evening.png")

var hunger: float = 100.0
var thirst: float = 100.0
var hunger_drain: float = 0.25
var thirst_drain: float = 0.5
var damage_timer: float = 0.0
var damage_interval: float = 3.0

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
			1, 2, 3:
				weather_icon.texture = tex_rain
		var t = weather_node.time_of_day
		if t >= 0.65 and t < 0.82:
			time_icon.texture = tex_evening
		elif t >= 0.35 and t < 0.65:
			time_icon.texture = tex_day
		elif t>= 0.2 and t< 0.35:
			time_icon.texture = tex_morning
		else:
			time_icon.texture = tex_night

	hunger -= hunger_drain * delta
	thirst -= thirst_drain * delta
	hunger = clamp(hunger, 0.0, 100.0)
	thirst = clamp(thirst, 0.0, 100.0)
	hunger_bar.value = hunger
	thirst_bar.value = thirst

	if hunger <= 0.0 or thirst <= 0.0:
		damage_timer += delta
		if damage_timer >= damage_interval:
			damage_timer = 0.0
			var hotbar = get_tree().root.get_node_or_null("Scene/CanvasLayer/Hotbar")
			if hotbar:
				var player = hotbar.get_local_player()
				if player:
					var prev_health = player.synced_health
					player.take_damage(1)
					if player.synced_health <= 0 or prev_health <= 1:
						var chat = get_tree().root.get_node_or_null("Scene/CanvasLayer/Chat_Box")
						if chat:
							var cause: String
							if hunger <= 0.0 and thirst <= 0.0:
								cause = "homelessness"
							elif thirst <= 0.0:
								cause = "thirst"
							else:
								cause = "hunger"
							var player_name = Steam.getFriendPersonaName(Steam.getSteamID()) if multiplayer.has_multiplayer_peer() else "Player"
							var msg = player_name + " died of " + cause
							if multiplayer.has_multiplayer_peer():
								chat._broadcast_message.rpc(msg)
							else:
								chat._add_message(msg)
	else:
		damage_timer = 0.0
