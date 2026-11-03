## Match screen controller.
##
## Owns the presentation of a live match: it subscribes to the `Session`
## autoload, renders every live universe as a board card, and turns player
## gestures into `Session.submit_*` calls. It never mutates the game state
## itself — the session is the only authority, in every mode.
##
## Signals consumed by the shell:
##   exit_requested    — the player wants to leave the match screen
##   rematch_requested — the player wants another game with the same settings
class_name QGMatchScreen
extends Control

signal exit_requested
signal rematch_requested
signal replay_requested

const UIKit := preload("res://src/ui/match/ui_kit.gd")
const HudScript := preload("res://src/ui/match/hud.gd")
const GridScript := preload("res://src/ui/match/universe_grid.gd")
const CardScript := preload("res://src/ui/match/universe_card.gd")
const ResultScript := preload("res://src/ui/match/result_panel.gd")
const ConfirmScript := preload("res://src/ui/match/confirm_overlay.gd")

const CONFIRM_RESIGN := "resign"
const CONFIRM_EXIT := "exit"

const HINT_DEFAULT := "左键落子 · Shift / 量子步 分裂 · Tab 切换宇宙 · P 停一手 · R 认输 · U 悔棋 · Esc 取消量子步"
const HINT_FOCUS := "点击缩略图切换聚焦棋盘 · " + HINT_DEFAULT

var _session = null
var _sfx = null

var _hud = null
var _grid = null
var _result = null
var _confirm = null

var _toast_panel: PanelContainer = null
var _toast_label: Label = null
var _toast_tween: Tween = null
var _footer_hint: Label = null
var _footer_mode: Label = null

var _cards: Dictionary = {}
var _card_ids: Array[int] = []
var _focus_layout := false

var _focus_id := 0
var _quantum_on := false
var _quantum_a := -1
var _quantum_universe := -1
var _confirm_action := ""
var _result_shown := false
var _status_text := ""


func _ready() -> void:
	_session = get_node_or_null("/root/Session")
	_sfx = get_node_or_null("/root/Sfx")
	_build_ui()
	_connect_session()
	_refresh()


# --------------------------------------------------------------------------
# Construction
# --------------------------------------------------------------------------

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = QGPalette.BG_DEEP
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	_hud = HudScript.new()
	column.add_child(_hud)
	_hud.quantum_toggled.connect(_on_quantum_toggled)
	_hud.pass_pressed.connect(request_pass)
	_hud.resign_pressed.connect(request_resign)
	_hud.undo_pressed.connect(request_undo)
	_hud.exit_pressed.connect(request_exit)
	_hud.confirm_score_pressed.connect(request_confirm_score)

	_grid = GridScript.new()
	_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_grid)

	column.add_child(_build_footer())

	_build_toast()

	_result = ResultScript.new()
	add_child(_result)
	_result.rematch_requested.connect(_on_rematch_pressed)
	_result.exit_requested.connect(_on_exit_pressed)
	_result.replay_requested.connect(_on_replay_pressed)

	_confirm = ConfirmScript.new()
	add_child(_confirm)
	_confirm.confirmed.connect(_on_confirm_confirmed)
	_confirm.cancelled.connect(_on_confirm_cancelled)


func _build_footer() -> PanelContainer:
	var footer := PanelContainer.new()
	footer.custom_minimum_size = Vector2(0.0, 34.0)
	footer.add_theme_stylebox_override(
		"panel", UIKit.flat_box(QGPalette.BG_PANEL, 8, QGPalette.BG_PANEL_LIGHT, 1, 14, 5)
	)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	footer.add_child(row)

	var hint := UIKit.make_label(HINT_DEFAULT, 11, QGPalette.TEXT_DIM)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.clip_text = true
	_footer_hint = hint
	row.add_child(hint)

	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 6)
	legend.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var phantom_dot := Panel.new()
	phantom_dot.custom_minimum_size = Vector2(10.0, 10.0)
	phantom_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	phantom_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	phantom_dot.add_theme_stylebox_override(
		"panel", UIKit.flat_box(Color(QGPalette.PHANTOM_TINT, 0.65), 5, QGPalette.VIOLET, 1)
	)
	legend.add_child(phantom_dot)
	legend.add_child(UIKit.make_label("虚子：被提则分支坍缩", 11, QGPalette.TEXT_MUTED))
	row.add_child(legend)

	_footer_mode = UIKit.make_label("", 11, QGPalette.TEXT_DIM)
	row.add_child(_footer_mode)
	return footer


func _build_toast() -> void:
	var toast_row := HBoxContainer.new()
	toast_row.alignment = BoxContainer.ALIGNMENT_CENTER
	toast_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_row.anchor_left = 0.0
	toast_row.anchor_right = 1.0
	toast_row.anchor_top = 1.0
	toast_row.anchor_bottom = 1.0
	toast_row.offset_left = 0.0
	toast_row.offset_right = 0.0
	toast_row.offset_top = -96.0
	toast_row.offset_bottom = -56.0
	add_child(toast_row)

	_toast_panel = PanelContainer.new()
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_panel.add_theme_stylebox_override(
		"panel", UIKit.flat_box(QGPalette.BG_PANEL_LIGHT, 8, QGPalette.VIOLET_DARK, 1, 14, 7)
	)
	_toast_label = UIKit.make_label("", 12, QGPalette.TEXT)
	_toast_panel.add_child(_toast_label)
	_toast_panel.visible = false
	toast_row.add_child(_toast_panel)


func _connect_session() -> void:
	if _session == null:
		return
	_session.state_changed.connect(_refresh)
	_session.match_started.connect(_on_match_started)
	_session.match_ended.connect(_on_match_ended)
	_session.status_changed.connect(_on_status_changed)
	_session.move_rejected.connect(_on_move_rejected)
	_session.opponent_left.connect(_on_opponent_left)
	_session.event_fired.connect(_on_event_fired)


# --------------------------------------------------------------------------
# State rendering
# --------------------------------------------------------------------------

func _refresh() -> void:
	if not is_inside_tree():
		return
	if _session == null or _session.game == null:
		_clear_cards()
		_hud.set_mode(QGSession.Mode.LOCAL)
		_hud.set_turn(QGTypes.EMPTY, "等待开局", false)
		_hud.set_status("对局尚未开始")
		_hud.set_quantum_enabled(false)
		_hud.set_undo_enabled(false)
		_hud.set_pass_enabled(false)
		_hud.set_resign_enabled(false)
		if _footer_mode != null:
			_footer_mode.text = ""
		return

	var game: QGGame = _session.game
	var online: bool = _session.mode != QGSession.Mode.LOCAL
	var ids := game.live_ids()

	_sync_cards(ids)
	if not ids.has(_focus_id) and not ids.is_empty():
		_focus_id = ids[0]
	_validate_quantum(game)

	# 13x13/19x19 boards cannot be made clickable for every universe at once, so
	# the layout switches to one large focused board plus a thumbnail column.
	var focus_layout: bool = game.board_size >= 13 and ids.size() > 2
	_focus_layout = focus_layout
	_grid.set_layout_mode(focus_layout, maxi(ids.find(_focus_id), 0))

	var quantum_mode := _quantum_on or _quantum_a >= 0
	var scoring: bool = game.is_scoring()
	# Phantom stones stay invisible while the game is being played: knowing which
	# stone might never have existed would turn the game into perfect information.
	# They are revealed once the game is decided (scoring phase / result panel).
	var reveal: bool = game.is_scoring() or game.is_over()
	for id in ids:
		var universe = game.get_universe(id)
		var card = _cards.get(id)
		if universe == null or card == null:
			continue
		var thumbnail: bool = focus_layout and id != _focus_id
		# During scoring the boards stay clickable, but a click marks a dead stone
		# instead of playing a move.
		var clickable: bool = scoring or (_session.can_play(id) and not thumbnail)
		card.apply(
			universe,
			id == _focus_id,
			clickable and not thumbnail,
			online,
			_session.my_color,
			quantum_mode,
			_quantum_a if _quantum_universe == id else -1,
			thumbnail,
			game.marked_dead(id) if scoring else ([] as Array[int]),
			reveal
		)

	_hud.set_scoring_mode(scoring)
	_hud.set_mode(_session.mode)
	_update_turn(game, ids, online)
	_hud.set_status(_hud_status(game, ids, online))
	if scoring:
		var my_confirm: bool = _session.mode != QGSession.Mode.LOCAL and game.is_confirmed(_session.my_color)
		_hud.set_confirm_state(
			not my_confirm or _session.mode == QGSession.Mode.LOCAL,
			"已确认" if my_confirm else "确认结算"
		)
	# A quantum split needs weight >= MIN_SPLIT_WEIGHT and a free universe slot;
	# the engine's can_split() is the single source of truth for that.
	var can_split: bool = game.can_split(_focus_id) and not game.is_over()
	_hud.set_quantum_enabled(can_split)
	_hud.set_quantum_reason("" if can_split else _quantum_exhausted_text(game))
	if not can_split and _quantum_on and _quantum_a < 0:
		_quantum_on = false
		_hud.set_quantum_checked(false)
	_hud.set_undo_enabled(
		_session.mode == QGSession.Mode.LOCAL and game.can_undo() and not game.is_over()
	)
	_hud.set_pass_enabled(not game.is_over() and _playable_focus(game) >= 0)
	_hud.set_resign_enabled(not game.is_over())
	_update_footer(game, online)

	if game.is_over() and not _result_shown:
		_show_result(_result_payload(game))


func _update_turn(game: QGGame, ids: Array[int], online: bool) -> void:
	if game.is_over() or ids.is_empty():
		_hud.set_turn(QGTypes.EMPTY, "对局结束", false)
		return
	if game.is_scoring():
		_hud.set_turn(QGTypes.EMPTY, "结算阶段", false)
		return
	var turn: int = game.turn_of(_focus_id)
	var can_play: bool = _session.can_play(_focus_id)
	var universe = game.get_universe(_focus_id)
	var waiting := false
	var text := ""
	if online and _session.my_color != QGTypes.EMPTY:
		if can_play:
			text = tr("轮到你（%s）") % ("黑方" if _session.my_color == QGTypes.BLACK else "白方")
		else:
			text = "等待对手落子…"
			waiting = true
	elif universe != null and bool(universe.sealed):
		text = "该宇宙已封印"
	elif turn == QGTypes.EMPTY:
		text = "对局结束"
	else:
		text = "黑方行棋" if turn == QGTypes.BLACK else "白方行棋"
	_hud.set_turn(turn, text, waiting)


func _hud_status(game: QGGame, ids: Array[int], online: bool) -> String:
	if _status_text.is_empty() and game.is_scoring():
		return _scoring_status_text(game)
	if not _status_text.is_empty():
		return _status_text
	if game.is_over():
		return "对局结束 · 结果见结算面板"
	if not game.can_split(_focus_id):
		return _quantum_exhausted_text(game)
	if _quantum_a >= 0:
		return "量子步：已选 A 点，点击第二个空点完成分裂（Esc 取消）"
	if _quantum_on:
		return "量子步模式：依次点击两个空点，现实会分裂成两个宇宙"
	if online:
		var my_name := ""
		if _session.my_color == QGTypes.BLACK:
			my_name = "黑方"
		elif _session.my_color == QGTypes.WHITE:
			my_name = "白方"
		var move_hint := "点击棋盘落子 · 每个宇宙独立行棋"
		if not my_name.is_empty():
			move_hint = tr("点击棋盘落子 · 你执%s · 每个宇宙独立行棋") % my_name
		for id in ids:
			if _session.can_play(id):
				return move_hint
		if not my_name.is_empty():
			return tr("你执%s · 对手行棋中，暂时不能操作棋盘") % my_name
		return "等待对手落子…"
	return "左键落子 · Shift+点击 或「量子步」分裂现实"


## Status line while the result is being agreed on.
func _scoring_status_text(game: QGGame) -> String:
	var marked := game.marked_count()
	var head := tr("结算阶段 · 点棋盘上的死子把它标掉（已标 %d 颗）") % marked
	if _session.mode == QGSession.Mode.LOCAL:
		return head + tr(" · 两人都确认后结束")
	if game.is_confirmed(_session.my_color):
		return head + tr(" · 已确认，等待对手确认")
	return head + tr(" · 确认无误后点「确认结算」")


func request_confirm_score() -> void:
	if _session == null or _session.game == null:
		return
	if not _session.game.is_scoring():
		return
	_play_sfx("play_click")
	var result: Dictionary = _session.submit_confirm_score()
	if not bool(result.get("ok", false)):
		_toast(UIKit.reason_text(String(result.get("reason", ""))))
		return
	_play_sfx("play_confirm")
	if not bool(result.get("final", false)):
		_toast("已确认，等待对手确认")
	_refresh()


func _update_footer(game: QGGame, online: bool) -> void:
	if _footer_mode == null:
		return
	if _footer_hint != null:
		if game.is_scoring():
			_footer_hint.text = tr("结算阶段：点击死子标记 · 确认后双方结束对局")
		else:
			_footer_hint.text = HINT_FOCUS if _focus_layout else HINT_DEFAULT
	if online:
		var lobby: Dictionary = _session.lobby_info()
		var opponent := ""
		if _session.mode == QGSession.Mode.HOST:
			opponent = String(lobby.get("guest", ""))
			if opponent.is_empty():
				opponent = "等待加入"
		else:
			opponent = String(lobby.get("host", "房主"))
		var state := "对局中" if _session.started else "连接中"
		_footer_mode.text = tr("对手：%s · %s") % [opponent, state]
	else:
		_footer_mode.text = tr("%s · 共 %d 手") % [L.board_text(game.board_size), game.move_count]


func _sync_cards(ids: Array[int]) -> void:
	var same := ids.size() == _card_ids.size()
	if same:
		for i in range(ids.size()):
			if ids[i] != _card_ids[i]:
				same = false
				break
	if same:
		return
	_clear_cards()
	_card_ids = ids.duplicate()
	for id in ids:
		var card = CardScript.new()
		card.point_clicked.connect(_on_board_point_clicked)
		card.selected.connect(_on_card_selected)
		_grid.add_child(card)
		_cards[id] = card
	_grid.queue_sort()


func _clear_cards() -> void:
	for card in _cards.values():
		if is_instance_valid(card):
			_grid.remove_child(card)
			card.queue_free()
	_cards.clear()
	_card_ids.clear()


# --------------------------------------------------------------------------
# Player intent
# --------------------------------------------------------------------------

func _on_board_point_clicked(universe_id: int, index: int) -> void:
	if _session == null or _session.game == null:
		return
	var game: QGGame = _session.game
	if game.is_over() or _confirm.is_open():
		return
	if game.is_scoring():
		# Observation is over: a click here toggles a dead-stone mark.
		var mark: Dictionary = _session.submit_mark(universe_id, index)
		if bool(mark.get("ok", false)):
			_play_sfx("play_mark")
			_refresh()
		else:
			_toast(UIKit.reason_text(String(mark.get("reason", ""))))
		return
	if not _session.can_play(universe_id):
		_toast("等待对手落子")
		return
	var universe = game.get_universe(universe_id)
	if universe == null or bool(universe.sealed):
		return

	_focus_id = universe_id
	var mover: int = game.turn_of(universe_id)
	var want_quantum: bool = _quantum_on or Input.is_key_pressed(KEY_SHIFT)

	# Second click of a quantum move.
	if _quantum_universe == universe_id and _quantum_a >= 0:
		if index == _quantum_a:
			_clear_quantum()
			_toast("已取消量子步选点")
			_refresh()
			return
		var point_a := _quantum_a
		_clear_quantum()
		var result: Dictionary = _session.submit_quantum(universe_id, point_a, index)
		if bool(result.get("ok", false)):
			_play_sfx("play_split")
			if not (result.get("collapsed", []) as Array).is_empty():
				_play_sfx("play_collapse")
			_toast("量子步：现实已分裂")
		elif String(result.get("reason", "")) == QGTypes.ERR_QUANTUM_EXHAUSTED:
			_toast(_quantum_exhausted_text(game))
		else:
			_toast(UIKit.reason_text(String(result.get("reason", ""))))
		_refresh()
		return

	# First click of a quantum move.
	if want_quantum:
		if not game.can_split(universe_id):
			_toast(_quantum_exhausted_text(game))
			return
		if not universe.position.is_empty(index):
			_toast("量子步需要两个空点")
			return
		_quantum_a = index
		_quantum_universe = universe_id
		_toast("量子步：已选 A 点，点击第二个空点（Esc 取消）")
		_refresh()
		return

	var move: Dictionary = _session.submit_move(universe_id, index)
	if bool(move.get("ok", false)):
		_play_sfx("play_stone", [mover])
		if not (move.get("collapsed", []) as Array).is_empty():
			_play_sfx("play_collapse")
	else:
		_toast(UIKit.reason_text(String(move.get("reason", ""))))
	_refresh()


func _on_card_selected(universe_id: int) -> void:
	if universe_id == _focus_id:
		return
	_focus_id = universe_id
	_clear_quantum()
	_refresh()


func _on_quantum_toggled(on: bool) -> void:
	_play_sfx("play_click")
	_quantum_on = on
	if not on:
		_clear_quantum()
		_refresh()
		return
	var game: QGGame = _session.game if _session != null else null
	if game == null:
		return
	if not game.can_split(_focus_id):
		_toast(_quantum_exhausted_text(game))
	_refresh()


func request_pass() -> void:
	if _session == null or _session.game == null or _session.game.is_over():
		return
	_play_sfx("play_click")
	var universe_id := _playable_focus(_session.game)
	if universe_id < 0:
		_toast("当前没有可以停一手的宇宙")
		return
	var result: Dictionary = _session.submit_pass(universe_id)
	if bool(result.get("ok", false)):
		_play_sfx("play_pass")
	else:
		_toast(UIKit.reason_text(String(result.get("reason", ""))))
	_refresh()


func request_resign() -> void:
	if _session == null or _session.game == null or _session.game.is_over():
		return
	_play_sfx("play_click")
	_open_confirm(CONFIRM_RESIGN, "认输", "确定放弃本局？对手将直接获胜。", "确认认输")


func request_undo() -> void:
	if _session == null or _session.game == null:
		return
	if _session.mode != QGSession.Mode.LOCAL:
		_toast("联机对局不能悔棋")
		return
	if _session.game.is_over():
		_toast("对局已经结束")
		return
	_play_sfx("play_click")
	var result: Dictionary = _session.submit_undo()
	if bool(result.get("ok", false)):
		_clear_quantum()
		_toast("已悔棋")
	else:
		_toast(UIKit.reason_text(String(result.get("reason", ""))))
	_refresh()


func request_exit() -> void:
	_play_sfx("play_click")
	var in_match: bool = (
		_session != null
		and _session.game != null
		and not _session.game.is_over()
		and _session.started
	)
	if in_match:
		_open_confirm(CONFIRM_EXIT, "退出对局", "返回主菜单后本局结束，进度不会保留。", "退出对局")
		return
	exit_requested.emit()


func cycle_focus(reverse: bool = false) -> void:
	if _session == null or _session.game == null:
		return
	var ids: Array[int] = _session.game.live_ids()
	if ids.is_empty():
		return
	var index: int = ids.find(_focus_id)
	if index < 0:
		index = 0
	else:
		index = posmod(index + (-1 if reverse else 1), ids.size())
	_focus_id = ids[index]
	_clear_quantum()
	_refresh()


func cancel_quantum() -> void:
	if _quantum_a < 0:
		return
	_clear_quantum()
	_toast("已取消量子步")
	_refresh()


func confirm_action() -> void:
	_on_confirm_confirmed()


func cancel_confirm() -> void:
	if _confirm.is_open():
		_confirm.close()
	_confirm_action = ""


# --------------------------------------------------------------------------
# Confirmation modal
# --------------------------------------------------------------------------

func _open_confirm(action: String, title: String, body: String, confirm_text: String) -> void:
	_confirm_action = action
	_confirm.open(title, body, confirm_text, true)


func _on_confirm_confirmed() -> void:
	_play_sfx("play_click")
	var action := _confirm_action
	_confirm_action = ""
	if action == CONFIRM_RESIGN:
		var resigning: int = _session.my_color
		if _session.mode == QGSession.Mode.LOCAL:
			# Hot seat: the player to move in the focused universe is the one
			# giving up, otherwise the wrong side would lose.
			resigning = _session.acting_color(_focus_id)
		var result: Dictionary = _session.submit_resign(resigning)
		if not bool(result.get("ok", false)):
			_toast(UIKit.reason_text(String(result.get("reason", ""))))
		_refresh()
	elif action == CONFIRM_EXIT:
		exit_requested.emit()


func _on_confirm_cancelled() -> void:
	_play_sfx("play_click")
	_confirm_action = ""


# --------------------------------------------------------------------------
# Session signals
# --------------------------------------------------------------------------

func _on_match_started(_meta: Dictionary) -> void:
	_result_shown = false
	if _result != null:
		_result.hide_result()
	_clear_quantum()
	_quantum_on = false
	_hud.set_quantum_checked(false)
	_status_text = ""
	_focus_id = 0
	_refresh()


func _on_match_ended(result: Dictionary) -> void:
	_show_result(result)


func _on_status_changed(text: String) -> void:
	_status_text = text
	if _hud != null:
		_hud.set_status(text)


func _on_move_rejected(reason: String) -> void:
	_toast(UIKit.reason_text(reason))


## Sound-only reaction to state packets from the other peer. The host emits a
## null event for its own moves (it already played the sound from the submit
## result), so a null/empty payload is ignored.
func _on_event_fired(event) -> void:
	if not (event is Dictionary):
		return
	var events: Array = []
	var payload: Dictionary = event
	if payload.has("events") and payload["events"] is Array:
		events = payload["events"]
	elif payload.has("type"):
		events = [payload]
	for item in events:
		if not (item is Dictionary):
			continue
		match String(item.get("type", "")):
			"move":
				_play_move_sound(int(item.get("universe", -1)))
			"split":
				_play_sfx("play_split")
			"collapse":
				_play_sfx("play_collapse")
			"pass", "sealed":
				_play_sfx("play_pass")


func _on_opponent_left() -> void:
	_status_text = "对手已离开"
	_toast("对手已离开")


func _on_rematch_pressed() -> void:
	_play_sfx("play_click")
	var has_listener := not get_signal_connection_list("rematch_requested").is_empty()
	rematch_requested.emit()
	# The shell owns the rematch flow (it may re-mount this scene or let the
	# session's match_started reset it). When the scene is driven without a shell
	# — tests and tools — fall back to Session.rematch() so the button still works.
	if has_listener:
		return
	if _session == null or not _session.has_method("rematch"):
		return
	var result: Dictionary = _session.rematch()
	if not bool(result.get("ok", false)):
		_toast(UIKit.reason_text(String(result.get("reason", ""))))


func _on_exit_pressed() -> void:
	_play_sfx("play_click")
	exit_requested.emit()


## The shell owns the replay screen; this scene only says "the player asked for it".
func _on_replay_pressed() -> void:
	_play_sfx("play_click")
	replay_requested.emit()


# --------------------------------------------------------------------------
# Keyboard
# --------------------------------------------------------------------------

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if _confirm.is_open():
		if event.keycode == KEY_ESCAPE:
			_confirm.close()
			_confirm_action = ""
			get_viewport().set_input_as_handled()
		return
	if _result_shown and _result.visible:
		return
	match event.keycode:
		KEY_ESCAPE:
			cancel_quantum()
			get_viewport().set_input_as_handled()
		KEY_TAB:
			cycle_focus(event.shift_pressed)
			get_viewport().set_input_as_handled()
		KEY_P:
			request_pass()
			get_viewport().set_input_as_handled()
		KEY_R:
			request_resign()
			get_viewport().set_input_as_handled()
		KEY_U:
			request_undo()
			get_viewport().set_input_as_handled()


# --------------------------------------------------------------------------
# Result
# --------------------------------------------------------------------------

func _result_payload(game: QGGame) -> Dictionary:
	var score: Dictionary = game.weighted_score()
	return {
		"winner": game.winner,
		"black": score["black"],
		"white": score["white"],
		"universes": score["universes"],
		"moves": game.move_count,
		"board_size": game.board_size,
		"meta": _session.match_meta,
	}


func _show_result(result: Dictionary) -> void:
	if _result_shown:
		return
	_result_shown = true
	_clear_quantum()
	_result.show_result(result, {"subtitle": _result_subtitle(result)})
	_play_result_sound(result)
	_refresh()


func _result_subtitle(result: Dictionary) -> String:
	var mode := "本地双人"
	var board_size := int(result.get("board_size", 0))
	if _session != null:
		if _session.mode != QGSession.Mode.LOCAL:
			mode = "在线对局"
		if board_size <= 0 and _session.game != null:
			board_size = _session.game.board_size
	var reason := _end_reason()
	return tr("%s · %s · 共 %d 手 · %s") % [mode, L.board_text(board_size), int(result.get("moves", 0)), reason]


func _end_reason() -> String:
	if _session == null or _session.game == null:
		return "终局"
	for event in _session.game.events:
		var kind := String(event.get("type", ""))
		if kind == "resign":
			var colour := int(event.get("colour", QGTypes.EMPTY))
			return tr("%s方认输") % ("黑" if colour == QGTypes.BLACK else "白")
		if kind == "game_over":
			return "双方停一手"
	return "终局"


# --------------------------------------------------------------------------
# Small helpers
# --------------------------------------------------------------------------

func _playable_focus(game: QGGame) -> int:
	if _session.can_play(_focus_id):
		return _focus_id
	for id in game.live_ids():
		if _session.can_play(id):
			return id
	return -1


func _play_sfx(method_name: String, args: Array = []) -> void:
	if _sfx == null or not _sfx.has_method(method_name):
		return
	_sfx.callv(method_name, args)


## A move event carries no colour; after the move the universe's turn belongs to
## the opponent of whoever just played.
func _play_move_sound(universe_id: int) -> void:
	if _session == null or _session.game == null:
		return
	var turn: int = _session.game.turn_of(universe_id)
	if turn == QGTypes.EMPTY:
		return
	_play_sfx("play_stone", [QGTypes.opponent(turn)])


func _play_result_sound(result: Dictionary) -> void:
	var local_won := true
	if _session != null and _session.my_color != QGTypes.EMPTY:
		local_won = int(result.get("winner", QGTypes.WINNER_NONE)) == _session.my_color
	_play_sfx("play_result", [local_won])


## The engine refuses a split for three reasons; say which one.
func _quantum_exhausted_text(game: QGGame) -> String:
	var universe = game.get_universe(_focus_id)
	if universe != null and bool(universe.sealed):
		return "该宇宙已封印，无法再分裂"
	if game.live_count() >= QGGame.MAX_LIVE_UNIVERSES:
		return tr("宇宙已达上限（最多 %d 个），不能再分裂") % QGGame.MAX_LIVE_UNIVERSES
	return "可能性太低（权重不足），不能再分裂"


func _validate_quantum(game: QGGame) -> void:
	if _quantum_a < 0:
		return
	var universe = game.get_universe(_quantum_universe)
	var invalid: bool = (
		universe == null
		or not bool(universe.alive)
		or bool(universe.sealed)
		or not _session.can_play(_quantum_universe)
		or universe.position.cells[_quantum_a] != QGTypes.EMPTY
	)
	if invalid:
		_clear_quantum()
		_toast("量子步选点已失效")


func _clear_quantum() -> void:
	_quantum_a = -1
	_quantum_universe = -1


func _toast(text: String) -> void:
	if _toast_panel == null or text.is_empty():
		return
	_toast_label.text = text
	_toast_panel.visible = true
	_toast_panel.modulate.a = 1.0
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.9)
	_toast_tween.tween_property(_toast_panel, "modulate:a", 0.0, 0.35)
	_toast_tween.tween_callback(_hide_toast)


func _hide_toast() -> void:
	if is_instance_valid(_toast_panel):
		_toast_panel.visible = false


# --------------------------------------------------------------------------
# Test / shell introspection hooks
# --------------------------------------------------------------------------

func card_count() -> int:
	return _cards.size()


func card_for(universe_id: int):
	return _cards.get(universe_id)


func board_for(universe_id: int):
	var card = _cards.get(universe_id)
	return card.board if card != null else null


func focused_universe() -> int:
	return _focus_id


## True when the screen shows one large focused board plus thumbnails (13x13 /
## 19x19 with 3+ universes) instead of the equal grid.
func is_focus_layout() -> bool:
	return _focus_layout


func quantum_mode_on() -> bool:
	return _quantum_on


## Programmatic equivalent of clicking the 量子步 button (used by tests and by a
## future controller binding).
func set_quantum_mode(on: bool) -> void:
	if _hud != null:
		_hud.set_quantum_checked(on)
	_on_quantum_toggled(on)


func quantum_pending() -> bool:
	return _quantum_a >= 0


func quantum_a_point() -> int:
	return _quantum_a


func is_confirm_open() -> bool:
	return _confirm != null and _confirm.is_open()


func is_result_visible() -> bool:
	return _result != null and _result.visible


func result_panel():
	return _result


func toast_text() -> String:
	return _toast_label.text if _toast_label != null else ""
