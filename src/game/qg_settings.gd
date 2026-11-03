## Player settings, persisted in `user://settings.cfg`.
##
## Registered as the `Settings` autoload.
extends Node

const CONFIG_PATH := "user://settings.cfg"

var board_size: int = 9
var player_name: String = "玩家"
var server_port: int = 27777
var last_address: String = "127.0.0.1"
var master_volume: float = 0.8
var music_volume: float = 0.7
var music_enabled: bool = true
var show_coordinates: bool = true
var animation_speed: float = 1.0
var last_mode: String = "menu"
## "auto" follows the operating system, otherwise "zh" or "en".
var language: String = "auto"


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return
	board_size = int(config.get_value("game", "board_size", board_size))
	player_name = String(config.get_value("game", "player_name", player_name))
	server_port = int(config.get_value("net", "port", server_port))
	last_address = String(config.get_value("net", "last_address", last_address))
	master_volume = float(config.get_value("audio", "master_volume", master_volume))
	music_volume = float(config.get_value("audio", "music_volume", music_volume))
	music_enabled = bool(config.get_value("audio", "music_enabled", music_enabled))
	show_coordinates = bool(config.get_value("display", "show_coordinates", show_coordinates))
	animation_speed = float(config.get_value("display", "animation_speed", animation_speed))
	last_mode = String(config.get_value("game", "last_mode", last_mode))
	language = String(config.get_value("i18n", "language", language))
	board_size = clampi(board_size, QGGame.MIN_BOARD, QGGame.MAX_BOARD)


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("game", "board_size", board_size)
	config.set_value("game", "player_name", player_name)
	config.set_value("game", "last_mode", last_mode)
	config.set_value("i18n", "language", language)
	config.set_value("net", "port", server_port)
	config.set_value("net", "last_address", last_address)
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("audio", "music_enabled", music_enabled)
	config.set_value("display", "show_coordinates", show_coordinates)
	config.set_value("display", "animation_speed", animation_speed)
	config.save(CONFIG_PATH)
