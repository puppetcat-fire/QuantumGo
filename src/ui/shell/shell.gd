## The application shell: owns the screen router, the match layer, the result
## dialog and the toast line. `res://src/ui/shell/main.tscn` is this node.
##
## Responsibilities that must not leak into screens:
##   * exactly one place calls `Session.leave()`;
##   * exactly one place instantiates the match scene and connects its signals;
##   * exactly one place records a finished match in the leaderboard, exactly once.
class_name QGShell
extends Control

const UI := preload("res://src/ui/shell/ui_kit.gd")
const TH := preload("res://src/ui/theme/qg_theme.gd")
const Backdrop := preload("res://src/ui/shell/backdrop.gd")
const MatchPlaceholder := preload("res://src/ui/shell/match_placeholder.gd")
const ResultView := preload("res://src/ui/shell/result_view.gd")

const SCREEN_MENU := "menu"
const SCREEN_LOBBY := "lobby"
const SCREEN_LEADERBOARD := "leaderboard"
const SCREEN_RULES := "rules"
const SCREEN_SETTINGS := "settings"
const SCREEN_TUTORIAL := "tutorial"
const SCREEN_REPLAY := "replay"

const SCREENS := {
	SCREEN_MENU: preload("res://src/ui/shell/screens/menu_screen.gd"),
	SCREEN_LOBBY: preload("res://src/ui/shell/screens/lobby_screen.gd"),
	SCREEN_LEADERBOARD: preload("res://src/ui/shell/screens/leaderboard_screen.gd"),
	SCREEN_RULES: preload("res://src/ui/shell/screens/rules_screen.gd"),
	SCREEN_SETTINGS: preload("res://src/ui/shell/screens/settings_screen.gd"),
	SCREEN_TUTORIAL: preload("res://src/ui/tutorial/tutorial_screen.gd"),
	SCREEN_REPLAY: preload("res://src/ui/replay/replay_screen.gd"),
}

## How long a client waits for the host to start a requested rematch before it
## gives up and goes back to the lobby instead of sitting on a dead dialog.
const REMATCH_TIMEOUT_MS := 20000

## Built by another module. Loaded dynamically so a missing match scene degrades
## to a readable placeholder instead of breaking the whole application.
const MATCH_SCENE := "res://src/ui/match/match.tscn"

var _screens: Dictionary = {}
var _current: String = ""
var _screen_host: Control = null
var _match_layer: Control = null
var _overlay_layer: Control = null
var _match_node: Node = null
var _result_view: Control = null
var _toast_root: Control = null
var _toast_panel: PanelContainer = null
var _toast_label: Label = null
var _toast_tween: Tween = null
var _in_match: bool = false
var _match_mode: String = "local"
var _result_recorded: bool = false
## True when the mounted match scene presents its own result panel (it exposes
## `rematch_requested`). The shell then records the result and leaves the modal
## to the match screen instead of stacking a second one on top of it.
var _match_handles_result: bool = false
## Set while a client is waiting for the host to answer a rematch request.
var _rematch_deadline_ms: int = 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = TH.build()
	_build_layers()
	_build_screens()
	_build_toast()
	_connect_session()
	show_screen(SCREEN_MENU)


func _process(_delta: float) -> void:
	# The Steam overlay and achievements only work while Steam callbacks are
	# pumped. The shell is the main scene, so it owns this.
	Platform.poll()
	if _rematch_deadline_ms > 0 and Time.get_ticks_msec() >= _rematch_deadline_ms:
		# A client asked for another game and the host never started one.
		_rematch_deadline_ms = 0
		if _in_match:
			_leave_match(SCREEN_LOBBY, "房主没有开始新的一局，已返回大厅")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _in_match and _current != SCREEN_MENU:
		show_screen(SCREEN_MENU)
		get_viewport().set_input_as_handled()


# --------------------------------------------------------------------------
# Public API used by screens
# --------------------------------------------------------------------------

## The screen instance for `screen_id`, or null. Exposed for tests and for future
## tooling that wants to inspect a page without knowing how it was built.
func screen(screen_id: String) -> Control:
	return _screens.get(screen_id, null)


func current_screen() -> String:
	return _current


func is_in_match() -> bool:
	return _in_match


func show_screen(screen_id: String) -> void:
	if not _screens.has(screen_id):
		push_error("QGShell: unknown screen '%s'" % screen_id)
		return
	if _in_match:
		return
	if _current != "" and _current != screen_id and _screens.has(_current):
		_screens[_current].visible = false
		_screens[_current].on_hide()
	for key in _screens:
		if key != screen_id:
			_screens[key].visible = false
	_current = screen_id
	_screens[screen_id].visible = true
	_screens[screen_id].on_show()


func start_local_match() -> void:
	if _in_match:
		return
	Session.start_local(Settings.board_size)


func quit_game() -> void:
	get_tree().quit()


func toast(text: String) -> void:
	if _toast_label == null or text.strip_edges().is_empty():
		return
	_toast_label.text = text
	_toast_panel.visible = true
	_toast_panel.modulate.a = 0.0
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast_panel, "modulate:a", 1.0, 0.14)
	_toast_tween.tween_interval(2.6)
	_toast_tween.tween_property(_toast_panel, "modulate:a", 0.0, 0.34)
	_toast_tween.tween_callback(func() -> void: _toast_panel.visible = false)


# --------------------------------------------------------------------------
# Construction
# --------------------------------------------------------------------------

func _build_layers() -> void:
	var backdrop := Backdrop.new()
	backdrop.name = "Backdrop"
	add_child(backdrop)
	UI.full_rect(backdrop)

	_screen_host = Control.new()
	_screen_host.name = "Screens"
	add_child(_screen_host)
	UI.full_rect(_screen_host)

	_match_layer = Control.new()
	_match_layer.name = "MatchLayer"
	_match_layer.visible = false
	add_child(_match_layer)
	UI.full_rect(_match_layer)

	_overlay_layer = Control.new()
	_overlay_layer.name = "Overlay"
	_overlay_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay_layer)
	UI.full_rect(_overlay_layer)


func _build_screens() -> void:
	for screen_id in SCREENS:
		var script: GDScript = SCREENS[screen_id]
		var screen: Control = script.new()
		screen.name = screen_id.capitalize()
		screen.bind(self)
		screen.visible = false
		_screen_host.add_child(screen)
		_screens[screen_id] = screen


func _build_toast() -> void:
	_toast_root = Control.new()
	_toast_root.name = "Toast"
	_toast_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast_root)
	UI.full_rect(_toast_root)

	# Every node in the toast chain has to ignore the mouse: mouse_filter is not
	# inherited, and this overlay covers the whole screen. A STOP anywhere in it
	# swallows every click in the game (the match screen looked "dead" because of
	# exactly that).
	var margin := UI.margins(0, 0, 0, 36)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_root.add_child(margin)
	UI.full_rect(margin)

	var column := UI.vbox(0)
	column.alignment = BoxContainer.ALIGNMENT_END
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	var row := UI.hbox(0)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(row)

	_toast_panel = PanelContainer.new()
	_toast_panel.theme_type_variation = &"ToastPanel"
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_panel.visible = false
	row.add_child(_toast_panel)
	var inner := UI.hbox(UI.GAP_SM)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_panel.add_child(inner)
	var dot := UI.status_dot(QGPalette.ACCENT, 6)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(dot)
	_toast_label = UI.label("", "BodyLabel")
	_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(_toast_label)


func _connect_session() -> void:
	Session.match_started.connect(_on_match_started)
	Session.match_ended.connect(_on_match_ended)
	Session.lobby_changed.connect(_on_lobby_changed)
	Session.status_changed.connect(_on_status_changed)
	Session.opponent_left.connect(_on_opponent_left)


# --------------------------------------------------------------------------
# Match lifecycle
# --------------------------------------------------------------------------

func _on_match_started(meta: Dictionary) -> void:
	_hide_result()
	_rematch_deadline_ms = 0
	_match_mode = String(meta.get("mode", "local"))
	_result_recorded = false
	_in_match = true
	_screen_host.visible = false
	_screen_host.process_mode = Node.PROCESS_MODE_DISABLED
	_mount_match()


func _mount_match() -> void:
	_teardown_match()
	var node: Node = null
	if ResourceLoader.exists(MATCH_SCENE):
		var packed := load(MATCH_SCENE) as PackedScene
		if packed != null:
			node = packed.instantiate()
	# A scene whose controller script failed to compile loads as a blank Control
	# with none of the contracted signals. Treat that exactly like a missing
	# scene instead of showing an empty board-less screen.
	if node != null and not node.has_signal("exit_requested"):
		push_warning("QGShell: %s is not usable (no exit_requested), using placeholder" % MATCH_SCENE)
		node.free()
		node = null
	if node == null:
		var placeholder := MatchPlaceholder.new()
		placeholder.exit_requested.connect(_on_match_exit_requested)
		node = placeholder
		_match_handles_result = false
	else:
		_match_handles_result = node.has_signal("rematch_requested")
		node.connect("exit_requested", _on_match_exit_requested)
		if node.has_signal("rematch_requested"):
			node.connect("rematch_requested", _on_match_rematch_requested)
		if node.has_signal("replay_requested"):
			node.connect("replay_requested", _on_match_replay_requested)
	_match_node = node
	_match_layer.add_child(node)
	if node is Control:
		UI.full_rect(node)
	_match_layer.visible = true


## The match screen asks for the replay screen. The history is copied before the
## session is torn down, then we leave the match straight into the replay.
func _on_match_replay_requested() -> void:
	var snapshots: Array = []
	for entry in Session.history:
		snapshots.append(entry)
	var replay: Node = _screens.get(SCREEN_REPLAY, null)
	if replay == null:
		return
	if replay.has_method("load_replay"):
		replay.call("load_replay", snapshots)
	_leave_match(SCREEN_REPLAY)


func _teardown_match() -> void:
	_match_layer.visible = false
	if _match_node != null and is_instance_valid(_match_node):
		if _match_node.get_parent() != null:
			_match_node.get_parent().remove_child(_match_node)
		_match_node.queue_free()
	_match_node = null


func _on_match_exit_requested() -> void:
	_leave_match()


func _on_match_rematch_requested() -> void:
	_on_result_rematch()


func _on_match_ended(result: Dictionary) -> void:
	if not _in_match or _result_recorded:
		return
	_result_recorded = true
	var names := _names_for_record(result)
	var entry := _record_result(result, names)
	if not _match_handles_result:
		# Only the shell's placeholder lacks a result panel of its own; a real
		# match scene shows one, and two modals at once would be a bug.
		_show_result(result, names, entry)


func _record_result(result: Dictionary, names: Dictionary) -> Dictionary:
	var meta: Dictionary = result.get("meta", {})
	if meta.is_empty():
		meta = Session.match_meta
	var board_size := int(result.get("board_size", meta.get("board_size", Settings.board_size)))
	var entry: Dictionary = Leaderboard.record_match(
		names,
		int(result.get("winner", QGTypes.WINNER_NONE)),
		board_size,
		int(result.get("moves", 0)),
		_match_mode)
	if _screens.has(SCREEN_LEADERBOARD):
		_screens[SCREEN_LEADERBOARD].refresh()
	return entry


func _names_for_record(result: Dictionary) -> Dictionary:
	var meta: Dictionary = result.get("meta", {})
	if meta.is_empty():
		meta = Session.match_meta
	if _match_mode == "local":
		# Hot-seat: the same profile plays both colours; the leaderboard keeps
		# them apart with a per-colour suffix.
		var player := Settings.player_name.strip_edges()
		if player.is_empty():
			player = "玩家"
		return {QGTypes.BLACK: player, QGTypes.WHITE: player}
	var names: Dictionary = meta.get("names", {})
	var colours: Dictionary = meta.get("colours", {})
	var mapped := {}
	for peer_id in colours.keys():
		mapped[int(colours[peer_id])] = String(names.get(peer_id, "玩家"))
	if mapped.has(QGTypes.BLACK) and mapped.has(QGTypes.WHITE):
		return mapped
	var black := String(names.get(QGTypes.BLACK, "黑方")).strip_edges()
	var white := String(names.get(QGTypes.WHITE, "白方")).strip_edges()
	return {
		QGTypes.BLACK: black if not black.is_empty() else "黑方",
		QGTypes.WHITE: white if not white.is_empty() else "白方",
	}


func _show_result(result: Dictionary, names: Dictionary, entry: Dictionary) -> void:
	if _result_view != null:
		return
	var view := ResultView.new()
	view.setup(result, names, entry)
	view.rematch_pressed.connect(_on_result_rematch)
	view.menu_pressed.connect(_on_result_menu)
	_overlay_layer.add_child(view)
	UI.full_rect(view)
	_result_view = view


func _hide_result() -> void:
	if _result_view != null and is_instance_valid(_result_view):
		if _result_view.get_parent() != null:
			_result_view.get_parent().remove_child(_result_view)
		_result_view.queue_free()
	_result_view = null


## Starts the next game with the same seats. The session owns the difference
## between hot-seat (restart locally), host (reset + rebroadcast start) and client
## (ask the host and wait). Only a refused/missing peer falls back to the lobby.
func _on_result_rematch() -> void:
	if not _in_match:
		return
	var result: Dictionary = Session.rematch()
	if not bool(result.get("ok", false)):
		var online := _match_mode == "online"
		_leave_match(SCREEN_LOBBY if online else SCREEN_MENU,
			"对手已离开，无法再来一局" if online else "无法开始新对局")
		return
	if bool(result.get("pending", false)):
		# Client: the host has the request and will broadcast the new start.
		_hide_result()
		toast("已请求再来一局，等待房主…")
		_rematch_deadline_ms = Time.get_ticks_msec() + REMATCH_TIMEOUT_MS
		return
	_rematch_deadline_ms = 0
	toast("新的一局开始")


func _on_result_menu() -> void:
	_leave_match(SCREEN_MENU)


## Tears down the match layer, leaves the session and returns to a screen.
## `target` overrides the default (menu for local, lobby for online).
func _leave_match(target: String = "", message: String = "") -> void:
	if not _in_match:
		return
	var was_online := _match_mode == "online"
	_rematch_deadline_ms = 0
	_teardown_match()
	_hide_result()
	_in_match = false
	_screen_host.visible = true
	_screen_host.process_mode = Node.PROCESS_MODE_INHERIT
	Session.leave()
	if _screens.has(SCREEN_LEADERBOARD):
		_screens[SCREEN_LEADERBOARD].refresh()
	var destination := target
	if destination.is_empty():
		destination = SCREEN_LOBBY if was_online else SCREEN_MENU
	if not message.is_empty():
		toast(message)
	_current = ""
	show_screen(destination)


# --------------------------------------------------------------------------
# Session signal forwarding
# --------------------------------------------------------------------------

func _on_lobby_changed(info: Dictionary) -> void:
	if _screens.has(SCREEN_LOBBY):
		_screens[SCREEN_LOBBY].set_lobby(info)


func _on_status_changed(text: String) -> void:
	if _screens.has(SCREEN_LOBBY):
		_screens[SCREEN_LOBBY].set_status(text)
	if _current != SCREEN_LOBBY or _in_match:
		toast(text)


func _on_opponent_left() -> void:
	if _in_match:
		_leave_match(SCREEN_LOBBY, "对手已离开对局")
	else:
		toast("对手已离开")
