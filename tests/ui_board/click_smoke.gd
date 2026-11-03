## Real-input regression test.
##
## Every other UI test presses buttons by emitting their `pressed` signal and
## clicks the board through a helper method, which means a full-screen overlay
## that swallows mouse input stays invisible to the suite. That is exactly the bug
## this test exists for: the toast overlay used to cover the game and make every
## click do nothing.
##
##   godot --path <project> --script res://tests/ui_board/click_smoke.gd
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

	print("-- boot the shell")
	# The headless display server starts with a zero-sized window, which makes
	# every control unhittable. Give the root a real size so mouse coordinates mean
	# something in CI.
	if root.size.x < 100 or root.size.y < 100:
		root.size = Vector2i(1440, 900)
		await _frames(2)
	print("   viewport size: ", root.size)
	var packed: PackedScene = load("res://src/ui/shell/main.tscn")
	_shell = packed.instantiate()
	root.add_child(_shell)
	await _frames(4)
	_check(_shell.call("current_screen") == "menu", "shell starts on the menu")

	print("-- click 单机双人 with the mouse")
	var start_button := _find_button(_shell, "单机双人")
	_check(start_button != null, "the menu has a local-match button")
	if start_button == null:
		_finish()
		return
	await _click_control(start_button)
	await _frames(6)
	_check(_session.game != null, "the match started from a real click")

	print("-- click the board")
	var match_screen = _shell.get("_match_node")
	_check(match_screen != null, "match screen is mounted")
	if match_screen == null:
		_finish()
		return
	var board: Control = match_screen.call("board_for", 0)
	_check(board != null, "board widget exists")
	if board == null:
		_finish()
		return
	_check(bool(board.get("interactive")), "board is interactive")

	# The overlay that used to swallow clicks: nothing but the board (or a child of
	# it) may be under the pointer.
	var centre: Vector2 = board.get_global_rect().get_center()
	await _hover(centre)
	var hovered := root.gui_get_hovered_control()
	_check(hovered != null, "something is under the pointer")
	if hovered != null:
		_check(
			_is_descendant_of(hovered, board),
			"the pointer lands on the board, not an overlay (got %s)" % hovered.get_path()
		)

	var before := int(_session.game.move_count)
	await _click_at(centre)
	await _frames(3)
	_check(int(_session.game.move_count) == before + 1, "a real click places a stone")

	print("-- click a HUD button")
	var pass_button := _find_button(match_screen, "停一手")
	_check(pass_button != null, "the HUD has a pass button")
	if pass_button != null:
		var moves_before := int(_session.game.move_count)
		await _click_control(pass_button)
		await _frames(3)
		_check(int(_session.game.move_count) == moves_before + 1, "a real click on the HUD passes")

	_finish()


func _frames(count: int) -> void:
	for _index in range(count):
		await process_frame


## Feed an event straight into the root viewport. `Input.parse_input_event` only
## works with a real display server, so the suite uses `push_input` and stays
## runnable headless in CI.
func _push(event: InputEvent) -> void:
	root.push_input(event)


func _hover(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	_push(motion)
	await _frames(2)


func _click_at(point: Vector2) -> void:
	await _hover(point)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = point
	press.global_position = point
	_push(press)
	await _frames(1)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = point
	release.global_position = point
	_push(release)
	await _frames(1)


func _click_control(control: Control) -> void:
	await _click_at(control.get_global_rect().get_center())


func _is_descendant_of(node: Node, ancestor: Node) -> bool:
	var current := node
	while current != null:
		if current == ancestor:
			return true
		current = current.get_parent()
	return false


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
		print("CLICK PASS (%d checks)" % checks)
		quit(0)
	else:
		print("CLICK FAIL (%d of %d checks)" % [failures, checks])
		quit(1)
