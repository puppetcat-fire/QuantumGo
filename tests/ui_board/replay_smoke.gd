## 复盘 (replay) smoke test.
##
## Covers the two halves of the hidden-information change: phantoms are invisible
## while a match is being played, and the replay screen shows them when the match
## is over.
##
##   godot --headless --path <project> --script res://tests/ui_board/replay_smoke.gd
extends SceneTree

var failures: int = 0
var checks: int = 0
var _shell: Node = null
var _session: QGSession = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_session = root.get_node_or_null("Session")
	_check(_session != null, "session autoload present")
	if _session == null:
		_finish()
		return

	print("-- start a local match")
	var packed: PackedScene = load("res://src/ui/shell/main.tscn")
	_shell = packed.instantiate()
	root.add_child(_shell)
	await _frames(4)
	_shell.call("start_local_match")
	await _frames(6)
	_check(_session.game != null, "match started")

	# A normal move, then a quantum split, so the replay has an interesting tree.
	_move_for(QGTypes.BLACK, 4 * 9 + 4)
	_move_for(QGTypes.WHITE, 2 * 9 + 2)
	var split := _quantum_for(QGTypes.BLACK, 6 * 9 + 2, 2 * 9 + 6)
	_check(bool(split.get("ok", false)), "quantum split accepted")

	var match_screen = _shell.get("_match_node")
	_check(match_screen != null, "match screen mounted")
	var any_live: Array[int] = _session.game.live_ids()
	var board_before = match_screen.call("board_for", any_live[0])
	_check(board_before != null, "board widget exists")
	if board_before != null:
		_check(not bool(board_before.get("reveal_phantoms")),
			"phantoms stay hidden during the match")

	print("-- finish the match and open the replay")
	_move_for(QGTypes.WHITE, 7 * 9 + 7)
	_session.submit_resign(QGTypes.BLACK)
	await _frames(6)
	_check(_session.game.is_over(), "resigning ends the match")
	_check(_session.history_size() >= 5, "the session recorded snapshots")

	var replay_button := _find_button(match_screen, "复盘")
	_check(replay_button != null, "the result panel offers 复盘")
	if replay_button == null:
		_finish()
		return
	replay_button.pressed.emit()
	await _frames(8)

	_check(String(_shell.call("current_screen")) == "replay", "the replay screen is shown")
	var replay = _shell.call("screen", "replay")
	_check(replay != null, "replay screen is routed")
	if replay == null:
		_finish()
		return
	_check(int(replay.call("step_count")) == _session.history_size(), "every snapshot reached the replay")
	_check(int(replay.call("current_index")) == int(replay.call("step_count")) - 1,
		"the replay opens on the final position")

	var game: QGGame = replay.call("current_game")
	_check(game != null, "the replay rebuilds a game from the snapshot")
	if game == null:
		_finish()
		return
	var live: Array[int] = game.live_ids()
	_check(live.size() >= 1, "the final position has a live universe")
	var replay_board = replay.call("board_for", live[0])
	_check(replay_board != null, "the replay draws boards")
	if replay_board != null:
		_check(bool(replay_board.get("reveal_phantoms")), "the replay reveals phantom stones")

	print("-- step backwards")
	var before_index := int(replay.call("current_index"))
	var prev_button := _find_button(replay, "◀ 上一步")
	_check(prev_button != null, "the replay has a previous button")
	if prev_button != null:
		prev_button.pressed.emit()
		await _frames(3)
		_check(int(replay.call("current_index")) == before_index - 1, "previous step moves the replay back")
		# The last recorded step is the resignation, which does not change the move
		# count, so compare the phase instead.
		var earlier: QGGame = replay.call("current_game")
		_check(earlier != null and not earlier.is_over(), "the earlier position is the pre-resign one")

	_finish()


func _move_for(colour: int, point: int) -> void:
	for universe_id in _session.game.live_ids():
		var universe = _session.game.get_universe(universe_id)
		if _session.game.turn_of(universe_id) == colour and universe.position.is_empty(point):
			_session.submit_move(universe_id, point)
			return


func _quantum_for(colour: int, point_a: int, point_b: int) -> Dictionary:
	for universe_id in _session.game.live_ids():
		var universe = _session.game.get_universe(universe_id)
		if _session.game.turn_of(universe_id) != colour:
			continue
		if universe.position.is_empty(point_a) and universe.position.is_empty(point_b):
			return _session.submit_quantum(universe_id, point_a, point_b)
	return {"ok": false}


func _frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _find_button(node: Node, text: String) -> Button:
	if node is Button and String((node as Button).text).contains(text):
		return node
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func _check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("   PASS %s" % message)
	else:
		failures += 1
		print("   FAIL %s" % message)


func _finish() -> void:
	print("")
	if failures == 0:
		print("REPLAY PASS (%d checks)" % checks)
		quit(0)
	else:
		print("REPLAY FAIL (%d of %d checks)" % [failures, checks])
		quit(1)
