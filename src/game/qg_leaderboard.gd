## Local leaderboard, ratings and match history, persisted in
## `user://leaderboard.json`.
##
## Registered as the `Leaderboard` autoload.
##
## Steam Leaderboards will replace the *ranking* for shipped builds, but this
## local store stays useful: it is what the player sees before they ever go
## online, and it keeps working offline.
extends Node

const DATA_PATH := "user://leaderboard.json"
const START_RATING := 1200
const K_FACTOR := 32
const HISTORY_LIMIT := 100

var players: Dictionary = {}
var history: Array[Dictionary] = []


func _ready() -> void:
	load_data()


func record_match(names: Dictionary, winner: int, board_size: int, moves: int, mode: String) -> Dictionary:
	var black_name := String(names.get(QGTypes.BLACK, "黑方"))
	var white_name := String(names.get(QGTypes.WHITE, "白方"))
	if black_name == white_name:
		# Hot-seat with the same profile name: keep a stable per-colour label.
		white_name = white_name + "（白）"
	_ensure_player(black_name)
	_ensure_player(white_name)

	var black_rating := int(players[black_name]["rating"])
	var white_rating := int(players[white_name]["rating"])
	var black_score := 0.5
	if winner == QGTypes.WINNER_BLACK:
		black_score = 1.0
	elif winner == QGTypes.WINNER_WHITE:
		black_score = 0.0

	var expected_black := 1.0 / (1.0 + pow(10.0, (white_rating - black_rating) / 400.0))
	var delta := int(round(K_FACTOR * (black_score - expected_black)))

	players[black_name]["rating"] = black_rating + delta
	players[white_name]["rating"] = white_rating - delta
	players[black_name]["games"] = int(players[black_name]["games"]) + 1
	players[white_name]["games"] = int(players[white_name]["games"]) + 1
	if winner == QGTypes.WINNER_BLACK:
		players[black_name]["wins"] = int(players[black_name]["wins"]) + 1
		players[white_name]["losses"] = int(players[white_name]["losses"]) + 1
	elif winner == QGTypes.WINNER_WHITE:
		players[white_name]["wins"] = int(players[white_name]["wins"]) + 1
		players[black_name]["losses"] = int(players[black_name]["losses"]) + 1

	var entry := {
		"black": black_name,
		"white": white_name,
		"winner": winner,
		"board_size": board_size,
		"moves": moves,
		"mode": mode,
		"rating_delta": delta,
		"timestamp": Time.get_unix_time_from_system(),
		"date": Time.get_datetime_string_from_system(false, true),
	}
	history.push_front(entry)
	while history.size() > HISTORY_LIMIT:
		history.pop_back()

	save_data()
	return entry


## Sorted standings, highest rating first.
func standings() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for name in players.keys():
		var row: Dictionary = players[name].duplicate()
		row["name"] = name
		var games := maxi(1, int(row["games"]))
		row["win_rate"] = float(row["wins"]) / float(games)
		rows.append(row)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["rating"]) > int(b["rating"]))
	return rows


func player_row(name: String) -> Dictionary:
	if not players.has(name):
		return {}
	var row: Dictionary = players[name].duplicate()
	row["name"] = name
	return row


func _ensure_player(name: String) -> void:
	if players.has(name):
		return
	players[name] = {
		"rating": START_RATING,
		"wins": 0,
		"losses": 0,
		"games": 0,
	}


func load_data() -> void:
	players.clear()
	history.clear()
	if not FileAccess.file_exists(DATA_PATH):
		return
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var data: Dictionary = parsed
	var stored_players: Dictionary = data.get("players", {})
	for name in stored_players.keys():
		var row: Dictionary = stored_players[name]
		players[String(name)] = {
			"rating": int(row.get("rating", START_RATING)),
			"wins": int(row.get("wins", 0)),
			"losses": int(row.get("losses", 0)),
			"games": int(row.get("games", 0)),
		}
	for item in data.get("history", []):
		if typeof(item) == TYPE_DICTIONARY:
			history.append(item)


func save_data() -> void:
	var file := FileAccess.open(DATA_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"version": 1, "players": players, "history": history}, "\t"))
	file.close()


func reset() -> void:
	players.clear()
	history.clear()
	save_data()
