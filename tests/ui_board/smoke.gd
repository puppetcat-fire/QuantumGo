## Headless smoke test for the match screen (task-2).
##
## Usage:
##   godot --headless --path <project> --script res://tests/ui_board/smoke.gd
##
## It starts a LOCAL session, instantiates res://src/ui/match/match.tscn, drives
## the real click path (board.activate_point -> match -> Session.submit_*) and
## asserts the visible state. Exits 0 when every check passes, 1 otherwise.
extends SceneTree

const MATCH_SCENE := "res://src/ui/match/match.tscn"
const REQUIRED_SIGNALS := ["exit_requested", "rematch_requested"]

var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var session = root.get_node_or_null("Session")
	_check(session != null, "Session autoload is available")
	if session == null:
		_finish()
		return
	var sfx = root.get_node_or_null("Sfx")
	_check(sfx != null, "Sfx autoload is available")
	if sfx != null:
		_check(sfx.has_clip("stone_black") and sfx.has_clip("split"), "Sfx has the match sound clips")
		for method_name in ["play_stone", "play_split", "play_collapse", "play_pass", "play_click", "play_result"]:
			_check(sfx.has_method(method_name), "Sfx exposes %s" % method_name)

	session.start_local(9)
	await _frames(1)

	var packed: PackedScene = load(MATCH_SCENE)
	_check(packed != null, "match.tscn loads")
	if packed == null:
		_finish()
		return
	var screen = packed.instantiate()
	_check(screen != null, "match.tscn instantiates")
	if screen == null:
		_finish()
		return
	root.add_child(screen)
	await _frames(3)

	for signal_name in REQUIRED_SIGNALS:
		_check(screen.has_signal(signal_name), "match screen exports signal '%s'" % signal_name)

	# --- initial render ----------------------------------------------------
	_check(screen.card_count() == 1, "one universe card for the root universe (got %d)" % screen.card_count())
	_check(session.game.live_ids() == [0], "engine has exactly one universe")
	var board = screen.board_for(0)
	_check(board != null, "board widget exists for universe 0")
	if board == null:
		_finish()
		return

	# --- normal move through the board click path --------------------------
	board.activate_point(4 * 9 + 4)
	await _frames(2)
	_check(session.game.move_count == 1, "clicking a point submits exactly one move")
	_check(
		int(session.game.get_universe(0).position.cells[4 * 9 + 4]) == QGTypes.BLACK,
		"the stone placed by the click is black"
	)
	_check(screen.focused_universe() == 0, "clicking a board focuses its universe")

	# --- LOCAL undo --------------------------------------------------------
	_check(session.mode == QGSession.Mode.LOCAL, "session is in LOCAL mode")
	screen.request_undo()
	await _frames(2)
	_check(session.game.move_count == 0, "U / 悔棋 undoes the last move in LOCAL mode")
	_check(not session.game.can_undo(), "undo stack is empty after the undo")

	# --- quantum move: A marker, Esc cancel, then a real split -------------
	screen.set_quantum_mode(true)
	await _frames(1)
	_check(screen.quantum_mode_on(), "量子步 toggle turns the mode on")

	var board_root = screen.board_for(0)
	board_root.activate_point(2 * 9 + 2)
	await _frames(2)
	_check(screen.quantum_pending(), "first quantum click only selects A")
	_check(screen.quantum_a_point() == 2 * 9 + 2, "A point is remembered")
	_check(session.game.move_count == 0, "selecting A does not move yet")

	screen.cancel_quantum()
	await _frames(2)
	_check(not screen.quantum_pending(), "Esc / cancel clears the pending A point")
	_check(session.game.move_count == 0, "cancelling a quantum move leaves the position alone")

	board_root.activate_point(2 * 9 + 2)
	await _frames(1)
	board_root.activate_point(6 * 9 + 6)
	await _frames(3)
	var ids = session.game.live_ids()
	_check(ids.size() == 2, "second quantum click splits reality into two universes")
	_check(screen.card_count() == ids.size(), "one card per live universe after the split")
	var total_weight := 0
	for id in ids:
		total_weight += int(session.game.get_universe(id).weight)
	_check(total_weight == 100, "weights of the two universes add up to 100 (got %d)" % total_weight)

	# Back to normal moves for the rest of the test.
	screen.set_quantum_mode(false)
	await _frames(1)
	_check(not screen.quantum_mode_on(), "量子步 toggle can be turned off again")

	# --- focus cycling -----------------------------------------------------
	screen.cycle_focus()
	await _frames(2)
	_check(screen.focused_universe() == ids[1], "Tab / cycle_focus moves focus to the next universe")

	# Give one universe a black turn, then fake a CLIENT view where black is the
	# opponent: clicks must be ignored even though the board is visible.
	var white_universe := -1
	for id in ids:
		if session.game.turn_of(id) == QGTypes.WHITE:
			white_universe = id
			break
	_check(white_universe >= 0, "one universe is waiting for white to move")
	if white_universe >= 0:
		screen.board_for(white_universe).activate_point(8 * 9 + 8)
		await _frames(2)
		var black_universe := -1
		for id in ids:
			if session.game.turn_of(id) == QGTypes.BLACK:
				black_universe = id
				break
		_check(black_universe >= 0, "the white move hands the turn to black in that universe")
		if black_universe >= 0:
			var moves_before: int = session.game.move_count
			session.mode = QGSession.Mode.CLIENT
			session.my_color = QGTypes.WHITE
			session.state_changed.emit()
			await _frames(2)
			_check(not session.can_play(black_universe), "CLIENT cannot act in the opponent's universe")
			screen.board_for(black_universe).activate_point(0)
			await _frames(2)
			_check(session.game.move_count == moves_before, "click on the opponent's turn is gated")
			session.mode = QGSession.Mode.LOCAL
			session.my_color = QGTypes.EMPTY
			session.state_changed.emit()
			await _frames(2)

	# --- pass / seal -------------------------------------------------------
	screen.request_pass()
	await _frames(2)
	var focus: int = screen.focused_universe()
	_check(
		int(session.game.get_universe(focus).consecutive_passes) == 1,
		"P / 停一手 passes in the focused universe"
	)
	screen.request_pass()
	await _frames(2)
	_check(bool(session.game.get_universe(focus).sealed), "two passes seal the focused universe")
	var sealed_board = screen.board_for(focus)
	_check(sealed_board != null and bool(sealed_board.sealed), "the board renders the sealed state")
	_check(not session.game.is_over(), "the match continues while another universe is live")

	# --- resign confirmation ----------------------------------------------
	screen.request_resign()
	await _frames(1)
	_check(screen.is_confirm_open(), "R / 认输 opens a confirmation dialog")
	screen.cancel_confirm()
	await _frames(1)
	_check(not screen.is_confirm_open(), "cancelling the dialog keeps the match running")
	_check(not session.game.is_over(), "cancelled resign does not end the match")

	screen.request_resign()
	await _frames(1)
	screen.confirm_action()
	await _frames(3)
	_check(session.game.is_over(), "confirmed resign ends the match")
	_check(screen.is_result_visible(), "result overlay appears when the match ends")

	# --- result panel buttons and exported signals -------------------------
	var result_panel = screen.result_panel()
	_check(result_panel != null, "result panel node exists")
	var rematch_hit := [false]
	var exit_hit := [false]
	screen.rematch_requested.connect(func() -> void: rematch_hit[0] = true)
	screen.exit_requested.connect(func() -> void: exit_hit[0] = true)
	_check(_press_button(result_panel, "再来一局"), "result panel has a 再来一局 button")
	await _frames(1)
	_check(rematch_hit[0], "再来一局 emits rematch_requested")
	_check(_press_button(result_panel, "返回主菜单"), "result panel has a 返回主菜单 button")
	await _frames(1)
	_check(exit_hit[0], "返回主菜单 emits exit_requested")

	# --- large boards switch to the focused layout (13x13 / 19x19) --------
	# An equal grid at 19x19 with 3 universes would leave ~22px cells, so the
	# screen has to show one big playable board plus click-to-focus thumbnails.
	session.start_local(19)
	await _frames(2)
	_move_for(session, QGTypes.BLACK, 9 * 19 + 9)
	_quantum_for(session, QGTypes.WHITE, 3 * 19 + 3, 15 * 19 + 15)
	_move_for(session, QGTypes.BLACK, 9 * 19 + 3)
	_move_for(session, QGTypes.WHITE, 3 * 19 + 9)
	_quantum_for(session, QGTypes.BLACK, 3 * 19 + 15, 15 * 19 + 3)
	await _frames(2)
	_check(session.game.live_ids().size() == 3, "three universes on a 19x19 board")
	_check(screen.is_focus_layout(), "19x19 with 3 universes uses the focused layout")
	var focused_id: int = screen.focused_universe()
	var focused_board = screen.board_for(focused_id)
	_check(
		focused_board != null and bool(focused_board.interactive),
		"the large focused board is playable"
	)
	var thumbs_ok := true
	var thumbnail_count := 0
	for id in session.game.live_ids():
		if id == focused_id:
			continue
		thumbnail_count += 1
		var thumbnail_board = screen.board_for(id)
		if thumbnail_board == null or bool(thumbnail_board.interactive):
			thumbs_ok = false
	_check(thumbnail_count == 2 and thumbs_ok, "thumbnail boards are click-to-focus only")
	var other_id := -1
	for id in session.game.live_ids():
		if id != focused_id:
			other_id = id
			break
	if other_id >= 0:
		screen.card_for(other_id).selected.emit(other_id)
		await _frames(2)
		_check(screen.focused_universe() == other_id, "clicking a thumbnail focuses that universe")

	# --- 13x13 with four universes uses the same focused layout -----------
	session.start_local(13)
	await _frames(2)
	_move_for(session, QGTypes.BLACK, 6 * 13 + 6)
	_quantum_for(session, QGTypes.WHITE, 3 * 13 + 3, 9 * 13 + 9)
	_move_for(session, QGTypes.BLACK, 6 * 13 + 3)
	_move_for(session, QGTypes.WHITE, 3 * 13 + 6)
	_quantum_for(session, QGTypes.BLACK, 3 * 13 + 9, 9 * 13 + 3)
	_quantum_for(session, QGTypes.WHITE, 9 * 13 + 6, 6 * 13 + 9)
	await _frames(2)
	_check(session.game.live_ids().size() == 4, "four universes on a 13x13 board")
	_check(screen.is_focus_layout(), "13x13 with 4 universes uses the focused layout")

	screen.queue_free()
	await _frames(2)
	_finish()


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

func _frames(count: int) -> void:
	for _i in range(maxi(1, count)):
		await process_frame


## Submits one scripted step through the real session API.
func _apply_session_step(session, step: Array) -> void:
	if String(step[0]) == "move":
		session.submit_move(int(step[1]), int(step[2]))
	else:
		session.submit_quantum(int(step[1]), int(step[2]), int(step[3]))


## Play a move in whichever live universe it is legal in. Splitting retires the
## universe it happens in, so scenarios must not address universes by fixed id.
func _move_for(session: QGSession, colour: int, point: int) -> Dictionary:
	for universe_id in session.game.live_ids():
		var universe = session.game.get_universe(universe_id)
		if session.game.turn_of(universe_id) == colour and universe.position.is_empty(point):
			return session.submit_move(universe_id, point)
	return {"ok": false}


func _quantum_for(session: QGSession, colour: int, point_a: int, point_b: int) -> Dictionary:
	for universe_id in session.game.live_ids():
		var universe = session.game.get_universe(universe_id)
		if session.game.turn_of(universe_id) != colour:
			continue
		if universe.position.is_empty(point_a) and universe.position.is_empty(point_b):
			return session.submit_quantum(universe_id, point_a, point_b)
	return {"ok": false}


func _press_button(node: Node, text: String) -> bool:
	if node == null:
		return false
	var button := _find_button(node, text)
	if button == null:
		return false
	button.pressed.emit()
	return true


func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node as Button
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("PASS  %s" % message)
	else:
		_failures.append(message)
		printerr("FAIL  %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("\nUI_BOARD_SMOKE PASS (%d checks)" % _checks)
		quit(0)
	else:
		printerr("\nUI_BOARD_SMOKE FAIL (%d failures / %d checks)" % [_failures.size(), _checks])
		for failure in _failures:
			printerr("  - %s" % failure)
		quit(1)
