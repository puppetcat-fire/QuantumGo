## Wire codec tests: what the host broadcasts must rebuild the exact same game on
## the client or the two boards drift apart mid-match.
extends RefCounted

var failures: int = 0
var checks: int = 0
var current_test: String = ""


func run_all() -> int:
	_test_empty_game_round_trip()
	_test_midgame_round_trip()
	_test_split_and_collapse_round_trip()
	_test_nineteen_lines_round_trip()
	print("")
	if failures == 0:
		print("PASS  %d wire checks" % checks)
		return 0
	print("FAIL  %d of %d wire checks failed" % [failures, checks])
	return 1


func _start(name: String) -> void:
	current_test = name
	print("-- %s" % name)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("   FAIL %s :: %s" % [current_test, message])


func _idx(size: int, row: int, col: int) -> int:
	return row * size + col


func _assert_same(original: QGGame, restored: QGGame) -> void:
	_check(restored != null, "restored game exists")
	if restored == null:
		return
	_check(original.board_size == restored.board_size, "board size")
	_check(original.live_ids() == restored.live_ids(), "live universe ids")
	_check(original.total_weight() == restored.total_weight(), "total weight")
	_check(original.move_count == restored.move_count, "move count")
	_check(original.phase == restored.phase, "phase")
	_check(original.winner == restored.winner, "winner")
	for id in original.live_ids():
		var left := original.get_universe(id)
		var right := restored.get_universe(id)
		_check(right != null, "universe %d exists" % id)
		if right == null:
			continue
		_check(left.weight == right.weight, "universe %d weight" % id)
		_check(left.turn == right.turn, "universe %d turn" % id)
		_check(left.phantom_point == right.phantom_point, "universe %d phantom point" % id)
		_check(left.partner == right.partner, "universe %d partner" % id)
		_check(left.ko_point == right.ko_point, "universe %d ko" % id)
		_check(left.sealed == right.sealed, "universe %d sealed" % id)
		_check(left.children == right.children, "universe %d children" % id)
		_check(left.position.cells == right.position.cells, "universe %d cells" % id)
		_check(left.position.phantom == right.position.phantom, "universe %d phantom" % id)
	var left_score := original.weighted_score()
	var right_score := restored.weighted_score()
	_check(int(left_score["black"]) == int(right_score["black"]), "black score")
	_check(int(left_score["white"]) == int(right_score["white"]), "white score")
	_check(int(left_score["winner"]) == int(right_score["winner"]), "score winner")


func _test_empty_game_round_trip() -> void:
	_start("empty game round trip")
	var game := QGGame.create(9)
	var restored := QGWire.decode_game(QGWire.encode_state(game))
	_assert_same(game, restored)


func _test_midgame_round_trip() -> void:
	_start("midgame round trip")
	var game := QGGame.create(9)
	var moves := [
		[3, 3, QGTypes.BLACK], [5, 5, QGTypes.WHITE], [3, 4, QGTypes.BLACK],
		[5, 4, QGTypes.WHITE], [4, 3, QGTypes.BLACK], [2, 2, QGTypes.WHITE],
		[6, 6, QGTypes.BLACK], [1, 7, QGTypes.WHITE],
	]
	for move in moves:
		game.apply_move(0, _idx(9, int(move[0]), int(move[1])), int(move[2]))
	var restored := QGWire.decode_game(QGWire.encode_state(game))
	_assert_same(game, restored)
	var continued := restored.apply_move(0, _idx(9, 7, 1), QGTypes.BLACK)
	_check(continued["ok"], "restored game accepts the next move")


func _test_split_and_collapse_round_trip() -> void:
	_start("split and collapse round trip")
	var game := QGGame.create(9)
	game.apply_move(0, _idx(9, 4, 4), QGTypes.BLACK)
	game.apply_move(0, _idx(9, 0, 1), QGTypes.WHITE)
	game.apply_quantum(0, _idx(9, 8, 8), _idx(9, 0, 0), QGTypes.BLACK)
	# Split the branch that carries the phantom so the codec sees a deeper tree.
	var phantom_child := -1
	for child_id in game.live_ids():
		if game.get_universe(child_id).is_phantom_holder():
			phantom_child = child_id
	_check(phantom_child >= 0, "one live branch carries the phantom")
	if phantom_child < 0:
		return
	game.apply_quantum(phantom_child, _idx(9, 7, 0), _idx(9, 7, 2), QGTypes.WHITE)

	var before := QGWire.decode_game(QGWire.encode_state(game))
	_assert_same(game, before)

	# Collapse the false branch and confirm the codec survives a smaller tree.
	var grandchildren: Array[int] = []
	for id in game.live_ids():
		if game.get_universe(id).parent == phantom_child:
			grandchildren.append(id)
	_check(grandchildren.size() == 2, "the phantom branch has two children")
	if grandchildren.size() != 2:
		return
	game.apply_move(grandchildren[0], _idx(9, 5, 5), QGTypes.BLACK)
	game.apply_move(grandchildren[0], _idx(9, 1, 0), QGTypes.WHITE)
	_check(game.live_ids().size() == 1, "branch collapsed before encoding")
	var after := QGWire.decode_game(QGWire.encode_state(game))
	_assert_same(game, after)


func _test_nineteen_lines_round_trip() -> void:
	_start("19x19 round trip")
	var game := QGGame.create(19)
	game.apply_move(0, _idx(19, 3, 3), QGTypes.BLACK)
	game.apply_move(0, _idx(19, 15, 15), QGTypes.WHITE)
	game.apply_quantum(0, _idx(19, 9, 9), _idx(19, 10, 10), QGTypes.BLACK)
	var bytes := QGWire.encode_state(game)
	var restored := QGWire.decode_game(bytes)
	_assert_same(game, restored)
	print("   wire size for 19x19 with 2 universes: %d bytes" % bytes.size())
