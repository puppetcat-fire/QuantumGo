## Headless client process for the ENet integration test.
##
## Started by `tests/net/run_net_test.ps1` as its own Godot process:
##   godot --headless --path <project> --script res://tests/net/client_probe.gd -- --port=<n> --mode=<mode>
##
## Modes:
##   match    (default) play the scripted match started by `host_probe.gd`
##   idle     connect, play one move, then wait to be killed by the driver
##            (used by the host's mid-match disconnect scenario)
##   refused  connect to a port nobody listens on and expect a clean,
##            player-facing error instead of a crash
##
## Prints `NET PASS client ...` / `NET FAIL client :: ...` and exits 0 / 1.
extends SceneTree

const BLACK := 1
const WHITE := 2

# Points this probe plays on the 9x9 board (index = row * 9 + column). The
# host's own points live in host_probe.gd; both files describe the same
# choreography.
const CLIENT_MOVE_1 := 24  # row 2, col 6
const CLIENT_MOVE_2 := 58  # row 6, col 4

var _session: QGSession = null
var _port := 27777
var _mode := "match"
var _kill_file := ""
var _statuses: Array[String] = []
var _rejections: Array[String] = []
var _ended := false
var _end_result: Dictionary = {}
var _state_before_start := false
var _finished := false
var _watchdog: SceneTreeTimer = null


func _initialize() -> void:
	_run()


func _run() -> void:
	# Printed first so the test driver can kill this exact engine process even
	# when the launcher's process tree cannot be terminated from the shell.
	print("NET PID %d" % OS.get_process_id())
	# In `--script` mode the root window is not inside the tree yet while
	# `_initialize` runs, so the autoload's multiplayer API does not exist.
	# One frame later it does.
	await process_frame
	await process_frame

	_port = _int_arg("--port=", 27777)
	_mode = _string_arg("--mode=", "match")
	_kill_file = _string_arg("--kill-file=", "")
	_session = root.get_node_or_null("Session") as QGSession
	if _session == null:
		_fail("Session autoload is missing")
		return

	_session.status_changed.connect(_on_status)
	_session.move_rejected.connect(_on_rejection)
	_session.state_changed.connect(_on_state_changed)
	_session.match_ended.connect(_on_match_ended)

	_watchdog = create_timer(_watchdog_seconds())
	_watchdog.timeout.connect(_on_watchdog)

	match _mode:
		"match":
			await _client_match()
		"idle":
			await _client_idle()
		"refused":
			await _client_refused()
		_:
			_fail("unknown mode '%s'" % _mode)


# --------------------------------------------------------------------------
# Scenarios
# --------------------------------------------------------------------------

func _client_match() -> void:
	var result := _session.join_match("127.0.0.1", _port, "客人")
	if not bool(result.get("ok", false)):
		_fail("join_match refused: %s" % str(result))
		return
	print("NET CLIENT CONNECTING port=%d" % _port)

	if not await _wait_until(func() -> bool: return _session.started, 20000):
		_fail("match never started (last status: %s)" % _last_status())
		return
	print("NET CLIENT STARTED")
	# "正在连接" / "已进入房间" are expected before the match; from here on a
	# status is either an error or the host leaving.
	_statuses.clear()

	if _session.game == null:
		_fail("match_started fired without a game")
		return
	if _session.my_color != WHITE:
		_fail("client colour is %d, expected white" % _session.my_color)
		return
	# The lead specifically worried about a `state` packet landing before
	# `match_started` while the client still has game == null.
	if _state_before_start:
		_fail("a state packet was applied before match_started")
		return

	if not await _wait_until(_client_turn_predicate(1), 15000):
		_fail("never got our first turn (moves=%d)" % _moves())
		return
	if not _expect_ok(_play_as(WHITE, CLIENT_MOVE_1), "client move 1"):
		return

	if not await _wait_until(_client_turn_predicate(3), 15000):
		_fail("host quantum move never arrived (moves=%d)" % _moves())
		return
	if not _expect_ok(_play_as(WHITE, CLIENT_MOVE_2), "client move 2"):
		return

	if not await _wait_until(_client_turn_predicate(5), 15000):
		_fail("host move 3 never arrived (moves=%d)" % _moves())
		return
	if not _expect_ok(_pass_as(WHITE), "client pass"):
		return

	# The host seals universe 0 with its own pass (move 7), then we resign.
	if not await _wait_until(func() -> bool:
			return _session.game != null and _session.game.move_count >= 7, 15000):
		_fail("host pass never arrived (moves=%d)" % _moves())
		return
	if not _expect_ok(_session.submit_resign(), "client resign"):
		return

	if not await _wait_until(func() -> bool: return _ended, 20000):
		_fail("match_ended never fired after resign (moves=%d)" % _moves())
		return
	if _session.game == null or not _session.game.is_over():
		_fail("match_ended fired but the mirrored game is not over")
		return
	if _session.game.winner != BLACK:
		_fail("mirrored winner is %d, expected black after we resigned" % _session.game.winner)
		return
	if not _end_result_matches_game():
		return
	if not _errors_clear():
		return
	_print_score("client")
	print("NET PASS client match")
	_finish(0)


func _client_idle() -> void:
	var result := _session.join_match("127.0.0.1", _port, "客人")
	if not bool(result.get("ok", false)):
		_fail("join_match refused: %s" % str(result))
		return
	print("NET CLIENT CONNECTING port=%d" % _port)

	if not await _wait_until(func() -> bool: return _session.started, 20000):
		_fail("match never started (last status: %s)" % _last_status())
		return
	print("NET CLIENT STARTED")

	if not await _wait_until(_client_turn_predicate(1), 15000):
		_fail("never got our first turn (moves=%d)" % _moves())
		return
	if not _expect_ok(_play_as(WHITE, CLIENT_MOVE_1), "client move 1"):
		return
	print("NET CLIENT MOVED")
	# The driver kills this process now; the exit code does not matter.
	await create_timer(55.0).timeout
	quit(1)


func _client_refused() -> void:
	var result := _session.join_match("127.0.0.1", _port, "客人")
	if not bool(result.get("ok", false)):
		_fail("join_match refused locally: %s" % str(result))
		return
	print("NET CLIENT CONNECTING port=%d" % _port)

	if not await _wait_until(func() -> bool: return _last_status_has_failure(), 15000):
		_fail("no connection error was reported (last status: %s)" % _last_status())
		return
	if _session.started:
		_fail("client claims the match started although no host exists")
		return
	if _session.game != null:
		_fail("client mirrored a game although no host exists")
		return

	var failure := _last_status()
	_session.leave()
	print("NET CLIENT ERROR %s" % failure)
	print("NET PASS client refused")
	_finish(0)


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

## A split retires the universe it happens in, so the scripted match cannot
## address universes by fixed id. These helpers pick the first live universe
## where the move is legal, which is what a player does in the UI.
func _live_turn(colour: int) -> int:
	if _session.game == null:
		return -1
	for universe_id in _session.game.live_ids():
		if _session.game.turn_of(universe_id) == colour:
			return universe_id
	return -1


func _play_as(colour: int, point: int) -> Dictionary:
	for universe_id in _session.game.live_ids():
		var universe = _session.game.get_universe(universe_id)
		if _session.game.turn_of(universe_id) == colour and universe.position.is_empty(point):
			return _session.submit_move(universe_id, point)
	return {"ok": false, "reason": "no_universe_for_side"}


func _pass_as(colour: int) -> Dictionary:
	var universe_id := _live_turn(colour)
	if universe_id < 0:
		return {"ok": false, "reason": "no_universe_for_side"}
	return _session.submit_pass(universe_id)


func _client_turn_predicate(min_moves: int) -> Callable:
	return func() -> bool:
		if _session.game == null:
			return false
		return _session.game.move_count >= min_moves and _live_turn(WHITE) >= 0


func _end_result_matches_game() -> bool:
	if _end_result.is_empty():
		_fail("match_ended fired with an empty result")
		return false
	var score := _session.game.weighted_score()
	if int(_end_result.get("moves", -1)) != _session.game.move_count:
		_fail("match_ended moves=%s but local game has %d" % [
			str(_end_result.get("moves")), _session.game.move_count])
		return false
	if int(_end_result.get("black", -1)) != int(score["black"]):
		_fail("match_ended black=%s but local score is %d" % [
			str(_end_result.get("black")), int(score["black"])])
		return false
	if int(_end_result.get("white", -1)) != int(score["white"]):
		_fail("match_ended white=%s but local score is %d" % [
			str(_end_result.get("white")), int(score["white"])])
		return false
	if int(_end_result.get("winner", -1)) != _session.game.winner:
		_fail("match_ended winner=%s but local winner is %d" % [
			str(_end_result.get("winner")), _session.game.winner])
		return false
	return true


func _expect_ok(result: Dictionary, what: String) -> bool:
	if bool(result.get("ok", false)):
		return true
	_fail("%s was rejected: %s" % [what, str(result)])
	return false


func _errors_clear() -> bool:
	if not _rejections.is_empty():
		_fail("commands rejected during match: %s" % str(_rejections))
		return false
	if not _statuses.is_empty():
		_fail("unexpected transport status during match: %s" % str(_statuses))
		return false
	return true


func _last_status_has_failure() -> bool:
	for status in _statuses:
		if status.contains("无法连接") or status.contains("超时"):
			return true
	return false


func _wait_until(condition: Callable, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if bool(condition.call()):
			return true
		await process_frame
	return bool(condition.call())


func _moves() -> int:
	if _session == null or _session.game == null:
		return -1
	return _session.game.move_count


func _print_score(side: String) -> void:
	var score := _session.game.weighted_score()
	print("NET SCORE %s black=%d white=%d moves=%d winner=%d" % [
		side,
		int(score["black"]),
		int(score["white"]),
		_session.game.move_count,
		int(_session.game.winner),
	])


func _last_status() -> String:
	if _statuses.is_empty():
		return ""
	return _statuses[-1]


func _watchdog_seconds() -> float:
	match _mode:
		"refused":
			return 25.0
		"idle":
			return 60.0
		_:
			return 45.0


func _on_watchdog() -> void:
	_fail("watchdog timeout (mode=%s, moves=%d, last status: %s)" % [
		_mode, _moves(), _last_status()])


func _on_status(text: String) -> void:
	_statuses.append(text)


func _on_rejection(reason: String) -> void:
	_rejections.append(reason)


func _on_state_changed() -> void:
	if _session != null and not _session.started:
		_state_before_start = true


func _on_match_ended(result: Dictionary) -> void:
	_ended = true
	_end_result = result


func _finish(code: int) -> void:
	if _finished:
		return
	_finished = true
	if _session != null:
		_session.leave()
	quit(code)


func _fail(reason: String) -> void:
	if _finished:
		return
	_finished = true
	print("NET FAIL client :: %s" % reason)
	if _session != null:
		_session.leave()
	quit(1)


func _string_arg(prefix: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return fallback


func _int_arg(prefix: String, fallback: int) -> int:
	var raw := _string_arg(prefix, "")
	if raw.is_empty() or not raw.is_valid_int():
		return fallback
	return int(raw)


## MainLoop virtual: lets the driver terminate this process even when killing
## the cmd.exe launcher tree is not allowed by the environment.
func _process(_delta: float) -> bool:
	if not _kill_file.is_empty() and FileAccess.file_exists(_kill_file):
		OS.kill(OS.get_process_id())
		quit(1)
		return true
	return false
