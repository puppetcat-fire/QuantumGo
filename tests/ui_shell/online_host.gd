## End-to-end online flow, host side.
##
## Run through `tests/ui_shell/run_online_flow.ps1`, which starts this process and
## `online_client.gd` together. Drives the real shell:
##   联机对战 → 填端口 → 创建房间 → 等对手加入 → 对局 → 认输 → 结算记录 → 退出
## and asserts the state machine afterwards: one leaderboard record, session left.
extends SceneTree

const SHELL_SCENE := "res://src/ui/shell/main.tscn"
const PROBE := preload("res://tests/ui_shell/online_probe.gd")
const PORT := 27832
const HOST_NAME := "房主"
const GUEST_NAME := "客人"

var checks: int = 0
var failures: int = 0
var shell: Node = null
var _session: Node = null
var _leaderboard: Node = null
var _settings: Node = null
var _leaderboard_snapshot: Dictionary = {}
var _settings_snapshot: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1440, 900)
	_session = root.get_node_or_null("Session")
	_leaderboard = root.get_node_or_null("Leaderboard")
	_settings = root.get_node_or_null("Settings")
	if _session == null or _leaderboard == null or _settings == null:
		_fail("autoload 缺失")
		_finish()
		return
	_leaderboard_snapshot = PROBE.snapshot_leaderboard(_leaderboard)
	_settings_snapshot = PROBE.snapshot_settings(_settings)
	_leaderboard.call("reset")
	# The room creator's profile name is what the other peer and the leaderboard
	# will see; set it before the shell reads it into the lobby.
	_settings.set("player_name", HOST_NAME)

	var packed: PackedScene = load(SHELL_SCENE)
	shell = packed.instantiate()
	root.add_child(shell)
	await _frames(3)
	shell.show_screen("lobby")
	await _frames(2)
	var lobby: Control = shell.screen("lobby")

	# Port field is editable and the value it holds is the port we listen on.
	var port_fields := PROBE.find_number_fields(lobby)
	_check(port_fields.size() >= 2, "联机页有两个端口输入框（创建 / 加入）")
	if port_fields.is_empty():
		_finish()
		return
	port_fields[0].call("set_value", PORT, false)
	_check(int(port_fields[0].call("get_value")) == PORT, "端口输入框可编辑")

	var create_button := PROBE.find_button(lobby, "创建房间")
	_check(create_button != null, "联机页有「创建房间」按钮")
	if create_button == null:
		_finish()
		return
	create_button.emit_signal("pressed")
	await _frames(3)

	_check(bool(_session.call("is_online")), "创建房间后 Session 在线")
	_check(int(_session.get("local_port")) == PORT, "房间使用输入框里的端口 %d" % PORT)
	var shown_ip := ""
	for address in PROBE.local_ipv4():
		if not PROBE.find_label_text(lobby, address).is_empty():
			shown_ip = address
			break
	_check(not shown_ip.is_empty(), "等待房间显示本机真实局域网 IP（%s）" % shown_ip)
	_check(not PROBE.find_label_text(lobby, str(PORT)).is_empty(), "等待房间显示端口")

	# Wait for the guest; the session starts the match as soon as it joins.
	var started := await _wait_until(func() -> bool: return bool(_session.get("started")), 40.0)
	_check(started, "对手加入后自动开局")
	if not started:
		_finish()
		return
	await _frames(3)
	_check(shell.is_in_match(), "shell 进入对局状态")
	_check(shell.get_node("MatchLayer").get_child_count() == 1, "对局场景挂在 MatchLayer 上")

	# 跨进程落子：房主先下一子（黑），客方再下一子（白）。房主收到远端 cmd 后必须
	# 通知本机 UI 刷新，否则两边盘面不一致、各自以为轮到对方走（联机死锁的形态）。
	var state_signals := [0]
	var counter := func() -> void: state_signals[0] += 1
	_session.connect("state_changed", counter)
	var host_move: Dictionary = _session.call("submit_move", 0, 2 * 9 + 2)
	_check(bool(host_move.get("ok", false)), "房主落子被受理")
	var guest_moved := await _wait_until(func() -> bool:
		var game = _session.get("game")
		return game != null and int(game.move_count) >= 2, 25.0)
	_check(guest_moved, "房主收到客方的落子")
	_check(state_signals[0] >= 2,
		"远端落子也通知房主界面刷新（state_changed 计数 %d）" % state_signals[0])
	if _session.is_connected("state_changed", counter):
		_session.disconnect("state_changed", counter)

	# Host is black; resigning hands the win to white (the guest).
	await _sleep(0.6)
	_session.call("submit_resign")
	var recorded := await _wait_until(
		func() -> bool: return _leaderboard.get("history").size() >= 1, 15.0)
	_check(recorded, "对局结束后记入排行榜")
	await _frames(2)
	_check(_leaderboard.get("history").size() == 1, "排行榜恰好记录一次")
	if _leaderboard.get("history").size() == 1:
		var entry: Dictionary = _leaderboard.get("history")[0]
		_check(String(entry.get("mode", "")) == "online", "记录标记为联机对局")
		_check(int(entry.get("winner", -1)) == QGTypes.WINNER_WHITE, "白方（客人）获胜")
		_check(String(entry.get("black", "")) == HOST_NAME, "记录里黑方是房主")
		_check(String(entry.get("white", "")) == GUEST_NAME, "记录里白方是客人")

	# The same signal must not record twice.
	_session.emit_signal("match_ended", {"winner": QGTypes.WINNER_WHITE})
	await _frames(2)
	_check(_leaderboard.get("history").size() == 1, "重复 match_ended 不会二次记录")

	# 再来一局: `Session.rematch()` resets the authoritative game and rebroadcasts
	# start. Both peers must come back with a fresh zero-move game on screen.
	await _sleep(1.0)
	shell.get_node("MatchLayer").get_child(0).emit_signal("rematch_requested")
	var rematched := await _wait_until(func() -> bool:
		var game = _session.get("game")
		return bool(_session.get("started")) and game != null and int(game.move_count) == 0 \
			and shell.is_in_match() and shell.get_node("MatchLayer").visible, 15.0)
	_check(rematched, "再来一局后拿到零手的新对局，对局层可见")
	_check(_leaderboard.get("history").size() == 1, "再来一局本身不新增排行榜记录")
	await _frames(3)

	# Finish the second game too: each match must record exactly once.
	if rematched:
		await _sleep(0.6)
		_session.call("submit_resign")
		var second := await _wait_until(
			func() -> bool: return _leaderboard.get("history").size() >= 2, 15.0)
		_check(second, "第二局结束后再记录一次")
		_check(_leaderboard.get("history").size() == 2, "两局各记录一次")

	# The guest asks for another game: {t:"rematch"} reaches the host, which
	# resets the game and broadcasts a new start to both peers.
	await _sleep(1.0)
	var guest_rematch := await _wait_until(func() -> bool:
		var game = _session.get("game")
		return bool(_session.get("started")) and game != null and int(game.move_count) == 0 \
			and shell.is_in_match() and shell.get_node("MatchLayer").visible, 25.0)
	_check(guest_rematch, "客方请求再来一局时房主自动开局（零手）")
	_check(_leaderboard.get("history").size() == 2, "客方请求的再来一局不新增排行榜记录")

	# Leaving the match must tear the session down; no stale transport survives.
	if shell.is_in_match():
		shell.get_node("MatchLayer").get_child(0).emit_signal("exit_requested")
	await _wait_until(func() -> bool: return not shell.is_in_match(), 5.0)
	await _frames(2)
	_check(not shell.is_in_match(), "退出对局后离开对局状态")
	_check(not bool(_session.call("is_online")), "退出后 Session.leave() 已调用")
	_check(_session.get("game") == null, "退出后没有残留对局数据")
	_check(int(_session.get("mode")) == QGSession.Mode.LOCAL, "退出后回到本地模式")
	_check(not shell.get_node("MatchLayer").visible, "对局层已隐藏")
	_check(shell.get_node("Screens").visible, "菜单层恢复可见")

	# Back at the menu, the leaderboard shows the game that just finished.
	shell.show_screen("menu")
	await _frames(2)
	shell.show_screen("leaderboard")
	await _frames(3)
	var leaderboard_screen: Control = shell.screen("leaderboard")
	_check(not PROBE.find_label_text(leaderboard_screen, HOST_NAME).is_empty(), "排行榜显示房主")
	_check(not PROBE.find_label_text(leaderboard_screen, GUEST_NAME).is_empty(), "排行榜显示客人")
	_check(not PROBE.find_label_text(leaderboard_screen, "联机").is_empty(), "最近对局标记为联机")

	_finish()


# --------------------------------------------------------------------------

func _check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("  HOST PASS  ", message)
	else:
		failures += 1
		printerr("  HOST FAIL  ", message)


func _fail(message: String) -> void:
	checks += 1
	failures += 1
	printerr("  HOST FAIL  ", message)


func _finish() -> void:
	_session.call("leave")
	if not _leaderboard_snapshot.is_empty():
		PROBE.restore_leaderboard(_leaderboard, _leaderboard_snapshot)
	if not _settings_snapshot.is_empty():
		PROBE.restore_settings(_settings, _settings_snapshot)
	print("HOST SUMMARY %d checks %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _frames(count: int) -> void:
	for _index in range(maxi(1, count)):
		await process_frame


func _sleep(seconds: float) -> void:
	await create_timer(seconds).timeout


func _wait_until(predicate: Callable, timeout_seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if bool(predicate.call()):
			return true
		await process_frame
	return false
