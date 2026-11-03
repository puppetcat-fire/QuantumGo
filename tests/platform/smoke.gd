## Platform service smoke test.
##
## Steam itself is not installed in CI or on a dev checkout, so what is verified
## here is the contract the rest of the game relies on: the service is inert but
## safe without Steam, and the achievement / leaderboard hooks fire at the right
## moments during a real match.
##
##   godot --headless --path <project> --script res://tests/platform/smoke.gd
extends SceneTree

var failures: int = 0
var checks: int = 0
var _session: QGSession = null
var _platform: Node = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_platform = root.get_node_or_null("Platform")
	_session = root.get_node_or_null("Session")
	_check(_platform != null, "Platform autoload exists")
	_check(_session != null, "Session autoload exists")
	if _platform == null or _session == null:
		_finish()
		return

	print("-- inert without Steam")
	_check(not bool(_platform.call("is_available")), "Steam is reported unavailable on this machine")
	_check(_platform.call("player_display_name") != null, "display name falls back to the local profile")
	_check(String(_platform.call("player_display_name")).length() > 0, "fallback name is not empty")
	_check(_platform.call("shows_overlay") == false, "overlay reports unavailable")
	_platform.call("open_overlay")
	_platform.call("poll")
	_check(true, "overlay and poll are safe no-ops without Steam")
	_check(_platform.call("submit_leaderboard_score", "TOTAL_WEIGHTED_SCORE", 42) == false,
		"leaderboard submission reports failure without Steam")
	_check(int(_platform.get("leaderboard_submissions")) == 1, "the attempt is still recorded")

	print("-- quantum achievements")
	_session.start_local(5)
	_reset_platform_counters()
	# Black makes a quantum move: the split must fire FIRST_QUANTUM_SPLIT. Both
	# candidate points are corners, so whichever sibling carries the phantom its
	# stone has exactly two liberties and can be captured in three moves.
	var split := _session.submit_quantum(0, _idx(5, 0, 0), _idx(5, 0, 4))
	_check(bool(split.get("ok", false)), "quantum move accepted")
	_check(_has("FIRST_QUANTUM_SPLIT"), "splitting reality unlocks FIRST_QUANTUM_SPLIT")
	if not bool(split.get("ok", false)):
		_finish()
		return

	print("-- collapse achievement")
	var phantom_universe := -1
	var phantom_point := -1
	for child_id in split["children"]:
		var child := _session.game.get_universe(child_id)
		if child.is_phantom_holder():
			phantom_universe = child_id
			phantom_point = child.phantom_point
	_check(phantom_universe >= 0, "one sibling carries the phantom")
	if phantom_universe < 0:
		_finish()
		return
	var liberties := _liberties_of(_session.game.get_universe(phantom_universe).position, phantom_point)
	_check(liberties.size() == 2, "the phantom corner stone has two liberties")
	if liberties.size() != 2:
		_finish()
		return
	# White fills one liberty, black plays elsewhere in that branch, white takes
	# the last one: capturing the phantom collapses the branch.
	var first_liberty := _session.submit_move(phantom_universe, liberties[0])
	_check(bool(first_liberty.get("ok", false)), "white fills the first liberty")
	var filler := -1
	for index in range(25):
		if _session.game.get_universe(phantom_universe).position.is_empty(index) and not liberties.has(index):
			filler = index
			break
	var black_elsewhere := _session.submit_move(phantom_universe, filler)
	_check(bool(black_elsewhere.get("ok", false)), "black plays elsewhere in the branch")
	var collapse := _session.submit_move(phantom_universe, liberties[1])
	var collapsed: Array = collapse.get("collapsed", [])
	_check(not collapsed.is_empty(), "capturing the phantom collapses the branch")
	_check(_has("FIRST_COLLAPSE"), "a collapse unlocks FIRST_COLLAPSE")
	var live: Array[int] = _session.game.live_ids()
	_check(live.size() == 1, "only the real branch survives")

	print("-- match result hooks")
	_reset_platform_counters()
	_session.submit_resign(QGTypes.BLACK)
	_check(_session.game.is_over(), "resigning ends the match")
	_check(_has("WIN_FIRST_MATCH"), "a finished match unlocks WIN_FIRST_MATCH")
	_check(int(_platform.get("leaderboard_submissions")) == 1,
		"the finished match submits exactly one leaderboard score")

	_finish()


func _idx(size: int, row: int, column: int) -> int:
	return row * size + column


func _liberties_of(position: QGPosition, index: int) -> PackedInt32Array:
	return position.liberties_of(position.group_of(index))


## Small helper on the session: play a scripted move in a given universe without
## the turn guard getting in the way (tests only).
func _has(api_name: String) -> bool:
	return bool(_platform.call("has_achievement", api_name))


func _reset_platform_counters() -> void:
	_platform.set("achievement_attempts", {})
	_platform.set("leaderboard_submissions", 0)


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
		print("PLATFORM PASS (%d checks)" % checks)
		quit(0)
	else:
		print("PLATFORM FAIL (%d of %d checks)" % [failures, checks])
		quit(1)
