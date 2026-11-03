## Screenshot harness for the hidden-phantom / replay work.
##
##   godot --path <project> --script res://tests/ui_board/shots_replay.gd
##
## Writes tmp/screens/hidden_phantoms.png (a match in progress) and
## tmp/screens/replay.png (the replay screen opened from the result panel).
extends SceneTree

const OUT := "res://tmp/screens"

var _shell: Node = null
var _session: QGSession = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_session = root.get_node("Session")
	var packed: PackedScene = load("res://src/ui/shell/main.tscn")
	_shell = packed.instantiate()
	root.add_child(_shell)
	await _frames(4)
	_shell.call("start_local_match")
	await _frames(6)

	_move_for(QGTypes.BLACK, 4 * 9 + 4)
	_move_for(QGTypes.WHITE, 2 * 9 + 2)
	_quantum_for(QGTypes.BLACK, 6 * 9 + 2, 2 * 9 + 6)
	_move_for(QGTypes.WHITE, 7 * 9 + 7)
	_move_for(QGTypes.BLACK, 6 * 9 + 6)
	await _frames(4)
	await _shoot("hidden_phantoms")

	_move_for(QGTypes.WHITE, 3 * 9 + 5)
	_session.submit_resign(QGTypes.BLACK)
	await _frames(6)
	var match_screen = _shell.get("_match_node")
	var replay_button := _find_button(match_screen, "复盘")
	if replay_button != null:
		replay_button.pressed.emit()
		await _frames(8)
		await _shoot("replay")
	quit(0)


func _move_for(colour: int, point: int) -> void:
	for universe_id in _session.game.live_ids():
		var universe = _session.game.get_universe(universe_id)
		if _session.game.turn_of(universe_id) == colour and universe.position.is_empty(point):
			_session.submit_move(universe_id, point)
			return


func _quantum_for(colour: int, point_a: int, point_b: int) -> void:
	for universe_id in _session.game.live_ids():
		var universe = _session.game.get_universe(universe_id)
		if _session.game.turn_of(universe_id) != colour:
			continue
		if universe.position.is_empty(point_a) and universe.position.is_empty(point_b):
			_session.submit_quantum(universe_id, point_a, point_b)
			return


func _frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _shoot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await _frames(2)
	var image := root.get_texture().get_image()
	if image == null:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	image.save_png("%s/%s.png" % [OUT, name])
	print("shot: %s/%s.png" % [OUT, name])


func _find_button(node: Node, text: String) -> Button:
	if node is Button and String((node as Button).text).contains(text):
		return node
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null
