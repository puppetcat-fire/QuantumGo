## End-to-end smoke test for the interactive tutorial.
##
## Drives the real shell, the real tutorial screen and the real board widget
## through all five steps, captures a screenshot of each one, and asserts the
## engine state the lesson claims is actually true.
##
##   godot --path <project> --script res://tests/ui_tutorial/smoke.gd
extends SceneTree

const TUTORIAL_DIR := "res://tmp/screens/tutorial"

var failures: int = 0
var checks: int = 0
var _shell: Node = null
var _screen: QGTutorialScreen = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("-- boot shell")
	var packed: PackedScene = load("res://src/ui/shell/main.tscn")
	if packed == null:
		_fail("main.tscn loads")
		_finish()
		return
	_shell = packed.instantiate()
	root.add_child(_shell)
	await _frames(3)
	_check(_shell != null, "shell instantiates")

	print("-- open tutorial")
	_shell.call("show_screen", "tutorial")
	await _frames(3)
	_screen = _shell.call("screen", "tutorial")
	_check(_screen != null, "tutorial screen is routed")
	if _screen == null:
		_finish()
		return

	_check(_screen.current_step() == 0, "tutorial starts at step 1")
	_check(_screen.step_title().contains("围棋"), "step 1 introduces Go")
	_check(_screen.live_universe_count() == 1, "step 1 shows one universe")
	await _shoot("step1_intro")

	print("-- step 2: place a normal stone")
	var start_button := _find_button(_screen, "开始")
	_check(start_button != null, "step 1 has a 开始 button")
	if start_button == null:
		_finish()
		return
	start_button.pressed.emit()
	await _frames(3)
	_check(_screen.current_step() == 1, "开始 advances to step 2")
	var board0 := _screen.board_for(0)
	_check(board0 != null, "step 2 renders a board")
	if board0 != null:
		board0.activate_point(4 * 9 + 4)
	await _frames(3)
	_check(_screen.current_step() == 2, "placing a stone advances to step 3")
	_check(_screen.live_universe_count() == 1, "one universe after a normal move")
	await _shoot("step2_stone")

	print("-- step 3: quantum split")
	var quantum_button := _find_button(_screen, "量子步")
	_check(quantum_button != null, "step 3 exposes the 量子步 button")
	if quantum_button == null:
		_finish()
		return
	quantum_button.pressed.emit()
	await _frames(2)
	var move_board := _screen.board_for(0)
	_check(move_board != null, "step 3 board is interactive")
	if move_board == null:
		_finish()
		return
	move_board.activate_point(2 * 9 + 2)
	await _frames(2)
	move_board = _screen.board_for(0)
	move_board.activate_point(2 * 9 + 6)
	await _frames(3)
	_check(_screen.live_universe_count() == 2, "quantum move creates a second universe")
	_check(_screen.current_step() == 3, "split advances to step 4")
	await _shoot("step3_split")

	print("-- step 4: observe the phantom")
	var phantom_universe: int = int(_screen.call("phantom_universe"))
	_check(phantom_universe >= 0, "the lesson knows which universe carries the phantom")
	var phantom_board := _screen.board_for(phantom_universe) if phantom_universe >= 0 else null
	_check(phantom_board != null, "step 4 shows the phantom universe")
	if phantom_board == null:
		_finish()
		return
	# The scenario puts the phantom in the top-left corner with one liberty.
	phantom_board.activate_point(1 * 9 + 0)
	await _frames(3)
	_check(_screen.live_universe_count() == 1, "capturing the phantom collapses the branch")
	_check(_screen.current_step() == 4, "collapse advances to step 5")
	_check(_screen.step_title().contains("权重"), "step 5 explains weighted scoring")
	await _shoot("step4_collapse")

	print("-- finish")
	var finish_button := _find_button(_screen, "完成")
	_check(finish_button != null, "last step has a 完成 button")
	if finish_button != null:
		finish_button.pressed.emit()
		await _frames(3)
		_check(String(_shell.call("current_screen")) == "menu", "完成 returns to the menu")

	print("-- re-enter: quantum mode must not stick")
	# 回归：量子步按钮的文字是按下时才改的，只重置 _quantum_mode 会留下"取消量子步"，
	# 重进教程看起来像按钮默认被选中。
	_shell.call("show_screen", "tutorial")
	await _frames(3)
	_screen = _shell.call("screen", "tutorial")
	_check(_screen != null, "tutorial screen is routed again")
	if _screen != null:
		_check(_screen.current_step() == 0, "re-entering restarts at step 1")
		_check(not _screen.quantum_mode_on(), "re-entering leaves quantum mode off")
		var reset_button := _find_button(_screen, "量子步")
		_check(reset_button != null and reset_button.text == "量子步",
			"re-entering restores the 量子步 button label")
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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TUTORIAL_DIR))
	var path := "%s/%s.png" % [TUTORIAL_DIR, name]
	image.save_png(path)
	print("   shot: %s" % path)


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


func _fail(message: String) -> void:
	_check(false, message)


func _finish() -> void:
	print("")
	if failures == 0:
		print("TUTORIAL PASS (%d checks)" % checks)
		quit(0)
	else:
		print("TUTORIAL FAIL (%d of %d checks)" % [failures, checks])
		quit(1)
