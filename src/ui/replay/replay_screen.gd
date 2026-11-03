## 复盘: step through the finished match one position at a time.
##
## This is the only place where phantom stones are visible while the boards are
## still interesting — that is the whole point of hiding them during play. The
## screen reads snapshots recorded by `QGSession`, so it needs no rules logic of
## its own: it rebuilds a `QGGame` from a snapshot and draws it.
class_name QGReplayScreen
extends "res://src/ui/shell/screen.gd"

const BoardView := preload("res://src/ui/match/board_view.gd")
const UIKit := preload("res://src/ui/match/ui_kit.gd")

const BOARD_MAX := 300
const BOARD_MIN := 176

var _history: Array[Dictionary] = []
var _index: int = 0
var _board_row: HBoxContainer = null
var _info_label: Label = null
var _step_label: Label = null
var _slider: HSlider = null
var _prev_button: Button = null
var _next_button: Button = null
var _board_columns: Array[Control] = []
var _view_ids: Dictionary = {}


func _ready() -> void:
	build_page("复盘", "回看这一局", "左右切换每一步。紫色虚线是当时那颗虚子——对局中谁都看不到它。")
	add_topbar_note("复盘")
	_build_body()


func _build_body() -> void:
	var column := UI.vbox(UI.GAP)
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(column)

	# The boards are centred both ways and sized so that up to six universes fit
	# without scrolling; the replay is for looking, so it should not need panning.
	var centre := CenterContainer.new()
	centre.size_flags_vertical = Control.SIZE_EXPAND_FILL
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(centre)

	_board_row = UI.hbox(UI.GAP_LG)
	_board_row.alignment = BoxContainer.ALIGNMENT_CENTER
	centre.add_child(_board_row)

	var controls := UI.card()
	column.add_child(controls)
	var row := UI.vbox(UI.GAP_SM)
	controls.add_child(row)

	var top := UI.hbox(UI.GAP_SM)
	row.add_child(top)
	_step_label = UI.label("", "BodyLabel")
	top.add_child(_step_label)
	var spring := Control.new()
	spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spring)
	_info_label = UI.dim("")
	top.add_child(_info_label)

	_slider = HSlider.new()
	_slider.min_value = 0
	_slider.max_value = 0
	_slider.step = 1
	_slider.custom_minimum_size = Vector2(0, 26)
	_slider.value_changed.connect(_on_slider_changed)
	row.add_child(_slider)

	var buttons := UI.hbox(UI.GAP_SM)
	row.add_child(buttons)
	_prev_button = UI.button("◀ 上一步", "GhostButton", 120, 40)
	_prev_button.pressed.connect(_on_prev_pressed)
	buttons.add_child(_prev_button)
	_next_button = UI.button("下一步 ▶", "PrimaryButton", 120, 40)
	_next_button.pressed.connect(_on_next_pressed)
	buttons.add_child(_next_button)
	var spring2 := Control.new()
	spring2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spring2)
	var close := UI.button("返回主菜单", "GhostButton", 150, 40)
	close.pressed.connect(func() -> void: go("menu"))
	buttons.add_child(close)


## Feeds the recorded snapshots into the screen. Called by the shell right before
## the screen is shown.
func load_replay(history: Array) -> void:
	_history.clear()
	for entry in history:
		if typeof(entry) == TYPE_DICTIONARY:
			_history.append(entry)
	_index = maxi(0, _history.size() - 1)
	if _slider != null:
		_slider.max_value = maxi(0, _history.size() - 1)
		_slider.set_value_no_signal(_index)
	_refresh()


func current_index() -> int:
	return _index


func step_count() -> int:
	return _history.size()


func board_for(universe_id: int) -> QGBoardView:
	return _view_ids.get(universe_id, null)


## The position currently on screen, rebuilt from the snapshot. Used by the smoke
## test and available for future "jump to a move" features.
func current_game() -> QGGame:
	if _history.is_empty():
		return null
	var index := clampi(_index, 0, _history.size() - 1)
	return QGGame.from_dict(_history[index])


func _on_prev_pressed() -> void:
	_step_by(-1)


func _on_next_pressed() -> void:
	_step_by(1)


func _step_by(delta: int) -> void:
	if _history.is_empty():
		return
	_index = clampi(_index + delta, 0, _history.size() - 1)
	if _slider != null:
		_slider.set_value_no_signal(_index)
	_refresh()


func _on_slider_changed(value: float) -> void:
	_index = int(round(value))
	_refresh()


func _refresh() -> void:
	if _board_row == null:
		return
	for column in _board_columns:
		if is_instance_valid(column):
			if column.get_parent() != null:
				column.get_parent().remove_child(column)
			column.queue_free()
	_board_columns.clear()
	_view_ids.clear()

	if _history.is_empty():
		_step_label.text = "没有可复盘的对局"
		_info_label.text = ""
		return

	_index = clampi(_index, 0, _history.size() - 1)
	_step_label.text = tr("第 %d 步 / 共 %d 步") % [_index, _history.size() - 1]
	_prev_button.disabled = _index <= 0
	_next_button.disabled = _index >= _history.size() - 1

	var game := QGGame.from_dict(_history[_index])
	var live := game.live_ids()
	_info_label.text = tr("%s棋盘 · %d 个宇宙 · 死子 %d") % [
		L.board_text(game.board_size), live.size(), game.marked_count()
	]

	# Size the boards so every universe fits on one row: 1 board gets the space it
	# deserves, six boards stay readable but compact.
	var side_by_count := {1: 480, 2: 420, 3: 340, 4: 300, 5: 250, 6: 210}
	var side: int = int(side_by_count.get(mini(live.size(), 6), BOARD_MIN))
	for id in live:
		var universe := game.get_universe(id)
		if universe == null:
			continue
		var column := UI.vbox(UI.GAP_SM)
		column.alignment = BoxContainer.ALIGNMENT_CENTER
		var caption := UI.label(tr("宇宙 %d · 权重 %d%%") % [id, universe.weight], "DimLabel")
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(caption)
		var pairing := _pairing_text(game, universe)
		if not pairing.is_empty():
			var pairing_label := UI.dim(pairing)
			pairing_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			pairing_label.add_theme_color_override(
				"font_color",
				QGPalette.VIOLET if universe.is_phantom_holder() else QGPalette.TEXT_MUTED
			)
			column.add_child(pairing_label)
		# Phantoms are inherited, so a board can carry several. Saying which
		# universe rolled each one is what tells two "C3 phantoms" apart.
		var inherited := _inherited_text(game, universe)
		if not inherited.is_empty():
			var inherited_label := UI.dim(inherited)
			inherited_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			inherited_label.add_theme_color_override("font_color", QGPalette.VIOLET_DARK)
			column.add_child(inherited_label)

		var view := BoardView.new()
		view.name = "Board%d" % id
		view.custom_minimum_size = Vector2(side, side)
		# Reveal the phantoms: this is the payoff for hiding them during the match.
		view.apply_state(
			universe.position,
			universe.sealed,
			universe.last_move,
			universe.ko_point,
			false,
			universe.turn,
			false,
			-1,
			true,
			game.marked_dead(id),
			true
		)
		column.add_child(view)
		_board_columns.append(column)
		_view_ids[id] = view
		_board_row.add_child(column)


## "虚子 B3 ↔ 实子 宇宙 4 · B7": the replay's whole point is being able to line a
## phantom up with the real stone that the same split placed on the other board.
func _pairing_text(game: QGGame, universe: QGGame.Universe) -> String:
	if universe.split_point < 0:
		return ""
	var partner := game.get_universe(universe.partner)
	if universe.is_phantom_holder():
		var mine := UIKit.point_name(universe.phantom_point, game.board_size)
		if partner == null:
			return tr("虚子 %s · 对应实子宇宙已消失") % mine
		var counterpart := UIKit.point_name(partner.split_point, game.board_size)
		var fate := _partner_fate(game, partner)
		if fate.is_empty():
			return tr("虚子 %s ↔ 实子 宇宙 %d · %s") % [mine, partner.id, counterpart]
		return tr("虚子 %s ↔ 实子 宇宙 %d · %s（%s）") % [mine, partner.id, counterpart, fate]
	if partner != null and partner.is_phantom_holder():
		var real_point := UIKit.point_name(universe.split_point, game.board_size)
		var phantom_point := UIKit.point_name(partner.phantom_point, game.board_size)
		var fate := _partner_fate(game, partner)
		if fate.is_empty():
			return tr("实子 %s ↔ 虚子 宇宙 %d · %s") % [real_point, partner.id, phantom_point]
		return tr("实子 %s ↔ 虚子 宇宙 %d · %s（%s）") % [real_point, partner.id, phantom_point, fate]
	return ""


## "" while the partner is still on the board, otherwise why it is gone.
func _partner_fate(game: QGGame, partner: QGGame.Universe) -> String:
	if partner.alive:
		return ""
	return tr("该支已再分裂") if _subtree_has_live(game, partner.id) else tr("已坍缩")


func _subtree_has_live(game: QGGame, root_id: int) -> bool:
	var universe := game.get_universe(root_id)
	if universe == null:
		return false
	if universe.alive:
		return true
	for child_id in universe.children:
		if _subtree_has_live(game, child_id):
			return true
	return false


## Lists the phantoms this board inherited from ancestors, each with the universe
## that rolled it: two boards can show a phantom on the same point and they are
## still different stones if they were rolled by different splits.
func _inherited_text(game: QGGame, universe: QGGame.Universe) -> String:
	var parts: Array[String] = []
	for index in range(universe.position.phantom.size()):
		if universe.position.phantom[index] == 0:
			continue
		var owner := _phantom_owner(game, universe.id, index)
		if owner < 0 or owner == universe.id:
			continue
		parts.append("%s←%d" % [UIKit.point_name(index, game.board_size), owner])
	if parts.is_empty():
		return ""
	return tr("继承虚子 %s（← 掷出的宇宙）") % "、".join(parts)


func _phantom_owner(game: QGGame, from_id: int, point: int) -> int:
	var current := from_id
	while current >= 0:
		var universe := game.get_universe(current)
		if universe == null:
			return -1
		if universe.phantom_point == point:
			return current
		current = universe.parent
	return -1
