## End-to-end test for the scoring phase: seal the board, mark a dead stone on
## the real widget, confirm, and check the result panel appears.
##
##   godot --path <project> --script res://tests/ui_board/scoring_smoke.gd
extends SceneTree

const SHOTS := "res://tmp/screens"

var failures: int = 0
var checks: int = 0
var _session: QGSession = null
var _screen: Control = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_session = root.get_node_or_null("Session")
	_check(_session != null, "session autoload present")
	if _session == null:
		_finish()
		return

	print("-- start a local match and mount the screen")
	_session.start_local(5)
	# A dead black stone inside white's area, plus a white wall to surround it.
	var game: QGGame = _session.game
	for row in range(5):
		game.get_universe(0).position.cells[row * 5 + 2] = QGTypes.WHITE
	game.get_universe(0).position.cells[1 * 5 + 1] = QGTypes.BLACK
	game.get_universe(0).turn = QGTypes.BLACK

	var packed: PackedScene = load("res://src/ui/match/match.tscn")
	_screen = packed.instantiate()
	root.add_child(_screen)
	await _frames(3)
	_check(_screen != null, "match screen mounts")

	print("-- pass twice to enter the scoring phase")
	_session.submit_pass(0)
	_session.submit_pass(0)
	await _frames(3)
	_check(_session.game.is_scoring(), "engine is in the scoring phase")

	var confirm_button := _find_button(_screen, "确认结算")
	_check(confirm_button != null, "the HUD offers 确认结算 instead of playing controls")
	_check(confirm_button != null and confirm_button.visible, "the confirm button is visible")

	var board: Control = _screen.call("board_for", 0)
	_check(board != null, "the board is still mounted during scoring")
	if board == null:
		_finish()
		return
	await _shoot("scoring_phase")

	print("-- mark the dead stone on the board")
	board.call("activate_point", 1 * 5 + 1)
	await _frames(3)
	_check(_session.game.marked_count() == 1, "clicking the stone marks it dead")
	_check(_session.game.is_marked_dead(0, 1 * 5 + 1), "the engine remembers the mark")
	var preview: Dictionary = _session.game.weighted_score()
	_check(int(preview["white"]) == 25 * 100, "preview counts the area for white")
	await _shoot("scoring_marked")

	print("-- confirm the result")
	confirm_button = _find_button(_screen, "确认结算")
	_check(confirm_button != null, "confirm button still present")
	if confirm_button != null:
		confirm_button.pressed.emit()
	await _frames(6)
	_check(_session.game.is_over(), "both sides confirmed, game is over")
	_check(int(_session.game.winner) == QGTypes.WINNER_WHITE, "white wins the agreed score")
	_check(_find_label_containing(_screen, "白方胜") != "", "result panel shows the winner")
	await _shoot("scoring_result")

	_finish()


func _frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _shoot(name: String) -> void:
	# The dummy renderer has no framebuffer; screenshots need a real display.
	if DisplayServer.get_name() == "headless":
		return
	await _frames(2)
	var image := root.get_texture().get_image()
	if image == null:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS))
	image.save_png("%s/%s.png" % [SHOTS, name])
	print("   shot: %s/%s.png" % [SHOTS, name])


func _find_button(node: Node, text: String) -> Button:
	if node is Button and String((node as Button).text).contains(text):
		return node
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func _find_label_containing(node: Node, text: String) -> String:
	if node is Label and String((node as Label).text).contains(text):
		return String((node as Label).text)
	for child in node.get_children():
		var found := _find_label_containing(child, text)
		if not found.is_empty():
			return found
	return ""


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
		print("SCORING PASS (%d checks)" % checks)
		quit(0)
	else:
		print("SCORING FAIL (%d of %d checks)" % [failures, checks])
		quit(1)
