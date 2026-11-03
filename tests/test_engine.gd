## Unit tests for the Quantum Go rules engine. Pure GDScript, no UI, headless.
##
## Run with:  godot --headless --path . --script res://tests/run_tests.gd
extends RefCounted

var failures: int = 0
var checks: int = 0
var current_test: String = ""


func run_all() -> int:
	_test_board_setup()
	_test_normal_move()
	_test_illegal_moves()
	_test_suicide_is_rejected()
	_test_ko()
	_test_quantum_split()
	_test_quantum_rejections()
	_test_collapse_single_level()
	_test_collapse_two_levels()
	_test_phantom_inherited_by_grandchild()
	_test_collapse_returns_weight_to_surviving_branch()
	_test_non_phantom_capture_does_not_collapse()
	_test_weighted_score()
	_test_pass_seals_universe()
	_test_dead_stones_scoring()
	_test_scoring_requires_sealed_universes()
	_test_resign()
	_test_serialization_round_trip()
	_test_weight_invariant_under_play()
	_test_undo()
	print("")
	if failures == 0:
		print("PASS  %d checks" % checks)
		return 0
	print("FAIL  %d of %d checks failed" % [failures, checks])
	return 1


func _start(name: String) -> void:
	current_test = name
	print("-- %s" % name)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("   FAIL %s :: %s" % [current_test, message])


func _check_eq(actual: Variant, expected: Variant, message: String) -> void:
	_check(actual == expected, "%s (expected %s, got %s)" % [message, str(expected), str(actual)])


func _idx(size: int, row: int, col: int) -> int:
	return row * size + col


func _test_board_setup() -> void:
	_start("board setup")
	var game := QGGame.create(9)
	_check_eq(game.board_size, 9, "board size")
	_check_eq(game.live_ids(), [0] as Array[int], "single root universe")
	_check_eq(game.get_universe(0).weight, 100, "root weight")
	_check_eq(game.get_universe(0).turn, QGTypes.BLACK, "black moves first")
	_check_eq(game.total_weight(), 100, "weight invariant")
	_check(game.phase == QGGame.PHASE_PLAYING, "game is playing")


func _test_normal_move() -> void:
	_start("normal move")
	var game := QGGame.create(9)
	var result := game.apply_move(0, _idx(9, 3, 3), QGTypes.BLACK)
	_check(result["ok"], "move accepted")
	var universe := game.get_universe(0)
	_check_eq(universe.position.get_cell(_idx(9, 3, 3)), QGTypes.BLACK, "stone placed")
	_check_eq(universe.turn, QGTypes.WHITE, "turn passes to white")
	var second := game.apply_move(0, _idx(9, 4, 4), QGTypes.WHITE)
	_check(second["ok"], "white move accepted")
	_check_eq(game.get_universe(0).turn, QGTypes.BLACK, "turn back to black")


func _test_illegal_moves() -> void:
	_start("illegal moves")
	var game := QGGame.create(9)
	var out_of_range := game.apply_move(0, 999, QGTypes.BLACK)
	_check(not out_of_range["ok"], "out of range rejected")
	_check_eq(out_of_range["reason"], QGTypes.ERR_OUT_OF_RANGE, "out of range reason")

	var wrong_turn := game.apply_move(0, _idx(9, 0, 0), QGTypes.WHITE)
	_check(not wrong_turn["ok"], "wrong colour rejected")
	_check_eq(wrong_turn["reason"], QGTypes.ERR_NOT_YOUR_TURN, "wrong colour reason")

	game.apply_move(0, _idx(9, 3, 3), QGTypes.BLACK)
	var occupied := game.apply_move(0, _idx(9, 3, 3), QGTypes.WHITE)
	_check(not occupied["ok"], "occupied point rejected")
	_check_eq(occupied["reason"], QGTypes.ERR_OCCUPIED, "occupied reason")


func _test_suicide_is_rejected() -> void:
	_start("suicide rejected")
	var game := QGGame.create(9)
	var universe := game.get_universe(0)
	# White walls off the corner (0,0) so that filling it would be suicide.
	universe.position.cells[_idx(9, 0, 1)] = QGTypes.WHITE
	universe.position.cells[_idx(9, 1, 0)] = QGTypes.WHITE
	# Keep them alive by giving them liberties elsewhere.
	universe.position.cells[_idx(9, 1, 1)] = QGTypes.EMPTY
	var result := game.apply_move(0, _idx(9, 0, 0), QGTypes.BLACK)
	_check(not result["ok"], "suicide rejected")
	_check_eq(result["reason"], QGTypes.ERR_SUICIDE, "suicide reason")


func _test_ko() -> void:
	_start("ko")
	var game := QGGame.create(9)
	var universe := game.get_universe(0)
	# Classic ko shape, black is about to capture at (1,2).
	#   . B W .
	#   B W . W
	#   . B W .
	universe.position.cells[_idx(9, 0, 1)] = QGTypes.BLACK
	universe.position.cells[_idx(9, 1, 0)] = QGTypes.BLACK
	universe.position.cells[_idx(9, 2, 1)] = QGTypes.BLACK
	universe.position.cells[_idx(9, 0, 2)] = QGTypes.WHITE
	universe.position.cells[_idx(9, 1, 1)] = QGTypes.WHITE
	universe.position.cells[_idx(9, 2, 2)] = QGTypes.WHITE
	universe.position.cells[_idx(9, 1, 3)] = QGTypes.WHITE

	var capture := game.apply_move(0, _idx(9, 1, 2), QGTypes.BLACK)
	_check(capture["ok"], "ko capture accepted")
	_check_eq(capture["captured"].size(), 1, "one stone captured")
	_check_eq(game.get_universe(0).ko_point, _idx(9, 1, 1), "ko point recorded")
	var recapture := game.apply_move(0, _idx(9, 1, 1), QGTypes.WHITE)
	_check(not recapture["ok"], "immediate recapture rejected")
	_check_eq(recapture["reason"], QGTypes.ERR_KO, "ko reason")


func _test_quantum_split() -> void:
	_start("quantum split")
	var point_a := _idx(9, 3, 3)
	var point_b := _idx(9, 3, 5)
	var game := QGGame.create(9, 7)
	var result := game.apply_quantum(0, point_a, point_b, QGTypes.BLACK)
	_check(result["ok"], "split accepted")
	var children: Array = result["children"]
	_check_eq(children.size(), 2, "two sibling universes")
	_check_eq(game.live_ids(), children, "the branch that split is retired")
	_check_eq(game.total_weight(), 100, "weight conserved")
	_check(not game.get_universe(0).alive, "the split universe is no longer live")
	_check_eq(game.get_universe(0).weight, 0, "the split universe holds no weight")

	var left := game.get_universe(children[0])
	var right := game.get_universe(children[1])
	_check_eq(left.weight + right.weight, 100, "children share the weight")
	_check_eq(left.weight, 50, "first child takes the larger half")
	_check_eq(right.weight, 50, "second child takes the rest")
	_check_eq(left.partner, right.id, "siblings point at each other")
	_check_eq(right.partner, left.id, "partnership is symmetric")
	_check_eq(left.position.get_cell(point_a), QGTypes.BLACK, "first child holds point A")
	_check_eq(left.position.get_cell(point_b), QGTypes.EMPTY, "point B stays empty there")
	_check_eq(right.position.get_cell(point_b), QGTypes.BLACK, "second child holds point B")
	_check_eq(right.position.get_cell(point_a), QGTypes.EMPTY, "point A stays empty there")

	# Exactly one of the two siblings carries the phantom, and the coin is seeded,
	# so the engine is reproducible without the players being able to see it.
	var holders: Array[int] = []
	for child_id in children:
		if game.get_universe(child_id).is_phantom_holder():
			holders.append(child_id)
	_check_eq(holders.size(), 1, "exactly one sibling carries the phantom")
	if holders.size() == 1:
		var holder := game.get_universe(holders[0])
		_check(holder.phantom_point >= 0, "the phantom point is recorded")
		_check(holder.position.is_phantom(holder.phantom_point), "the phantom stone is flagged on the board")
		var real_id: int = children[1] if holders[0] == children[0] else children[0]
		_check(not game.get_universe(real_id).is_phantom_holder(), "the other sibling is real")
	_check_eq(left.turn, QGTypes.WHITE, "first child turn passes")
	_check_eq(right.turn, QGTypes.WHITE, "second child turn passes")

	# Same seed, same coin: this is what makes online play and replays exact.
	var repeat := QGGame.create(9, 7)
	repeat.apply_quantum(0, point_a, point_b, QGTypes.BLACK)
	_check_eq(repeat.get_universe(children[0]).phantom_point,
		game.get_universe(children[0]).phantom_point, "the seeded coin is reproducible")


func _test_quantum_rejections() -> void:
	_start("quantum rejections")
	var game := QGGame.create(9)
	var same := game.apply_quantum(0, _idx(9, 2, 2), _idx(9, 2, 2), QGTypes.BLACK)
	_check(not same["ok"], "same point rejected")
	_check_eq(same["reason"], QGTypes.ERR_BAD_POINTS, "same point reason")

	var wrong_turn := game.apply_quantum(0, _idx(9, 2, 2), _idx(9, 2, 4), QGTypes.WHITE)
	_check(not wrong_turn["ok"], "wrong colour rejected")

	game.apply_move(0, _idx(9, 2, 2), QGTypes.BLACK)
	game.apply_move(0, _idx(9, 4, 4), QGTypes.WHITE)
	var on_stone := game.apply_quantum(0, _idx(9, 2, 2), _idx(9, 2, 4), QGTypes.BLACK)
	_check(not on_stone["ok"], "occupied split point rejected")

	# Drain the weight: 100 -> 50 -> 25 -> 12 -> 6 -> 3 -> 2 -> 1
	var shrink := QGGame.create(9)
	var ids := [0]
	var guard := 0
	while true:
		guard += 1
		if guard > 20:
			break
		var target := -1
		for id in shrink.live_ids():
			if shrink.can_split(id):
				target = id
				break
		if target < 0:
			break
		var universe := shrink.get_universe(target)
		var colour := universe.turn
		var free: Array[int] = []
		for index in range(81):
			if universe.position.is_empty(index):
				free.append(index)
				if free.size() >= 2:
					break
		if free.size() < 2:
			break
		var split := shrink.apply_quantum(target, free[0], free[1], colour)
		_check(split["ok"], "split during drain accepted")
	_check_eq(shrink.total_weight(), 100, "weight still conserved after drain")
	_check(not shrink.can_split(shrink.live_ids()[0]) or shrink.get_universe(shrink.live_ids()[0]).weight >= 2, "cannot split weight 1")


## The coin that picks the phantom side is seeded, so tests can look for a seed
## that produces the situation they want to exercise. This keeps the engine free
## of test-only hooks.
func _seed_for_phantom_at(size: int, point_a: int, point_b: int, want: int) -> int:
	for seed_value in range(256):
		var probe := QGGame.create(size, seed_value)
		var result := probe.apply_quantum(0, point_a, point_b, QGTypes.BLACK)
		if not result["ok"]:
			return -1
		for child_id in result["children"]:
			if probe.get_universe(child_id).phantom_point == want:
				return seed_value
	return -1


func _test_collapse_single_level() -> void:
	_start("collapse single level")
	var point_a := _idx(9, 8, 8)
	var point_b := _idx(9, 0, 0)
	var seed_value := _seed_for_phantom_at(9, point_a, point_b, point_b)
	_check(seed_value >= 0, "found a seed that puts the phantom on point B")
	if seed_value < 0:
		return

	var game := QGGame.create(9, seed_value)
	# White already sits at (0,1), so the corner phantom has one liberty at split time.
	game.apply_move(0, _idx(9, 4, 4), QGTypes.BLACK)
	game.apply_move(0, _idx(9, 0, 1), QGTypes.WHITE)
	var split := game.apply_quantum(0, point_a, point_b, QGTypes.BLACK)
	_check(split["ok"], "split accepted")
	var phantom_child := -1
	var real_child := -1
	for child_id in split["children"]:
		if game.get_universe(child_id).is_phantom_holder():
			phantom_child = child_id
		else:
			real_child = child_id
	_check(phantom_child >= 0 and real_child >= 0, "one sibling is fake, one is real")

	var capture := game.apply_move(phantom_child, _idx(9, 1, 0), QGTypes.WHITE)
	_check(capture["ok"], "capture accepted")
	_check_eq(Array(capture["captured"]).size(), 1, "phantom captured")
	var collapsed: Array = capture["collapsed"]
	_check(collapsed.size() == 1 and int(collapsed[0]) == phantom_child, "the fake branch collapsed")
	var live: Array[int] = game.live_ids()
	_check(live.size() == 1 and live[0] == real_child, "only the real branch remains")
	_check_eq(game.get_universe(real_child).weight, 100, "the surviving sibling inherits the weight")
	_check_eq(game.total_weight(), 100, "weight invariant after collapse")


func _test_collapse_two_levels() -> void:
	_start("collapse two levels")
	var point_a := _idx(9, 8, 8)
	var point_b := _idx(9, 0, 0)
	var seed_value := _seed_for_phantom_at(9, point_a, point_b, point_b)
	_check(seed_value >= 0, "found a seed that puts the phantom on point B")
	if seed_value < 0:
		return

	var game := QGGame.create(9, seed_value)
	game.apply_move(0, _idx(9, 4, 4), QGTypes.BLACK)
	game.apply_move(0, _idx(9, 0, 1), QGTypes.WHITE)
	var first := game.apply_quantum(0, point_a, point_b, QGTypes.BLACK)
	var fake_child := -1
	var real_child := -1
	for child_id in first["children"]:
		if game.get_universe(child_id).is_phantom_holder():
			fake_child = child_id
		else:
			real_child = child_id
	_check(fake_child >= 0 and real_child >= 0, "one sibling is fake, one is real")

	# Splitting the fake branch copies its phantom stone into both grandchildren.
	var second := game.apply_quantum(fake_child, _idx(9, 7, 0), _idx(9, 7, 2), QGTypes.WHITE)
	_check(second["ok"], "second split accepted")
	var grandchildren: Array = second["children"]
	_check_eq(game.live_ids().size(), 3, "three live branches")
	_check_eq(game.total_weight(), 100, "weight conserved")
	_check(game.get_universe(grandchildren[0]).position.is_phantom(point_b),
		"the phantom stone inherited from the ancestor is still flagged")

	game.apply_move(grandchildren[0], _idx(9, 5, 5), QGTypes.BLACK)
	var capture := game.apply_move(grandchildren[0], _idx(9, 1, 0), QGTypes.WHITE)
	_check(capture["ok"], "capture accepted")
	var collapsed: Array = capture["collapsed"]
	_check(collapsed.size() == 1 and int(collapsed[0]) == fake_child,
		"the whole false subtree collapsed from its retired root")
	var live: Array[int] = game.live_ids()
	_check(live.size() == 1 and live[0] == real_child, "only the real branch remains")
	_check_eq(game.get_universe(real_child).weight, 100, "the real sibling inherits everything")
	_check_eq(game.total_weight(), 100, "weight invariant")


func _test_phantom_inherited_by_grandchild() -> void:
	_start("phantom inherited by grandchild")
	var point_a := _idx(9, 0, 0)
	var point_b := _idx(9, 0, 8)
	var seed_value := _seed_for_phantom_at(9, point_a, point_b, point_b)
	_check(seed_value >= 0, "found a seed that puts the phantom on point B")
	if seed_value < 0:
		return

	var game := QGGame.create(9, seed_value)
	var first := game.apply_quantum(0, point_a, point_b, QGTypes.BLACK)
	var fake_child := -1
	for child_id in first["children"]:
		if game.get_universe(child_id).is_phantom_holder():
			fake_child = child_id
	_check(fake_child >= 0, "the fake sibling is known")

	var second := game.apply_quantum(fake_child, _idx(9, 2, 2), _idx(9, 2, 6), QGTypes.WHITE)
	_check(second["ok"], "second split accepted")
	var grandchildren: Array = second["children"]
	for child_id in grandchildren:
		var grandchild := game.get_universe(child_id)
		_check(grandchild.position.is_phantom(point_b), "ancestor phantom survives the copy")
		_check_eq(grandchild.parent, fake_child, "grandchild parent is the split branch")
	_check(game.get_universe(grandchildren[0]).is_phantom_holder()
		or game.get_universe(grandchildren[1]).is_phantom_holder(),
		"one grandchild carries the new phantom")
	_check_eq(game.get_universe(grandchildren[0]).partner, grandchildren[1], "grandchildren are partners")


func _test_collapse_returns_weight_to_surviving_branch() -> void:
	_start("collapse keeps weight in the surviving branch")
	var step_a := _idx(9, 0, 0)
	var step_b := _idx(9, 0, 8)
	var seed_value := _seed_for_phantom_at(9, step_a, step_b, step_b)
	_check(seed_value >= 0, "found a seed with a phantom sibling")
	if seed_value < 0:
		return

	var game := QGGame.create(9, seed_value)
	# Root splits: one sibling is the phantom, the other is real and continues.
	var first := game.apply_quantum(0, step_a, step_b, QGTypes.BLACK)
	var unrelated := -1
	var real_sibling := -1
	for child_id in first["children"]:
		if game.get_universe(child_id).is_phantom_holder():
			unrelated = child_id
		else:
			real_sibling = child_id
	_check(unrelated >= 0 and real_sibling >= 0, "one fake and one real sibling")

	# The real sibling splits; its own phantom is the branch we will collapse.
	var second := game.apply_quantum(real_sibling, _idx(9, 2, 2), _idx(9, 2, 6), QGTypes.WHITE)
	var doomed := -1
	var keeps_splitting := -1
	for child_id in second["children"]:
		if game.get_universe(child_id).is_phantom_holder():
			doomed = child_id
		else:
			keeps_splitting = child_id
	_check(doomed >= 0 and keeps_splitting >= 0, "the second split has a phantom too")
	if doomed < 0 or keeps_splitting < 0:
		return

	# The surviving sibling splits once more, so the doomed universe's partner is
	# retired and its weight lives one level deeper.
	var third := game.apply_quantum(keeps_splitting, _idx(9, 4, 4), _idx(9, 4, 0), QGTypes.BLACK)
	_check(third["ok"], "third split accepted")
	var surviving_line: Array = third["children"]
	_check_eq(game.total_weight(), 100, "weight invariant before the collapse")

	var unrelated_weight: int = game.get_universe(unrelated).weight
	var freed: int = game.get_universe(doomed).weight
	var line_before := 0
	for id in surviving_line:
		line_before += game.get_universe(id).weight
	_check(freed > 0, "the doomed branch holds weight")
	game._collapse(doomed)
	_check(not game.get_universe(doomed).alive, "the fake branch is gone")
	# The weight must stay inside the surviving half of that split; an unrelated
	# branch must not collect a share of it.
	_check_eq(game.get_universe(unrelated).weight, unrelated_weight,
		"an unrelated branch does not inherit the released weight")
	var line_after := 0
	for id in surviving_line:
		line_after += game.get_universe(id).weight
	_check_eq(line_after, line_before + freed,
		"the weight went to the surviving half of the split")
	_check_eq(game.total_weight(), 100, "weight invariant after the collapse")


func _test_non_phantom_capture_does_not_collapse() -> void:
	_start("normal capture does not collapse")
	var game := QGGame.create(9)
	# A lone black stone at (0,0) ends up with a single liberty at (1,0).
	game.apply_move(0, _idx(9, 0, 0), QGTypes.BLACK)
	game.apply_move(0, _idx(9, 0, 1), QGTypes.WHITE)
	game.apply_move(0, _idx(9, 5, 5), QGTypes.BLACK)
	var capture := game.apply_move(0, _idx(9, 1, 0), QGTypes.WHITE)
	_check(capture["ok"], "capture accepted")
	if capture["ok"]:
		_check_eq(capture["captured"].size(), 1, "one stone captured")
		_check_eq(capture["collapsed"], [] as Array[int], "no universe collapsed")
	_check_eq(game.live_ids(), [0] as Array[int], "still one universe")


func _test_weighted_score() -> void:
	_start("weighted score")
	var game := QGGame.create(9)
	# Black owns the whole left column plus the area behind it.
	for row in range(9):
		game.apply_move(0, _idx(9, row, 0), QGTypes.BLACK if row % 2 == 0 else QGTypes.WHITE)
	# Not a legal game, but the score helper must simply add up areas.
	var score := game.weighted_score()
	_check(score.has("universes"), "score lists universes")
	_check_eq(score["universes"].size(), 1, "one row for one universe")
	_check(int(score["black"]) >= 0 and int(score["white"]) >= 0, "non-negative totals")

	var empty_game := QGGame.create(9)
	var empty_score := empty_game.weighted_score()
	_check_eq(empty_score["black"], 0, "empty board black score")
	_check_eq(empty_score["white"], 0, "empty board white score")
	_check_eq(empty_score["winner"], QGTypes.WINNER_NONE, "empty board is a draw")

	var filled := QGGame.create(5)
	for index in range(25):
		var colour := QGTypes.BLACK if index % 2 == 0 else QGTypes.WHITE
		filled.get_universe(0).position.cells[index] = colour
	var filled_score := filled.weighted_score()
	_check_eq(filled_score["black"], 13 * 100, "black stones weighted")
	_check_eq(filled_score["white"], 12 * 100, "white stones weighted")
	_check_eq(filled_score["winner"], QGTypes.WINNER_BLACK, "black wins the weighted total")


func _test_pass_seals_universe() -> void:
	_start("pass seals universe")
	var game := QGGame.create(9)
	var first := game.apply_pass(0, QGTypes.BLACK)
	_check(first["ok"], "first pass accepted")
	_check(not first["sealed"], "one pass does not seal")
	var second := game.apply_pass(0, QGTypes.WHITE)
	_check(second["ok"], "second pass accepted")
	_check(second["sealed"], "two passes seal")
	_check(game.is_scoring(), "all universes sealed enters the scoring phase")
	_check(not game.is_over(), "scoring phase is not the end of the game yet")

	var black_ok := game.confirm_scoring(QGTypes.BLACK)
	_check(black_ok["ok"], "black confirms")
	_check(not game.is_over(), "one confirmation is not enough")
	var white_ok := game.confirm_scoring(QGTypes.WHITE)
	_check(bool(white_ok.get("final", false)), "second confirmation finalises the score")
	_check(game.is_over(), "game over after both confirm")
	_check_eq(game.winner, QGTypes.WINNER_NONE, "empty board draw")


func _test_dead_stones_scoring() -> void:
	_start("dead stone scoring")
	var game := QGGame.create(5)
	var universe := game.get_universe(0)
	# White wall down column 2; a lone black stone sits inside white's area.
	for row in range(5):
		universe.position.cells[_idx(5, row, 2)] = QGTypes.WHITE
	universe.position.cells[_idx(5, 1, 1)] = QGTypes.BLACK

	var before := game.weighted_score()
	# White wall (5 stones) plus the clean right-hand area (10 points); the left
	# area touches both colours so it is dame while the black stone sits there.
	_check_eq(int(before["white"]), 15 * 100, "white wall and its clean area count")
	_check_eq(int(before["black"]), 1 * 100, "the black stone counts, its area is dame")

	game.apply_pass(0, QGTypes.BLACK)
	game.apply_pass(0, QGTypes.WHITE)
	_check(game.is_scoring(), "scoring phase reached")

	var mark := game.toggle_dead(0, _idx(5, 1, 1))
	_check(mark["ok"], "dead stone marked")
	_check(game.is_marked_dead(0, _idx(5, 1, 1)), "mark is remembered")
	_check_eq(game.marked_count(), 1, "one dead stone counted")

	var preview := game.weighted_score()
	_check_eq(int(preview["white"]), 25 * 100, "marked stone turns the left area into white points")
	_check_eq(int(preview["black"]), 0, "the dead stone no longer scores")
	_check_eq(int(preview["winner"]), QGTypes.WINNER_WHITE, "white leads once the stone is dead")

	# Any change to the marks invalidates earlier confirmations.
	game.confirm_scoring(QGTypes.BLACK)
	_check(game.is_confirmed(QGTypes.BLACK), "black confirmed")
	game.toggle_dead(0, _idx(5, 1, 1))
	_check(not game.is_confirmed(QGTypes.BLACK), "changing marks clears the confirmation")
	game.toggle_dead(0, _idx(5, 1, 1))
	_check_eq(game.marked_count(), 1, "mark restored")

	game.confirm_scoring(QGTypes.BLACK)
	var final := game.confirm_scoring(QGTypes.WHITE)
	_check(bool(final.get("final", false)), "score finalised")
	_check(game.is_over(), "game over after confirmation")
	_check_eq(game.winner, QGTypes.WINNER_WHITE, "white wins")
	_check_eq(game.get_universe(0).position.cells[_idx(5, 1, 1)], QGTypes.EMPTY, "dead stone removed from the board")
	_check_eq(game.marked_count(), 0, "marks cleared after finalising")


func _test_scoring_requires_sealed_universes() -> void:
	_start("scoring phase guards")
	var game := QGGame.create(9)
	game.apply_move(0, _idx(9, 4, 4), QGTypes.BLACK)
	var early := game.toggle_dead(0, _idx(9, 4, 4))
	_check(not early["ok"], "cannot mark dead stones while playing")
	var confirm_early := game.confirm_scoring(QGTypes.BLACK)
	_check(not confirm_early["ok"], "cannot confirm while playing")
	var begin := game.begin_scoring()
	_check(not begin["ok"], "cannot start scoring with an open universe")


func _test_resign() -> void:
	_start("resign")
	var game := QGGame.create(9)
	var result := game.resign(QGTypes.BLACK)
	_check(result["ok"], "resign accepted")
	_check(game.is_over(), "game over after resign")
	_check_eq(game.winner, QGTypes.WINNER_WHITE, "opponent wins")


func _test_serialization_round_trip() -> void:
	_start("serialization round trip")
	var game := QGGame.create(9)
	game.apply_move(0, _idx(9, 4, 4), QGTypes.BLACK)
	game.apply_quantum(0, _idx(9, 2, 2), _idx(9, 2, 6), QGTypes.WHITE)
	game.apply_move(1, _idx(9, 6, 6), QGTypes.BLACK)

	var state := game.to_dict()
	var restored := QGGame.from_dict(state)
	_check_eq(restored.board_size, game.board_size, "board size survives")
	_check_eq(restored.live_ids(), game.live_ids(), "universes survive")
	_check_eq(restored.total_weight(), game.total_weight(), "weights survive")
	_check_eq(restored.get_universe(1).phantom_point, game.get_universe(1).phantom_point, "phantom point survives")
	_check(restored.get_universe(1).position.is_phantom(_idx(9, 2, 6))
		or restored.get_universe(2).position.is_phantom(_idx(9, 2, 6)), "phantom flag survives")
	_check_eq(restored.seed_value, game.seed_value, "the seed survives")
	_check_eq(restored.weighted_score(), game.weighted_score(), "score survives")

	var continued := restored.apply_move(1, _idx(9, 6, 8), QGTypes.WHITE)
	_check(continued["ok"], "restored game still playable")


func _test_weight_invariant_under_play() -> void:
	_start("weight invariant under play")
	var game := QGGame.create(9)
	var seed := 12345
	for step in range(60):
		var live := game.live_ids()
		if live.is_empty():
			break
		var universe_id: int = live[seed % live.size()]
		var universe := game.get_universe(universe_id)
		if universe.sealed:
			seed += 7
			continue
		var colour := universe.turn
		var empties: Array[int] = []
		for index in range(81):
			if universe.position.is_empty(index):
				empties.append(index)
		if empties.is_empty():
			break
		seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
		var pick: int = empties[seed % empties.size()]
		if step % 5 == 4 and game.can_split(universe_id) and empties.size() >= 2:
			var other: int = empties[(seed + 3) % empties.size()]
			if other != pick:
				game.apply_quantum(universe_id, pick, other, colour)
		else:
			game.apply_move(universe_id, pick, colour)
		_check_eq(game.total_weight(), 100, "weight invariant at step %d" % step)


func _test_undo() -> void:
	_start("undo")
	var game := QGGame.create(9)
	game.apply_move(0, _idx(9, 3, 3), QGTypes.BLACK)
	_check(game.get_universe(0).position.get_cell(_idx(9, 3, 3)) == QGTypes.BLACK, "stone before undo")
	_check(game.undo(), "undo succeeds")
	_check_eq(game.get_universe(0).position.get_cell(_idx(9, 3, 3)), QGTypes.EMPTY, "stone removed by undo")
	_check_eq(game.get_universe(0).turn, QGTypes.BLACK, "turn restored")
