## End-to-end online flow, guest side.
##
## Started after `online_host.gd` by `run_online_flow.ps1`. Drives the real shell:
##   联机对战 → 填地址/端口 → 加入房间 → 对局 → 对手认输 → 结算 → 退出
## It retries the join while the host is still booting, so the runner does not
## depend on precise start ordering.
extends SceneTree

const SHELL_SCENE := "res://src/ui/shell/main.tscn"
const PROBE := preload("res://tests/ui_shell/online_probe.gd")
const PORT := 27832
const ADDRESS := "127.0.0.1"
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
	_settings.set("player_name", GUEST_NAME)
	_settings.set("last_address", "")

	var packed: PackedScene = load(SHELL_SCENE)
	shell = packed.instantiate()
	root.add_child(shell)
	await _frames(3)
	shell.show_screen("lobby")
	await _frames(2)
	var lobby: Control = shell.screen("lobby")

	var address_edit := PROBE.find_line_edit(lobby, "例如")
	_check(address_edit != null, "联机页有 IP 地址输入框")
	var port_fields := PROBE.find_number_fields(lobby)
	_check(port_fields.size() >= 2, "联机页有两个端口输入框")
	var join_button := PROBE.find_button(lobby, "加入房间")
	_check(join_button != null, "联机页有「加入房间」按钮")
	if address_edit == null or port_fields.size() < 2 or join_button == null:
		_finish()
		return

	address_edit.text = ADDRESS
	port_fields[1].call("set_value", PORT, false)
	_check(int(port_fields[1].call("get_value")) == PORT, "加入端口可编辑")
	join_button.emit_signal("pressed")
	await _frames(3)
	_check(bool(_session.call("is_online")), "点击加入后进入联机模式")

	# The host can still be booting; retry until the host starts the match.
	var started := await _wait_for_start(35.0)
	_check(started, "成功加入房间并开局")
	if not started:
		_finish()
		return
	await _frames(3)
	_check(shell.is_in_match(), "shell 进入对局状态")
	_check(shell.get_node("MatchLayer").get_child_count() == 1, "对局场景挂在 MatchLayer 上")
	_check(int(_session.get("my_color")) == QGTypes.WHITE, "客方执白")

	# 等房主先落一子（黑），再由客方落一子（白）——覆盖"远端 cmd"这条只有真实双开
	# 才会走到的路径。
	var host_moved := await _wait_until(func() -> bool:
		var game = _session.get("game")
		return game != null and int(game.move_count) >= 1, 25.0)
	_check(host_moved, "客方收到房主的落子")
	if host_moved:
		var guest_move: Dictionary = _session.call("submit_move", 0, 4 * 9 + 4)
		_check(bool(guest_move.get("ok", false)), "客方落子被受理")
		var applied := await _wait_until(func() -> bool:
			var game = _session.get("game")
			return game != null and int(game.move_count) >= 2, 20.0)
		_check(applied, "房主应用客方落子后双方盘面一致")

	var finished := await _wait_until(
		func() -> bool: return _leaderboard.get("history").size() >= 1, 25.0)
	_check(finished, "对手认输后本机也收到结算")
	await _frames(2)
	_check(_leaderboard.get("history").size() == 1, "排行榜恰好记录一次")
	if _leaderboard.get("history").size() == 1:
		var entry: Dictionary = _leaderboard.get("history")[0]
		_check(String(entry.get("mode", "")) == "online", "记录标记为联机对局")
		_check(int(entry.get("winner", -1)) == QGTypes.WINNER_WHITE, "白方（客人）获胜")
		_check(String(entry.get("black", "")) == HOST_NAME, "记录里黑方是房主")
		_check(String(entry.get("white", "")) == GUEST_NAME, "记录里白方是客人")

	_session.emit_signal("match_ended", {"winner": QGTypes.WINNER_WHITE})
	await _frames(2)
	_check(_leaderboard.get("history").size() == 1, "重复 match_ended 不会二次记录")

	# The host asks for another game; `Session.rematch()` on the client sends
	# {t:"rematch"} and the host's new start arrives through match_started.
	var rematched := await _wait_until(func() -> bool:
		var game = _session.get("game")
		return bool(_session.get("started")) and game != null and int(game.move_count) == 0 \
			and shell.is_in_match() and shell.get_node("MatchLayer").visible, 30.0)
	_check(rematched, "房主开启再来一局，客方拿到零手新对局且对局层可见")
	_check(_leaderboard.get("history").size() == 1, "再来一局本身不新增排行榜记录")
	await _frames(3)

	if rematched:
		var second := await _wait_until(
			func() -> bool: return _leaderboard.get("history").size() >= 2, 20.0)
		_check(second, "第二局结束也记录一次")
		_check(_leaderboard.get("history").size() == 2, "两局各记录一次")

	# 客方主动发起再来一局: Session.rematch() sends {t:"rematch"} and waits for
	# the host's new start packet (pending → match_started).
	await _sleep(1.0)
	if shell.is_in_match():
		shell.get_node("MatchLayer").get_child(0).emit_signal("rematch_requested")
	var guest_rematch := await _wait_until(func() -> bool:
		var game = _session.get("game")
		return bool(_session.get("started")) and game != null and int(game.move_count) == 0 \
			and shell.is_in_match() and shell.get_node("MatchLayer").visible, 25.0)
	_check(guest_rematch, "客方请求再来一局后拿到零手新对局")
	_check(_leaderboard.get("history").size() == 2, "客方请求的再来一局不新增排行榜记录")

	if shell.is_in_match():
		shell.get_node("MatchLayer").get_child(0).emit_signal("exit_requested")
	await _wait_until(func() -> bool: return not shell.is_in_match(), 5.0)
	await _frames(2)
	_check(not shell.is_in_match(), "退出对局后离开对局状态")
	_check(not bool(_session.call("is_online")), "退出后 Session.leave() 已调用")
	_check(_session.get("game") == null, "退出后没有残留对局数据")
	_check(int(_session.get("mode")) == QGSession.Mode.LOCAL, "退出后回到本地模式")

	shell.show_screen("menu")
	await _frames(2)
	shell.show_screen("leaderboard")
	await _frames(3)
	var leaderboard_screen: Control = shell.screen("leaderboard")
	_check(not PROBE.find_label_text(leaderboard_screen, HOST_NAME).is_empty(), "客方排行榜显示房主")
	_check(not PROBE.find_label_text(leaderboard_screen, GUEST_NAME).is_empty(), "客方排行榜显示客人")

	_finish()


# --------------------------------------------------------------------------

## Presses 加入房间 once, then retries the session call until the match starts.
func _wait_for_start(timeout_seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	var next_attempt := Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < deadline:
		if bool(_session.get("started")):
			return true
		if Time.get_ticks_msec() >= next_attempt:
			next_attempt = Time.get_ticks_msec() + 2000
			_session.call("join_match", ADDRESS, PORT, GUEST_NAME)
		await process_frame
	return false


func _check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("  CLIENT PASS  ", message)
	else:
		failures += 1
		printerr("  CLIENT FAIL  ", message)


func _fail(message: String) -> void:
	checks += 1
	failures += 1
	printerr("  CLIENT FAIL  ", message)


func _finish() -> void:
	_session.call("leave")
	if not _leaderboard_snapshot.is_empty():
		PROBE.restore_leaderboard(_leaderboard, _leaderboard_snapshot)
	if not _settings_snapshot.is_empty():
		PROBE.restore_settings(_settings, _settings_snapshot)
	print("CLIENT SUMMARY %d checks %d failures" % [checks, failures])
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
