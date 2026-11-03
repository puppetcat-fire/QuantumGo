## Windowed screenshot harness for the match screen (task-2).
##
## Usage:
##   godot --path <project> --script res://tests/ui_board/shots.gd -- <scenario> <out.png> [frames]
##
## Scenarios mirror tools/shot.gd where they overlap (empty / midgame / split /
## result) and add the states this screen introduces:
##   two, four, six      — the multi-board layouts the engine can reach (cap: 6)
##   board13_four        — 13x13 with 4 universes (focused + thumbnail layout)
##   board19_three       — 19x19 with 3 universes (focused + thumbnail layout)
##   result_six          — result overlay with six universe rows
##   sealed              — one sealed universe next to live ones
##   quantum_pending     — first point of a quantum move picked (A marker + violet ghost)
##   hover               — normal hover ghost stone
##   online_wait         — CLIENT view where the opponent is to move
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var scenario := String(args[0]) if args.size() > 0 else "six"
	var out_path := String(args[1]) if args.size() > 1 else "res://tmp/screens/match_%s.png" % scenario
	var frames := int(args[2]) if args.size() > 2 else 14

	var session = root.get_node_or_null("Session")
	if session == null:
		printerr("shots: Session autoload missing")
		quit(2)
		return

	var nudge := _prepare(session, scenario)
	await process_frame

	var packed: PackedScene = load("res://src/ui/match/match.tscn")
	if packed == null:
		printerr("shots: cannot load match scene")
		quit(2)
		return
	var screen = packed.instantiate()
	root.add_child(screen)
	await process_frame

	if scenario == "quantum_pending":
		screen.set_quantum_mode(true)
		await process_frame
		screen.board_for(0).activate_point(nudge)
		await process_frame
		var pending_board = screen.board_for(0)
		if pending_board != null:
			pending_board.set("_hover_index", 5 * 9 + 1)
			pending_board.queue_redraw()
	elif scenario == "hover":
		var hover_board = screen.board_for(0)
		if hover_board != null:
			hover_board.set("_hover_index", 5 * 9 + 1)
			hover_board.queue_redraw()

	for _frame in range(maxi(1, frames)):
		await process_frame

	if out_path.begins_with("res://"):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_path.get_base_dir()))
	var image := root.get_texture().get_image()
	if image == null:
		printerr("shots: no framebuffer")
		quit(3)
		return
	var code := image.save_png(out_path)
	print("shots: saved %s (%s) code=%d" % [out_path, str(image.get_size()), code])
	quit(0 if code == OK else 4)


## Builds the requested state. Returns a point index used by scenarios that need
## a post-load interaction (A marker).
func _prepare(session, scenario: String) -> int:
	var board_size := 9
	match scenario:
		"board13_four":
			board_size = 13
		"board19_three":
			board_size = 19
	session.start_local(board_size)
	var game: QGGame = session.game
	var n := game.board_size

	match scenario:
		"empty":
			return 40
		"board13_four":
			_build_four_13(game)
			return 40
		"board19_three":
			_build_three_19(game)
			return 40
		"two":
			_build_midgame(game)
			_quantum(game, 0, 0, 0, 8, 8)
			return 40
		"four":
			_build_split(game)
			_quantum(game, 0, 0, 0, 8, 8)
			return 40
		"six", "result_six":
			_build_six(game)
			if scenario == "result_six":
				game.resign(QGTypes.WHITE)
			return 40
		"split":
			_build_split(game)
			return 76
		"result":
			_build_split(game)
			game.resign(QGTypes.WHITE)
			return 40
		"sealed":
			_build_split(game)
			# Two passes seal one universe; the other two keep playing.
			game.apply_pass(1, game.turn_of(1))
			game.apply_pass(1, game.turn_of(1))
			return 40
		"quantum_pending":
			_build_midgame(game)
			return 4 * n + 6
		"online_wait":
			_build_midgame(game)
			session.mode = QGSession.Mode.CLIENT
			session.my_color = QGTypes.WHITE
			return 40
		_:
			_build_midgame(game)
			return 40


## 13x13 with four universes: too dense for an equal grid, so the match screen
## must switch to focused board + thumbnails.
func _build_four_13(game: QGGame) -> void:
	_move(game, 0, 6, 6)
	_quantum(game, 0, 3, 3, 9, 9)     # 0 + 1
	_move(game, 0, 6, 3)
	_move(game, 1, 3, 6)
	_quantum(game, 0, 3, 9, 9, 3)     # 0 + 2
	_quantum(game, 1, 9, 6, 6, 9)     # 1 + 3
	_move(game, 2, 2, 2)
	_move(game, 3, 10, 10)


## 19x19 with three universes: equal boards would be ~22px per cell, so this also
## uses the focused layout.
func _build_three_19(game: QGGame) -> void:
	_move(game, 0, 9, 9)
	_quantum(game, 0, 3, 3, 15, 15)   # 0 + 1
	_move(game, 0, 9, 3)
	_move(game, 1, 3, 9)
	_quantum(game, 0, 3, 15, 15, 3)   # 0 + 2
	_move(game, 2, 9, 15)


func _build_midgame(game: QGGame) -> void:
	var n := game.board_size
	var play := [
		[QGTypes.BLACK, 4, 4], [QGTypes.WHITE, 2, 2], [QGTypes.BLACK, 6, 2],
		[QGTypes.WHITE, 3, 6], [QGTypes.BLACK, 6, 6], [QGTypes.WHITE, 2, 5],
		[QGTypes.BLACK, 5, 4], [QGTypes.WHITE, 1, 3], [QGTypes.BLACK, 7, 4],
		[QGTypes.WHITE, 3, 3], [QGTypes.BLACK, 6, 0], [QGTypes.WHITE, 2, 7],
	]
	for move in play:
		game.apply_move(0, int(move[1]) * n + int(move[2]), int(move[0]))


func _build_split(game: QGGame) -> void:
	var n := game.board_size
	_build_midgame(game)
	game.apply_quantum(0, 3 * n + 1, 6 * n + 4, game.turn_of(0))
	game.apply_move(1, 1 * n + 1, game.turn_of(1))
	game.apply_move(1, 5 * n + 7, game.turn_of(1))
	game.apply_quantum(1, 2 * n + 1, 7 * n + 7, game.turn_of(1))
	game.apply_move(0, 7 * n + 1, game.turn_of(0))


## Six live universes, the engine's cap (MAX_LIVE_UNIVERSES). Every board gets a
## few stones and the branched boards carry phantom stones, so the screenshot
## exercises the small-board layout, weight badges and the phantom style.
func _build_six(game: QGGame) -> void:
	_move(game, 0, 4, 4)
	_quantum(game, 0, 2, 2, 6, 6)     # 0 + 1
	_move(game, 0, 4, 2)
	_move(game, 1, 2, 4)
	_quantum(game, 0, 2, 6, 6, 2)     # 0 + 2
	_quantum(game, 1, 6, 4, 4, 6)     # 1 + 3
	_quantum(game, 2, 4, 8, 8, 4)     # 2 + 4
	_quantum(game, 3, 0, 4, 8, 8)     # 3 + 5
	_move(game, 4, 0, 0)
	_move(game, 5, 0, 8)
	_move(game, 4, 4, 0)
	_move(game, 5, 4, 8)


func _move(game: QGGame, universe_id: int, row: int, col: int) -> void:
	var colour := game.turn_of(universe_id)
	if colour == QGTypes.EMPTY:
		return
	game.apply_move(universe_id, row * game.board_size + col, colour)


func _quantum(game: QGGame, universe_id: int, a_row: int, a_col: int, b_row: int, b_col: int) -> void:
	var colour := game.turn_of(universe_id)
	if colour == QGTypes.EMPTY:
		return
	game.apply_quantum(
		universe_id,
		a_row * game.board_size + a_col,
		b_row * game.board_size + b_col,
		colour
	)
