## Headless host process for the ENet integration test.
##
## Started by `tests/net/run_net_test.ps1` as its own Godot process:
##   godot --headless --path <project> --script res://tests/net/host_probe.gd -- --port=<n> --mode=<mode>
##
## Modes:
##   match      (default) play a scripted match against `client_probe.gd`
##   disconnect client is killed mid-match; the host must report a clean
##              `opponent_left` / "对手已离开" instead of crashing
##   port-busy  binding an occupied port must be reported cleanly, and hosting
##              must still work once the port is free
##
## Prints `NET PASS host ...` / `NET FAIL host :: ...` and exits 0 / 1.
extends SceneTree

const BLACK := 1
const WHITE := 2

# The scripted match runs on a 9x9 board: index = row * 9 + column. The guest's
# own points live in client_probe.gd; both files describe the same choreography.
const HOST_MOVE_1 := 20    # row 2, col 2
const SPLIT_A := 38        # row 4, col 2
const SPLIT_B := 42        # row 4, col 6
const HOST_MOVE_3 := 56    # row 6, col 2

var _session: QGSession = null
var _port := 27777
var _mode := "match"
var _kill_file := ""
var _statuses: Array[String] = []
var _rejections: Array[String] = []
var _opponent_left := false
var _match_ended := false
var _guest_left := false
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
	_session.opponent_left.connect(_on_opponent_left)
	_session.match_ended.connect(_on_match_ended)
	_session.lobby_changed.connect(_on_lobby_changed)

	_watchdog = create_timer(_watchdog_seconds())
	_watchdog.timeout.connect(_on_watchdog)

	match _mode:
		"match":
			await _host_match()
		"disconnect":
			await _host_disconnect()
		"port-busy":
			await _host_port_busy()
		_:
			_fail("unknown mode '%s'" % _mode)


# --------------------------------------------------------------------------
# Scenarios
# --------------------------------------------------------------------------

func _host_match() -> void:
	var result := _session.host_match(9, "房主", _port)
	if not bool(result.get("ok", false)):
		_fail("host_match refused: %s" % str(result))
		return
	print("NET HOST READY port=%d" % _port)

	if not await _wait_until(func() -> bool: return _session.started, 20000):
		_fail("match never started (last status: %s)" % _last_status())
		return
	print("NET HOST STARTED")
	# "房间已创建，等待对手加入" is expected before the match; from here on any
	# status is either an error or a disconnect.
	_statuses.clear()
	if _session.game == null:
		_fail("match_started fired without a game")
		return
	if _session.my_color != BLACK:
		_fail("host colour is %d, expected black" % _session.my_color)
		return
	if int(_session.game.board_size) != 9:
		_fail("board size is %d, expected 9" % _session.game.board_size)
		return

	if not _expect_ok(_play_as(BLACK, HOST_MOVE_1), "host move 1"):
		return
	if not await _wait_until(_host_turn_predicate(2), 15000):
		_fail("client move never arrived (moves=%d)" % _moves())
		return

	if not _expect_ok(_quantum_as(BLACK, SPLIT_A, SPLIT_B), "host quantum"):
		return
	if not await _wait_until(_host_turn_predicate(4), 15000):
		_fail("client reply to the quantum move never arrived (moves=%d)" % _moves())
		return

	if not _expect_ok(_play_as(BLACK, HOST_MOVE_3), "host move 3"):
		return
	if not await _wait_until(_host_turn_predicate(6), 15000):
		_fail("client pass never arrived (moves=%d)" % _moves())
		return

	if not _expect_ok(_pass_as(BLACK), "host pass"):
		return
	if not await _wait_until(func() -> bool:
			return _session.game != null and _session.game.is_over(), 20000):
		_fail("match did not end after the client resigned (moves=%d)" % _moves())
		return

	if _session.game.winner != BLACK:
		_fail("winner is %d, expected black after white resigned" % _session.game.winner)
		return
	if not _errors_clear():
		return
	# The guest can only close its connection after it has received the final
	# "over" packet, so waiting for it proves the result really crossed the
	# network instead of being dropped when the host process exits.
	if not await _wait_until(func() -> bool: return _guest_left, 15000):
		_fail("guest never acknowledged the result by disconnecting")
		return
	_print_score("host")
	print("NET PASS host match")
	_finish(0)


func _host_disconnect() -> void:
	var result := _session.host_match(9, "房主", _port)
	if not bool(result.get("ok", false)):
		_fail("host_match refused: %s" % str(result))
		return
	print("NET HOST READY port=%d" % _port)

	if not await _wait_until(func() -> bool: return _session.started, 20000):
		_fail("match never started (last status: %s)" % _last_status())
		return
	print("NET HOST STARTED")
	_statuses.clear()

	if not _expect_ok(_play_as(BLACK, HOST_MOVE_1), "host move 1"):
		return
	if not await _wait_until(func() -> bool:
			return _session.game != null and _session.game.move_count >= 2, 15000):
		_fail("client never played a move before the kill (moves=%d)" % _moves())
		return
	print("NET DISCONNECT READY moves=%d" % _moves())

	# The driver hard-kills the client now (through the client's kill file); it
	# gets no chance to say goodbye. The transport notices the missing keepalives
	# a few seconds later.
	if not await _wait_until(func() -> bool: return _opponent_left, 45000):
		_fail("opponent_left never fired after the client was killed (moves=%d)" % _moves())
		return
	await process_frame

	if not _statuses.any(func(status: String) -> bool: return status.contains("对手已离开")):
		_fail("no player-facing '对手已离开' status; got %s" % str(_statuses))
		return
	if _session.game == null:
		_fail("host game was cleared when the opponent left")
		return
	if _moves() != 2:
		_fail("move count changed on disconnect: %d, expected 2" % _moves())
		return
	_print_score("host")
	print("NET PASS host disconnect")
	_finish(0)


func _host_port_busy() -> void:
	var blocker := ENetMultiplayerPeer.new()
	var blocked := blocker.create_server(_port, 1)
	if blocked != OK:
		_fail("could not occupy port %d for the test (error %d)" % [_port, blocked])
		return

	var result := _session.host_match(9, "房主", _port)
	blocker.close()
	if bool(result.get("ok", true)):
		_fail("host_match claimed success on an occupied port")
		return
	if not _statuses.any(func(status: String) -> bool: return status.contains("占用")):
		_fail("no '端口已被占用' status was emitted; got %s" % str(_statuses))
		return

	var retry := _session.host_match(9, "房主", _port)
	if not bool(retry.get("ok", false)):
		_fail("host_match failed on the port after it was freed: %s" % str(retry))
		return
	_session.leave()
	print("NET PASS host port-busy")
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


func _quantum_as(colour: int, point_a: int, point_b: int) -> Dictionary:
	for universe_id in _session.game.live_ids():
		var universe = _session.game.get_universe(universe_id)
		if _session.game.turn_of(universe_id) != colour:
			continue
		if universe.position.is_empty(point_a) and universe.position.is_empty(point_b):
			return _session.submit_quantum(universe_id, point_a, point_b)
	return {"ok": false, "reason": "no_universe_for_split"}


func _pass_as(colour: int) -> Dictionary:
	var universe_id := _live_turn(colour)
	if universe_id < 0:
		return {"ok": false, "reason": "no_universe_for_side"}
	return _session.submit_pass(universe_id)


func _host_turn_predicate(min_moves: int) -> Callable:
	return func() -> bool:
		if _session.game == null:
			return false
		return _session.game.move_count >= min_moves and _live_turn(BLACK) >= 0


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
		"disconnect":
			return 70.0
		"port-busy":
			return 20.0
		_:
			return 45.0


func _on_watchdog() -> void:
	_fail("watchdog timeout (mode=%s, moves=%d, last status: %s)" % [
		_mode, _moves(), _last_status()])


func _on_status(text: String) -> void:
	_statuses.append(text)


func _on_rejection(reason: String) -> void:
	_rejections.append(reason)


func _on_opponent_left() -> void:
	_opponent_left = true


func _on_match_ended(_result: Dictionary) -> void:
	_match_ended = true


func _on_lobby_changed(_info: Dictionary) -> void:
	if _match_ended:
		_guest_left = true


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
	print("NET FAIL host :: %s" % reason)
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
