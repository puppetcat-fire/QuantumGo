## End-of-match overlay: winner, weighted score, per-universe breakdown and the
## two buttons the shell listens to (再来一局 / 返回主菜单).
##
## The panel never changes scenes itself; it only emits intent.
class_name QGResultPanel
extends Control

signal rematch_requested
signal exit_requested
signal replay_requested

const UIKit := preload("res://src/ui/match/ui_kit.gd")
const PANEL_WIDTH := 760.0

var _title: Label = null
var _subtitle: Label = null
var _black_box: PanelContainer = null
var _white_box: PanelContainer = null
var _black_value: Label = null
var _white_value: Label = null
var _rows: GridContainer = null
var _breakdown_title: Label = null
var _rematch_button: Button = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()


func _build() -> void:
	var scrim := ColorRect.new()
	scrim.color = Color(QGPalette.BG_DEEP, 0.86)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	panel.add_theme_stylebox_override(
		"panel", UIKit.flat_box(QGPalette.BG_PANEL, 14, QGPalette.ACCENT_DARK, 1)
	)
	centre.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_bottom", 26)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)

	# --- title -------------------------------------------------------------
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 16)
	column.add_child(title_row)

	var title_column := VBoxContainer.new()
	title_column.add_theme_constant_override("separation", 2)
	title_row.add_child(title_column)

	_title = UIKit.make_label("对局结束", 30, QGPalette.TEXT, true)
	title_column.add_child(_title)
	_subtitle = UIKit.make_label("", 12, QGPalette.TEXT_MUTED)
	title_column.add_child(_subtitle)

	# --- weighted score ----------------------------------------------------
	var score_row := HBoxContainer.new()
	score_row.add_theme_constant_override("separation", 12)
	column.add_child(score_row)

	_black_box = _make_score_box("黑方", QGTypes.BLACK)
	_black_value = _black_box.get_meta("value_label")
	score_row.add_child(_black_box)

	_white_box = _make_score_box("白方", QGTypes.WHITE)
	_white_value = _white_box.get_meta("value_label")
	score_row.add_child(_white_box)

	var formula := UIKit.make_label(
		"加权目数 = 各宇宙目数 × 该宇宙权重，全部存活宇宙之和",
		10,
		QGPalette.TEXT_DIM
	)
	column.add_child(formula)

	var divider := ColorRect.new()
	divider.color = QGPalette.BG_PANEL_LIGHT
	divider.custom_minimum_size = Vector2(0.0, 1.0)
	column.add_child(divider)

	# --- per-universe breakdown -------------------------------------------
	_breakdown_title = UIKit.make_label("各宇宙明细", 13, QGPalette.TEXT_MUTED)
	column.add_child(_breakdown_title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0.0, 196.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	column.add_child(scroll)

	_rows = GridContainer.new()
	_rows.columns = 6
	_rows.add_theme_constant_override("h_separation", 18)
	_rows.add_theme_constant_override("v_separation", 7)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)

	# --- buttons -----------------------------------------------------------
	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 10)
	button_row.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(button_row)

	var replay_button := UIKit.make_button("复盘", "ghost", 110.0)
	replay_button.custom_minimum_size = Vector2(110.0, 42.0)
	replay_button.tooltip_text = "逐步回看这一局，并能看到当时哪颗子是虚子"
	replay_button.pressed.connect(func() -> void: replay_requested.emit())
	button_row.add_child(replay_button)

	var back_button := UIKit.make_button("返回主菜单", "ghost", 150.0)
	back_button.custom_minimum_size = Vector2(150.0, 42.0)
	back_button.pressed.connect(func() -> void: exit_requested.emit())
	button_row.add_child(back_button)

	_rematch_button = UIKit.make_button("再来一局", "accent", 170.0)
	_rematch_button.custom_minimum_size = Vector2(170.0, 42.0)
	_rematch_button.pressed.connect(func() -> void: rematch_requested.emit())
	button_row.add_child(_rematch_button)

	var note := UIKit.make_label("点击「再来一局」用同样的棋盘大小重新开局", 10, QGPalette.TEXT_DIM)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(note)


func _make_score_box(name: String, colour: int) -> PanelContainer:
	var box := PanelContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_stylebox_override(
		"panel", UIKit.flat_box(QGPalette.BG_PANEL_LIGHT, 10, QGPalette.BG_HOVER, 1)
	)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	box.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	margin.add_child(column)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	column.add_child(head)

	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(12.0, 12.0)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.add_theme_stylebox_override("panel", UIKit.stone_dot_style(colour, 12.0))
	head.add_child(dot)
	head.add_child(UIKit.make_label(name, 13, QGPalette.TEXT_MUTED))

	var value := UIKit.make_label("0.0", 27, QGPalette.TEXT, true)
	column.add_child(value)

	var caption := UIKit.make_label("加权目数", 10, QGPalette.TEXT_DIM)
	column.add_child(caption)

	box.set_meta("value_label", value)
	box.set_meta("dot", dot)
	return box


## Fills and shows the overlay.
## `result` is the payload from Session.match_ended / QGGame.weighted_score;
## `context` carries display-only strings from match.gd (subtitle, end reason).
func show_result(result: Dictionary, context: Dictionary = {}) -> void:
	var winner := int(result.get("winner", QGTypes.WINNER_NONE))
	var black := int(result.get("black", 0))
	var white := int(result.get("white", 0))

	_title.text = _winner_text(winner, black, white)
	_title.add_theme_color_override(
		"font_color",
		QGPalette.TEXT if winner != QGTypes.WINNER_NONE else QGPalette.TEXT_MUTED
	)
	_subtitle.text = String(context.get("subtitle", ""))

	_black_value.text = tr("%s 目") % UIKit.format_units(black)
	_white_value.text = tr("%s 目") % UIKit.format_units(white)
	_black_value.add_theme_color_override(
		"font_color", QGPalette.ACCENT if winner == QGTypes.WINNER_BLACK else QGPalette.TEXT
	)
	_white_value.add_theme_color_override(
		"font_color", QGPalette.ACCENT if winner == QGTypes.WINNER_WHITE else QGPalette.TEXT
	)
	_style_score_box(_black_box, winner == QGTypes.WINNER_BLACK)
	_style_score_box(_white_box, winner == QGTypes.WINNER_WHITE)

	var universes: Array = result.get("universes", [])
	_breakdown_title.text = tr("各宇宙明细 · %d 个宇宙 · 加权目数 = 目数 × 权重") % universes.size()
	_render_rows(universes)

	visible = true


func hide_result() -> void:
	visible = false


func _winner_text(winner: int, black: int, white: int) -> String:
	match winner:
		QGTypes.WINNER_BLACK:
			return "黑方胜"
		QGTypes.WINNER_WHITE:
			return "白方胜"
		_:
			return "和棋" if black == white else "无胜负"


func _style_score_box(box: PanelContainer, is_winner: bool) -> void:
	box.add_theme_stylebox_override(
		"panel",
		UIKit.flat_box(
			QGPalette.BG_PANEL_LIGHT,
			10,
			QGPalette.ACCENT if is_winner else QGPalette.BG_HOVER,
			2 if is_winner else 1
		)
	)


func _render_rows(universes: Array) -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()

	for header in ["宇宙", "权重", "黑目", "白目", "加权目数（黑 : 白）", "状态"]:
		var cell := UIKit.make_label(header, 11, QGPalette.TEXT_DIM)
		cell.custom_minimum_size = Vector2(0.0, 22.0)
		_rows.add_child(cell)

	for row in universes:
		var data := row as Dictionary
		var weight := int(data.get("weight", 0))
		var black_area := int(data.get("black", 0))
		var white_area := int(data.get("white", 0))
		var black_value := int(data.get("black_value", black_area * weight))
		var white_value := int(data.get("white_value", white_area * weight))
		var sealed := bool(data.get("sealed", false))
		var weight_colour := QGPalette.ACCENT if weight >= 100 else QGPalette.VIOLET

		_rows.add_child(_make_cell(tr("宇宙 %d") % int(data.get("id", -1)), 13, QGPalette.TEXT))
		_rows.add_child(_make_cell("%d%%" % weight, 13, weight_colour))
		_rows.add_child(_make_cell(str(black_area), 13, QGPalette.TEXT))
		_rows.add_child(_make_cell(str(white_area), 13, QGPalette.TEXT))
		_rows.add_child(_make_cell(
			"%s : %s" % [UIKit.format_units(black_value), UIKit.format_units(white_value)],
			13,
			QGPalette.TEXT_MUTED
		))
		_rows.add_child(_make_cell(
			"已封印" if sealed else "未封印",
			12,
			QGPalette.WARNING if sealed else QGPalette.TEXT_DIM
		))


func _make_cell(text: String, font_size: int, colour: Color) -> Label:
	var label := UIKit.make_label(text, font_size, colour)
	label.custom_minimum_size = Vector2(0.0, 22.0)
	return label
