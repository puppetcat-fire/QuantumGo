## Headless smoke test for the application shell.
##
## Run:
##   godot --headless --path <project> --script res://tests/ui_shell/smoke.gd
##
## Walks every screen, drives the real match lifecycle through `Session`, checks
## that a finished match is recorded exactly once, checks that settings survive a
## save/reload round trip, and exercises the two fallbacks (missing match scene,
## standalone result dialog). Exits 0 only when every check passes.
##
## Autoloads are fetched as nodes instead of by identifier: the `--script` main
## loop is compiled before autoload globals are registered, so `Settings.foo`
## would not compile here even though it does in every scene script.
extends SceneTree

const SHELL_SCENE := "res://src/ui/shell/main.tscn"
const MATCH_SCENE := "res://src/ui/match/match.tscn"
const ENET_TRANSPORT := "res://src/net/qg_enet_transport.gd"
const SCREEN_IDS := ["menu", "lobby", "leaderboard", "rules", "settings"]
const MENU_BUTTONS := ["单机双人", "联机对战", "排行榜", "规则", "设置", "退出游戏"]

var failures: int = 0
var checks: int = 0
var shell: Node = null
var _settings: Node = null
var _leaderboard: Node = null
var _session: Node = null
var _settings_snapshot: Dictionary = {}
var _players_snapshot: Dictionary = {}
var _history_snapshot: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_settings = root.get_node_or_null("Settings")
	_leaderboard = root.get_node_or_null("Leaderboard")
	_session = root.get_node_or_null("Session")
	_check(_settings != null, "Settings autoload 存在")
	_check(_leaderboard != null, "Leaderboard autoload 存在")
	_check(_session != null, "Session autoload 存在")
	var sfx := root.get_node_or_null("Sfx")
	_check(sfx != null, "Sfx autoload 存在")
	if sfx != null:
		_check(bool(sfx.call("is_music_available")), "背景音乐资源已加载并可循环")
	if _settings == null or _leaderboard == null or _session == null:
		_finish()
		return
	_snapshot_user_data()
	# Headless has no window; give the router a viewport size so size-dependent
	# layout code is still exercised.
	root.size = Vector2i(1440, 900)

	await _test_load()
	if shell == null:
		_finish()
		return
	await _test_screens()
	await _test_menu_contents()
	await _test_rules_contents()
	await _test_settings_persistence()
	await _test_lobby_validation()
	await _test_local_match_flow()
	await _test_leaderboard_screen()
	await _test_lobby_host_flow()
	await _test_placeholder_fallback()
	await _test_result_dialog_fallback()
	await _test_back_navigation()

	_restore_user_data()
	_finish()


# --------------------------------------------------------------------------
# Checks
# --------------------------------------------------------------------------

func _test_load() -> void:
	var theme_asset := load("res://src/ui/theme/qg_theme.tres") as Theme
	_check(theme_asset != null, "qg_theme.tres 可加载（由 generate_theme.gd 生成）")
	if theme_asset != null:
		_check(theme_asset.has_stylebox("normal", "Button"), "qg_theme.tres 含按钮样式")
		_check(theme_asset.default_font != null, "qg_theme.tres 带中文字体")
	var packed: PackedScene = load(SHELL_SCENE)
	_check(packed != null, "main.tscn loads as a PackedScene")
	if packed == null:
		return
	shell = packed.instantiate()
	_check(shell != null, "main.tscn instantiates")
	if shell == null:
		return
	root.add_child(shell)
	await process_frame
	await process_frame
	_check(shell.get("theme") != null, "shell applies the shared Theme")
	_check(shell.has_method("show_screen"), "shell exposes the screen router")
	_check(shell.current_screen() == "menu", "router starts on 主菜单")


func _test_screens() -> void:
	for screen_id in SCREEN_IDS:
		shell.show_screen(screen_id)
		await process_frame
		var screen: Control = shell.screen(screen_id)
		_check(screen != null and screen.visible, "%s 屏幕可见" % screen_id)
		_check(shell.current_screen() == screen_id, "router current == %s" % screen_id)
		if root.size.x > 0 and screen != null:
			_check(screen.size.x >= 1000 and screen.size.y >= 700,
				"%s 铺满 1440x900 视口 (%s)" % [screen_id, str(screen.size)])


func _test_menu_contents() -> void:
	shell.show_screen("menu")
	await process_frame
	var menu: Control = shell.screen("menu")
	var texts: Array = []
	_collect_button_texts(menu, texts)
	for expected in MENU_BUTTONS:
		_check(texts.has(expected), "主菜单有按钮「%s」" % expected)
	_check(not _find_label_text(menu, "量子围棋").is_empty(), "主菜单显示标题 量子围棋")
	# The footer only prefixes the name when it differs from the shipped default
	# ("玩家" / "Player"), so give the profile a distinctive one and refresh.
	_settings.set("player_name", "冒烟玩家")
	shell.show_screen("menu")
	await process_frame
	menu = shell.screen("menu")
	var has_player := false
	for line in _collect_label_texts(menu):
		if String(line).contains("玩家：") and String(line).contains("冒烟玩家"):
			has_player = true
			break
	_check(has_player, "主菜单页脚显示玩家名称")


func _test_rules_contents() -> void:
	shell.show_screen("rules")
	await process_frame
	var rules: Control = shell.screen("rules")
	_check(not _find_label_text(rules, "6 个宇宙").is_empty(), "规则页写明一局最多 6 个宇宙")
	_check(not _find_label_text(rules, "8%").is_empty(), "规则页写明权重低于 8% 不能分裂")
	_check(not _find_label_text(rules, "虚子").is_empty(), "规则页解释虚子")
	_check(not _find_label_text(rules, "坍缩").is_empty(), "规则页解释坍缩")


func _test_settings_persistence() -> void:
	shell.show_screen("settings")
	await process_frame
	var settings_screen: Control = shell.screen("settings")
	var name_edit := _find_line_edit(settings_screen, "你的名字")
	_check(name_edit != null, "设置页有玩家名称输入框")
	if name_edit == null:
		return
	name_edit.text = "冒烟测试玩家"
	settings_screen.call("_on_save_pressed")
	await process_frame
	_check(String(_settings.get("player_name")) == "冒烟测试玩家", "保存后 Settings.player_name 更新")
	_settings.set("player_name", "占位")
	_settings.call("load_settings")
	_check(String(_settings.get("player_name")) == "冒烟测试玩家", "Settings.load_settings() 读回已保存的名称")
	var config := ConfigFile.new()
	var loaded := config.load("user://settings.cfg")
	_check(loaded == OK, "settings.cfg 已写入")
	if loaded == OK:
		_check(String(config.get_value("game", "player_name", "")) == "冒烟测试玩家",
			"settings.cfg 内含玩家名称")
	_check(not _find_label_text(settings_screen, "已保存").is_empty(), "保存后有「已保存」反馈")

	# Audio knobs: music toggle and music volume must exist and persist.
	_check(not _find_label_text(settings_screen, "背景音乐").is_empty(), "设置页有背景音乐开关")
	_check(not _find_label_text(settings_screen, "音乐音量").is_empty(), "设置页有音乐音量滑杆")
	var toggles := _find_toggles(settings_screen)
	_check(toggles.size() == 2, "设置页有两个开关（坐标 / 音乐）")
	if toggles.size() >= 2:
		var music_toggle: Control = toggles[toggles.size() - 1]
		music_toggle.call("set_on", false)
		settings_screen.call("_on_save_pressed")
		await process_frame
		_check(not bool(_settings.get("music_enabled")), "关闭背景音乐被保存")
		var config_after := ConfigFile.new()
		if config_after.load("user://settings.cfg") == OK:
			_check(config_after.get_value("audio", "music_enabled", true) == false,
				"settings.cfg 內含音乐开关")
		music_toggle.call("set_on", true)
		settings_screen.call("_on_save_pressed")
		await process_frame
		_check(bool(_settings.get("music_enabled")), "重新打开背景音乐被保存")


func _test_lobby_validation() -> void:
	shell.show_screen("lobby")
	await process_frame
	var lobby: Control = shell.screen("lobby")
	var join_button := _find_button(lobby, "加入房间")
	_check(join_button != null, "联机页有「加入房间」按钮")
	var address_edit := _find_line_edit(lobby, "例如")
	_check(address_edit != null, "联机页有地址输入框")
	if join_button == null or address_edit == null:
		return
	address_edit.text = ""
	join_button.emit_signal("pressed")
	await process_frame
	_check(not bool(_session.call("is_online")), "空地址不会发起连接")
	_check(not _find_label_text(lobby, "请填写").is_empty(), "空地址给出可见的错误提示")


func _test_local_match_flow() -> void:
	shell.show_screen("menu")
	await process_frame
	var history_before: int = _leaderboard.get("history").size()
	shell.start_local_match()
	await process_frame
	await process_frame
	_check(bool(_session.get("started")), "单机对局开始后 Session.started 为真")
	_check(shell.is_in_match(), "shell 进入对局状态")
	_check(not shell.get_node("Screens").visible, "进入对局后隐藏菜单层")
	_check(shell.get_node("MatchLayer").visible, "对局层可见")
	_check(shell.get_node("MatchLayer").get_child_count() == 1, "对局层挂载了一个场景")
	var match_node: Node = shell.get_node("MatchLayer").get_child(0)
	# The match scene is owned by another module and may not be loadable yet. The
	# shell must still finish the match correctly, so the expected presentation is
	# chosen from what actually got mounted instead of assuming.
	var real_match: bool = match_node.has_signal("rematch_requested")
	if real_match:
		_check(match_node.has_signal("exit_requested"), "对局场景暴露 exit_requested")
	else:
		_check(not _find_label_text(match_node, "对局界面尚未就绪").is_empty(),
			"对局场景不可用时显示「对局界面尚未就绪」占位")

	# Finish the match for real: resign through the session.
	_session.call("submit_resign")
	await process_frame
	await process_frame
	_check(_leaderboard.get("history").size() == history_before + 1, "对局结束后记入排行榜一次")
	if _leaderboard.get("history").size() == history_before + 1:
		var entry: Dictionary = _leaderboard.get("history")[0]
		_check(String(entry.get("mode", "")) == "local", "结算记录标记为单机对局")
		_check(String(entry.get("black", "")) == "冒烟测试玩家", "结算记录使用玩家名称")
		_check(int(entry.get("board_size", 0)) == int(_settings.get("board_size")),
			"结算记录带棋盘大小")
	var overlay: Node = shell.get_node("Overlay")
	if real_match:
		_check(bool(match_node.call("is_result_visible")) if match_node.has_method("is_result_visible") else true,
			"对局界面显示自己的结算面板")
		_check(overlay.get_child_count() == 0, "shell 不叠加第二个结算弹窗")
	else:
		_check(overlay.get_child_count() == 1, "没有对局界面时由 shell 显示结算弹窗")

	# The same signal must not record a second time.
	_session.emit_signal("match_ended", {"winner": QGTypes.WINNER_BLACK})
	await process_frame
	_check(_leaderboard.get("history").size() == history_before + 1, "重复的 match_ended 不会二次记录")

	# 再来一局: through the match screen's signal, or the shell dialog's button.
	if real_match:
		match_node.emit_signal("rematch_requested")
	else:
		var rematch := _find_button(overlay, "再来一局")
		_check(rematch != null, "结算弹窗有「再来一局」")
		if rematch != null:
			rematch.emit_signal("pressed")
	await process_frame
	await process_frame
	_check(bool(_session.get("started")), "再来一局重新开始对局")
	_check(shell.is_in_match(), "再来一局仍在对局中")
	_check(shell.get_node("MatchLayer").get_child_count() == 1, "再来一局后只有一个对局场景")
	var fresh_game = _session.get("game")
	_check(fresh_game != null and int(fresh_game.move_count) == 0, "再来一局是零手的新对局")
	_check(_leaderboard.get("history").size() == history_before + 1,
		"再来一局本身不新增排行榜记录")

	# 返回主菜单 comes from whichever scene the shell mounted.
	var current_match: Node = shell.get_node("MatchLayer").get_child(0)
	current_match.emit_signal("exit_requested")
	await process_frame
	await process_frame
	_check(not shell.is_in_match(), "返回后离开对局状态")
	_check(not bool(_session.get("started")), "返回后 Session.leave() 已调用")
	_check(not shell.get_node("MatchLayer").visible, "返回后对局层隐藏")
	_check(shell.get_node("Screens").visible, "返回后菜单层恢复")
	_check(shell.current_screen() == "menu", "单机对局返回主菜单")


func _test_leaderboard_screen() -> void:
	shell.show_screen("leaderboard")
	await process_frame
	var leaderboard: Control = shell.screen("leaderboard")
	var has_player := false
	for line in _collect_label_texts(leaderboard):
		if String(line).contains("冒烟测试玩家"):
			has_player = true
			break
	_check(has_player, "排行榜出现刚打完的玩家")
	_check(not _find_label_text(leaderboard, "Steam").is_empty(), "排行榜说明在线排名会接入 Steam")


func _test_lobby_host_flow() -> void:
	if not ResourceLoader.exists(ENET_TRANSPORT):
		print("  SKIP 房主流程：ENet 传输尚未就位 (%s)" % ENET_TRANSPORT)
		return
	shell.show_screen("lobby")
	await process_frame
	var result: Dictionary = _session.call("host_match", 5, "冒烟房主", 27831)
	_check(bool(result.get("ok", false)), "可以创建房间（端口 27831）")
	await process_frame
	var lobby: Control = shell.screen("lobby")
	if bool(result.get("ok", false)):
		var shown := false
		for address in IP.get_local_addresses():
			var text := String(address)
			if text.contains(":"):
				continue
			if not _find_label_text(lobby, text).is_empty():
				shown = true
				break
		_check(shown, "房间界面显示本机 IP 地址")
		_check(not _find_label_text(lobby, "房间已创建").is_empty(), "房间界面显示等待状态")
	_session.call("leave")
	await process_frame
	_check(not bool(_session.call("is_online")), "leave() 关闭房间")


func _test_placeholder_fallback() -> void:
	var script: GDScript = load("res://src/ui/shell/match_placeholder.gd")
	_check(script != null, "占位场景脚本可加载")
	if script == null:
		return
	var placeholder: Control = script.new()
	var exit_count := [0]
	placeholder.connect("exit_requested", func() -> void: exit_count[0] += 1)
	root.add_child(placeholder)
	await process_frame
	_check(not _find_label_text(placeholder, "对局界面尚未就绪").is_empty(),
		"缺少对局场景时显示「对局界面尚未就绪」占位")
	var back := _find_button(placeholder, "返回主菜单")
	_check(back != null, "占位页有返回按钮")
	if back != null:
		back.emit_signal("pressed")
		await process_frame
	_check(exit_count[0] == 1, "占位页返回按钮发出 exit_requested")
	root.remove_child(placeholder)
	placeholder.queue_free()


func _test_result_dialog_fallback() -> void:
	var script: GDScript = load("res://src/ui/shell/result_view.gd")
	_check(script != null, "结算弹窗脚本可加载")
	if script == null:
		return
	var view: Control = script.new()
	var rematch_count := [0]
	var menu_count := [0]
	view.connect("rematch_pressed", func() -> void: rematch_count[0] += 1)
	view.connect("menu_pressed", func() -> void: menu_count[0] += 1)
	view.call("setup",
		{"winner": QGTypes.WINNER_BLACK, "black": 120, "white": 96,
			"universes": [{"id": 0}, {"id": 1}], "moves": 42, "board_size": 9},
		{QGTypes.BLACK: "甲玩家", QGTypes.WHITE: "乙玩家"}, {"rating_delta": 12})
	root.add_child(view)
	await process_frame
	_check(not _find_label_text(view, "黑方胜").is_empty(), "结算弹窗写出胜方")
	_check(not _find_label_text(view, "甲玩家").is_empty(), "结算弹窗写出双方名称")
	_check(not _find_label_text(view, "已记入本地排行榜").is_empty(), "结算弹窗标注已记入排行榜")
	var rematch := _find_button(view, "再来一局")
	var menu_button := _find_button(view, "返回主菜单")
	_check(rematch != null and menu_button != null, "结算弹窗有两个出口按钮")
	if rematch != null:
		rematch.emit_signal("pressed")
		await process_frame
	_check(rematch_count[0] == 1, "再来一局按钮发出 rematch_pressed")
	if menu_button != null:
		menu_button.emit_signal("pressed")
		await process_frame
	_check(menu_count[0] == 1, "返回主菜单按钮发出 menu_pressed")
	root.remove_child(view)
	view.queue_free()


func _test_back_navigation() -> void:
	shell.show_screen("rules")
	await process_frame
	var rules: Control = shell.screen("rules")
	var back := _find_button(rules, "返回")
	_check(back != null, "规则页有返回按钮")
	if back != null:
		back.emit_signal("pressed")
		await process_frame
	_check(shell.current_screen() == "menu", "返回按钮回到主菜单")


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

func _check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("  PASS  ", message)
	else:
		failures += 1
		printerr("  FAIL  ", message)


func _finish() -> void:
	print("")
	print("UI shell smoke: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _snapshot_user_data() -> void:
	_settings_snapshot = {
		"board_size": _settings.get("board_size"),
		"player_name": _settings.get("player_name"),
		"server_port": _settings.get("server_port"),
		"last_address": _settings.get("last_address"),
		"master_volume": _settings.get("master_volume"),
		"show_coordinates": _settings.get("show_coordinates"),
		"show_phantom": _settings.get("show_phantom"),
		"animation_speed": _settings.get("animation_speed"),
	}
	_players_snapshot = _leaderboard.get("players").duplicate(true)
	_history_snapshot = _leaderboard.get("history").duplicate(true)


func _restore_user_data() -> void:
	for key in _settings_snapshot:
		_settings.set(key, _settings_snapshot[key])
	_settings.call("save_settings")
	_leaderboard.set("players", _players_snapshot)
	var history: Array = _leaderboard.get("history")
	history.assign(_history_snapshot)
	_leaderboard.call("save_data")


func _collect_button_texts(node: Node, out: Array) -> void:
	if node is Button:
		out.append(String(node.text))
	for child in node.get_children():
		_collect_button_texts(child, out)


func _collect_label_texts(node: Node) -> Array:
	var out: Array = []
	if node is Label:
		out.append(String(node.text))
	for child in node.get_children():
		out.append_array(_collect_label_texts(child))
	return out


func _find_button(node: Node, text: String) -> Button:
	if node == null:
		return null
	if node is Button and String(node.text).contains(text):
		return node
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func _find_label_text(node: Node, text: String) -> String:
	if node is Label and String(node.text).contains(text):
		return String(node.text)
	for child in node.get_children():
		var found := _find_label_text(child, text)
		if not found.is_empty():
			return found
	return ""


func _find_line_edit(node: Node, placeholder_marker: String = "") -> LineEdit:
	if node is LineEdit:
		if placeholder_marker.is_empty() or String(node.placeholder_text).contains(placeholder_marker):
			return node
	for child in node.get_children():
		var found := _find_line_edit(child, placeholder_marker)
		if found != null:
			return found
	return null


## Every QGToggle under `node`, in tree order. Used to drive the settings
## switches without reaching into private fields by index.
func _find_toggles(node: Node) -> Array[Control]:
	var out: Array[Control] = []
	var script: Script = node.get_script()
	if script != null and String(script.resource_path).ends_with("widgets/toggle.gd"):
		out.append(node as Control)
	for child in node.get_children():
		out.append_array(_find_toggles(child))
	return out
