## Windowed screenshot harness for the shell screens.
##
## Run (needs a real display, not headless):
##   godot --path <project> --script res://tests/ui_shell/shots.gd
##
## Writes one PNG per screen into `res://tmp/screens/`. Demo leaderboard data is
## seeded in memory only and never saved, so a screenshot run cannot pollute the
## player's real profile.
extends SceneTree

const SHELL_SCENE := "res://src/ui/shell/main.tscn"
const OUT_DIR := "res://tmp/screens"
const SETTLE_FRAMES := 6

var shell: Node = null
var _leaderboard: Node = null
var _settings: Node = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_leaderboard = root.get_node_or_null("Leaderboard")
	_settings = root.get_node_or_null("Settings")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var packed: PackedScene = load(SHELL_SCENE)
	if packed == null:
		printerr("shots: cannot load ", SHELL_SCENE)
		quit(2)
		return

	# A believable profile so the screens look like a shipped game. This is set
	# before the shell exists: the menu reads the profile when it is first shown,
	# and nothing is written back to disk.
	if _settings != null:
		_settings.set("player_name", "小满")
		_settings.set("board_size", 9)
		_settings.set("server_port", 27777)
		_settings.set("last_address", "")
		_settings.set("master_volume", 0.8)
		_settings.set("animation_speed", 1.0)
		_settings.set("show_coordinates", true)
		_settings.set("show_phantom", true)

	shell = packed.instantiate()
	root.add_child(shell)
	await _settle()

	await _shot("menu")

	shell.show_screen("lobby")
	await _settle()
	await _shot("lobby")

	# Hosting state: a real room on a high port, filled with a real address list.
	var hosted: Dictionary = {}
	if root.get_node_or_null("Session") != null:
		hosted = root.get_node("Session").call("host_match", 9, "小满", 27777)
		await _settle()
		if bool(hosted.get("ok", false)):
			await _shot("lobby_hosting")
		else:
			printerr("shots: host_match failed: ", hosted)
		root.get_node("Session").call("leave")

	_seed_leaderboard()
	shell.show_screen("leaderboard")
	await _settle()
	await _shot("leaderboard")

	shell.show_screen("rules")
	await _settle()
	await _shot("rules")

	shell.show_screen("settings")
	await _settle()
	await _shot("settings")

	# Result dialog on its own, over the menu backdrop.
	shell.show_screen("menu")
	await _settle()
	var result_script: GDScript = load("res://src/ui/shell/result_view.gd")
	var view: Control = result_script.new()
	view.call("setup",
		{"winner": QGTypes.WINNER_BLACK, "black": 312, "white": 268,
			"universes": [{"id": 0}, {"id": 1}, {"id": 2}], "moves": 87, "board_size": 9},
		{QGTypes.BLACK: "小满", QGTypes.WHITE: "半目"}, {"rating_delta": 16})
	# Mount it under the shell's overlay so it inherits the shared theme, exactly
	# as the running game does.
	var overlay: Node = shell.get_node("Overlay")
	overlay.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await _settle()
	await _shot("result")
	overlay.remove_child(view)
	view.queue_free()

	print("shots: done")
	quit(0)


func _settle() -> void:
	for _frame in range(SETTLE_FRAMES):
		await process_frame


func _shot(name: String) -> void:
	await _settle()
	var image := root.get_texture().get_image()
	if image == null:
		printerr("shots: no framebuffer for ", name)
		return
	var path := "%s/%s.png" % [OUT_DIR, name]
	var code := image.save_png(path)
	print("shots: %s -> %s (%s) code=%d" % [name, path, str(image.get_size()), code])


func _seed_leaderboard() -> void:
	if _leaderboard == null:
		return
	_leaderboard.set("players", {
		"青木": {"rating": 1287, "wins": 7, "losses": 3, "games": 10},
		"半目": {"rating": 1243, "wins": 5, "losses": 2, "games": 7},
		"小满": {"rating": 1216, "wins": 3, "losses": 1, "games": 4},
		"星位": {"rating": 1188, "wins": 4, "losses": 5, "games": 9},
		"劫争": {"rating": 1152, "wins": 2, "losses": 4, "games": 6},
	})
	var history: Array = _leaderboard.get("history")
	history.clear()
	history.append({
		"black": "小满", "white": "半目", "winner": 1, "board_size": 9,
		"moves": 87, "mode": "local", "rating_delta": 16,
		"timestamp": 0, "date": "2026-11-01 14:12:00",
	})
	history.append({
		"black": "星位", "white": "小满", "winner": 2, "board_size": 9,
		"moves": 64, "mode": "online", "rating_delta": -11,
		"timestamp": 0, "date": "2026-11-01 13:40:00",
	})
	history.append({
		"black": "青木", "white": "劫争", "winner": 1, "board_size": 13,
		"moves": 121, "mode": "local", "rating_delta": 9,
		"timestamp": 0, "date": "2026-10-31 22:05:00",
	})
	history.append({
		"black": "半目", "white": "青木", "winner": 2, "board_size": 9,
		"moves": 58, "mode": "local", "rating_delta": -7,
		"timestamp": 0, "date": "2026-10-31 21:30:00",
	})
