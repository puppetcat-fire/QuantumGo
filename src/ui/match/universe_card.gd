## One universe card: header (id, weight, turn) plus the board widget.
##
## The card owns no game logic. The match screen feeds it a universe snapshot and
## forwards its board clicks back up.
class_name QGUniverseCard
extends PanelContainer

signal point_clicked(universe_id: int, index: int)
signal selected(universe_id: int)

const UIKit := preload("res://src/ui/match/ui_kit.gd")
const BoardView := preload("res://src/ui/match/board_view.gd")

const PAD := 10.0
const HEADER_HEIGHT := 26.0

var universe_id: int = -1
var board: QGBoardView = null

var _title: Label = null
var _weight_box: PanelContainer = null
var _weight_label: Label = null
var _turn_dot: Panel = null
var _turn_label: Label = null
var _sealed_label: Label = null
var _focused := false
var _compact_level := -1
var _has_turn := false
var _sealed_state := false
## The container fits a card (and therefore sends NOTIFICATION_RESIZED) as soon
## as it is added to the grid, which can be before _ready has built the children.
## Layout work is deferred until the card is actually built; a snapshot passed in
## before that point is replayed in _ready.
var _built := false
var _pending_apply: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	_built = true
	_apply_focus_style()
	_apply_compact(true)
	if not _pending_apply.is_empty():
		var args := _pending_apply
		_pending_apply = []
		apply(
			args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7]
		)


func _build() -> void:
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", int(PAD))
	margin.add_theme_constant_override("margin_right", int(PAD))
	margin.add_theme_constant_override("margin_top", int(PAD))
	margin.add_theme_constant_override("margin_bottom", int(PAD))

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)

	var header := HBoxContainer.new()
	header.custom_minimum_size = Vector2(0.0, HEADER_HEIGHT)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_constant_override("separation", 8)
	column.add_child(header)

	_title = UIKit.make_label("宇宙 0", 14, QGPalette.TEXT, true)
	_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_title)

	_weight_box = PanelContainer.new()
	_weight_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_weight_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_weight_label = UIKit.make_label("100%", 12, QGPalette.ACCENT, true)
	_weight_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_weight_box.add_child(_weight_label)
	header.add_child(_weight_box)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(spacer)

	var turn_box := HBoxContainer.new()
	turn_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	turn_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	turn_box.add_theme_constant_override("separation", 5)
	header.add_child(turn_box)

	_turn_dot = Panel.new()
	_turn_dot.custom_minimum_size = Vector2(11.0, 11.0)
	_turn_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_turn_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	turn_box.add_child(_turn_dot)

	_turn_label = UIKit.make_label("黑方", 12, QGPalette.TEXT_MUTED)
	_turn_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	turn_box.add_child(_turn_label)

	_sealed_label = UIKit.make_label("已封印", 12, QGPalette.WARNING)
	_sealed_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	turn_box.add_child(_sealed_label)

	board = BoardView.new()
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.custom_minimum_size = Vector2(24.0, 24.0)
	board.point_clicked.connect(_on_board_point_clicked)
	column.add_child(board)

	add_child(margin)


func _apply_focus_style() -> void:
	var border := QGPalette.ACCENT if _focused else QGPalette.BG_PANEL_LIGHT
	var width := 2 if _focused else 1
	add_theme_stylebox_override("panel", UIKit.flat_box(QGPalette.BG_PANEL, 10, border, width))


## Drops detail as the card gets narrower so the header can never force the card
## wider than its grid cell (which would make neighbouring boards overlap).
func _apply_compact(force: bool = false) -> void:
	if not _built:
		return
	var level := 0
	if size.x > 0.0:
		if size.x < 150.0:
			level = 3
		elif size.x < 200.0:
			level = 2
		elif size.x < 260.0:
			level = 1
	if level == _compact_level and not force:
		return
	_compact_level = level
	_title.add_theme_font_size_override("font_size", 12 if level >= 1 else 14)
	_turn_label.add_theme_font_size_override("font_size", 11 if level >= 1 else 12)
	_weight_label.add_theme_font_size_override("font_size", 11 if level >= 1 else 12)
	_sealed_label.add_theme_font_size_override("font_size", 11 if level >= 1 else 12)
	if universe_id >= 0:
		_title.text = (tr("宇宙 %d") % universe_id) if level < 3 else ("%d" % universe_id)
	_weight_box.visible = level < 3
	_turn_dot.visible = _has_turn and level < 2
	_turn_label.visible = _has_turn and level < 2
	_sealed_label.visible = _sealed_state and level < 2


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_apply_compact()


## Feeds one universe snapshot into the card. `thumbnail` marks the small
## overview cards of the focus layout: they are click-to-focus only, never play.
func apply(
	universe: Variant,
	focused: bool,
	can_play: bool,
	online: bool,
	my_color: int,
	quantum_mode: bool,
	pending_a: int,
	thumbnail: bool = false,
	dead_points: Array[int] = [],
	reveal_phantoms: bool = false
) -> void:
	if universe == null:
		return
	if not _built:
		_pending_apply = [
			universe, focused, can_play, online, my_color, quantum_mode, pending_a, thumbnail
		]
		return
	universe_id = int(universe.id)
	_focused = focused
	_apply_focus_style()
	mouse_default_cursor_shape = (
		Control.CURSOR_POINTING_HAND if thumbnail else Control.CURSOR_ARROW
	)

	_title.text = tr("宇宙 %d") % universe_id
	_weight_label.text = "%d%%" % int(universe.weight)
	_weight_label.add_theme_color_override(
		"font_color",
		QGPalette.ACCENT if int(universe.weight) >= 100 else QGPalette.VIOLET
	)
	_weight_box.add_theme_stylebox_override(
		"panel",
		UIKit.flat_box(
			QGPalette.BG_PANEL_LIGHT,
			5,
			QGPalette.BG_HOVER if int(universe.weight) >= 100 else QGPalette.VIOLET_DARK,
			1,
			6,
			1
		)
	)

	var sealed: bool = bool(universe.sealed)
	_has_turn = not sealed
	_sealed_state = sealed
	if not sealed:
		var colour := int(universe.turn)
		_turn_dot.add_theme_stylebox_override("panel", UIKit.stone_dot_style(colour, 11.0))
		if online:
			if colour == my_color:
				_turn_label.text = "轮到你"
				_turn_label.add_theme_color_override("font_color", QGPalette.ACCENT)
			else:
				_turn_label.text = "等待"
				_turn_label.add_theme_color_override("font_color", QGPalette.TEXT_MUTED)
		else:
			_turn_label.text = "黑方" if colour == QGTypes.BLACK else "白方"
			_turn_label.add_theme_color_override("font_color", QGPalette.TEXT_MUTED)
	_apply_compact(true)

	var position: QGPosition = universe.position
	var tooltip := tr("宇宙 %d · 权重 %d%%") % [universe_id, int(universe.weight)]
	if int(universe.parent) >= 0:
		tooltip += tr(" · 分裂自宇宙 %d") % int(universe.parent)
	if thumbnail:
		tooltip += " · 点击切换到这个棋盘"
	tooltip_text = tooltip

	board.apply_state(
		position,
		sealed,
		int(universe.last_move),
		int(universe.ko_point),
		can_play and not thumbnail,
		int(universe.turn),
		quantum_mode,
		pending_a,
		not thumbnail,
		dead_points,
		reveal_phantoms
	)


func _on_board_point_clicked(index: int) -> void:
	point_clicked.emit(universe_id, index)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		selected.emit(universe_id)
		accept_event()
