## End-to-end session test: plays a whole hot-seat match through `QGSession`
## (the same code path the UI uses), then checks scoring, serialization and the
## leaderboard record. Headless.
##
## Usage: godot --headless --path <project> --script res://tests/run_session.gd
extends SceneTree

const MAX_STEPS := 600

var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	var session: QGSession = root.get_node_or_null("Session")
	var leaderboard: Node = root.get_node_or_null("Leaderboard")
	if session == null or leaderboard == null:
		printerr("autoloads missing")
		quit(2)
		return

	_start(session)
	_play(session)
	_score(session)
	_leaderboard(session, leaderboard)
	_serialize(session)

	print("")
	if failures == 0:
		print("SESSION PASS  %d checks" % checks)
		quit(0)
	else:
		print("SESSION FAIL  %d of %d checks failed" % [failures, checks])
		quit(1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("   FAIL %s" % message)


func _start(session: QGSession) -> void:
	print("-- start local session")
	var result := session.start_local(9)
	_check(result["ok"], "start_local accepted")
	_check(session.game != null, "game created")
	_check(session.started, "session started")
	_check(session.mode == QGSession.Mode.LOCAL, "local mode")
	_check(session.game.live_ids().size() == 1, "one universe to begin with")


## Deterministic pseudo-random play. Mixes normal moves, quantum splits and passes
## so the state machine sees every path the UI can produce.
func _play(session: QGSession) -> void:
	print("-- play")
	var seed_value := 987654321
	var splits := 0
	var collapses := 0
	var moves := 0
	var steps := 0
	while not session.game.is_over() and steps < MAX_STEPS:
		steps += 1
		var live := session.game.live_ids()
		if live.is_empty():
			break
		seed_value = (seed_value * 1103515245 + 12345) & 0x7FFFFFFF
		var universe_id: int = live[seed_value % live.size()]
		var universe := session.game.get_universe(universe_id)
		if universe.sealed:
			continue
		var empties := _empty_points(session.game, universe_id)
		if empties.is_empty():
			session.submit_pass(universe_id)
			continue
		var roll := seed_value % 100
		var result: Dictionary
		if roll < 22 and session.game.can_split(universe_id) and empties.size() >= 2:
			var point_a: int = empties[seed_value % empties.size()]
			var point_b: int = empties[(seed_value / 7) % empties.size()]
			if point_a == point_b:
				continue
			result = session.submit_quantum(universe_id, point_a, point_b)
			if result.get("ok", false):
				splits += 1
				collapses += int(result.get("collapsed", []).size())
		elif roll < 30:
			result = session.submit_pass(universe_id)
		else:
			result = session.submit_move(universe_id, empties[seed_value % empties.size()])
			if result.get("ok", false):
				moves += 1
		if not result.get("ok", false):
			# A rejected command is fine (suicide/ko); the UI must survive it too.
			_check(String(result.get("reason", "")) != "", "rejection carries a reason")

	print("   moves=%d splits=%d collapses=%d steps=%d universes=%d" % [
		moves, splits, collapses, steps, session.game.live_ids().size(),
	])
	_check(moves > 10, "the bot actually played")
	_check(splits > 0, "at least one quantum split happened")
	_check(session.game.total_weight() == 100, "weight invariant held through the match")

	# Seal everything so the match moves to the scoring phase, then confirm.
	_seal_all(session)
	_check(session.game.is_scoring(), "sealing every universe enters the scoring phase")
	_check(not session.game.is_over(), "the match is not over before both sides confirm")
	var confirm := session.submit_confirm_score()
	_check(confirm["ok"], "confirming the score is accepted")
	_check(session.game.is_over(), "game ends once both sides confirm")


func _seal_all(session: QGSession) -> void:
	var guard := 0
	while not session.game.is_over() and guard < 200:
		guard += 1
		var live := session.game.live_ids()
		var sealed_any := false
		for universe_id in live:
			var universe := session.game.get_universe(universe_id)
			if universe.sealed:
				continue
			session.submit_pass(universe_id)
			sealed_any = true
		if not sealed_any:
			break


func _score(session: QGSession) -> void:
	print("-- score")
	if session.game == null:
		return
	var score := session.game.weighted_score()
	_check(int(score["black"]) >= 0, "black total non-negative")
	_check(int(score["white"]) >= 0, "white total non-negative")
	var rows: Array = score["universes"]
	_check(rows.size() > 0, "score breakdown lists universes")
	var weight_sum := 0
	for row in rows:
		weight_sum += int(row["weight"])
	_check(weight_sum == 100, "score breakdown weights add up to 100")
	_check(session.game.winner == int(score["winner"]), "game winner matches the weighted score")
	if int(score["black"]) > int(score["white"]):
		_check(session.game.winner == QGTypes.WINNER_BLACK, "black winner is consistent")
	elif int(score["white"]) > int(score["black"]):
		_check(session.game.winner == QGTypes.WINNER_WHITE, "white winner is consistent")
	print("   black=%d white=%d winner=%s" % [
		int(score["black"]), int(score["white"]), QGTypes.winner_name(session.game.winner),
	])


func _leaderboard(session: QGSession, leaderboard: Node) -> void:
	print("-- leaderboard")
	var names := {QGTypes.BLACK: "测试黑", QGTypes.WHITE: "测试白"}
	var entry: Dictionary = leaderboard.record_match(
		names, session.game.winner, session.game.board_size, session.game.move_count, "local"
	)
	_check(entry.has("rating_delta"), "record has a rating delta")
	var rows: Array = leaderboard.standings()
	_check(rows.size() >= 2, "two players on the board")
	if rows.size() >= 2:
		_check(int(rows[0]["rating"]) >= int(rows[1]["rating"]), "standings sorted by rating")
	_check(leaderboard.history.size() > 0, "history recorded")


func _serialize(session: QGSession) -> void:
	print("-- serialize")
	var state := session.game.to_dict()
	var restored := QGGame.from_dict(state)
	_check(restored.live_ids() == session.game.live_ids(), "universes survive a save/load")
	_check(restored.weighted_score() == session.game.weighted_score(), "score survives a save/load")

	var wire := QGWire.encode_state(session.game)
	var from_wire := QGWire.decode_game(wire)
	_check(from_wire.live_ids() == session.game.live_ids(), "wire round trip keeps universes")
	_check(from_wire.weighted_score() == session.game.weighted_score(), "wire round trip keeps score")
	print("   wire size: %d bytes for %d universes" % [wire.size(), session.game.live_ids().size()])


func _empty_points(game: QGGame, universe_id: int) -> Array[int]:
	var out: Array[int] = []
	var universe := game.get_universe(universe_id)
	if universe == null:
		return out
	for index in range(universe.position.cells.size()):
		if universe.position.is_empty(index):
			out.append(index)
	return out
