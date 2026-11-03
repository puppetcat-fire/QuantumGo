## Modal shown over the final position when a match ends.
##
## The shell records the result and then hands the numbers here; this view never
## recomputes scores. Buttons are the only way forward, so the player cannot
## accidentally end up in a half-torn-down match.
class_name QGResultView
extends Control

signal rematch_pressed
signal menu_pressed

const UI := preload("res://src/ui/shell/ui_kit.gd")

var _primary: Button = null


func setup(result: Dictionary, names: Dictionary, entry: Dictionary) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(QGPalette.BG_DEEP, 0.72)
	add_child(dim)
	UI.full_rect(dim)

	var centre := CenterContainer.new()
	add_child(centre)
	UI.full_rect(centre)

	var card := UI.card()
	card.theme_type_variation = &"AccentPanel"
	card.custom_minimum_size = Vector2(560, 0)
	centre.add_child(card)

	var column := UI.vbox(UI.GAP)
	card.add_child(column)

	var winner := int(result.get("winner", 0))
	column.add_child(UI.kicker("对局结束"))
	var headline := UI.hero(_headline(winner))
	headline.add_theme_color_override("font_color", _headline_colour(winner))
	column.add_child(headline)
	column.add_child(UI.muted(_names_line(names), true))

	column.add_child(UI.spacer_h(UI.GAP_SM))
	column.add_child(_score_panel(result))
	column.add_child(UI.spacer_h(UI.GAP_SM))

	if not entry.is_empty():
		var recorded := UI.hbox(UI.GAP_SM)
		recorded.add_child(UI.status_dot(QGPalette.SUCCESS, 6))
		recorded.add_child(UI.dim("已记入本地排行榜"))
		column.add_child(recorded)

	column.add_child(UI.spacer_h(UI.GAP_SM))
	var buttons := UI.hbox(UI.GAP)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	_primary = UI.button("再来一局", "PrimaryButton", 168)
	_primary.pressed.connect(func() -> void: rematch_pressed.emit())
	buttons.add_child(_primary)
	var menu_button := UI.button("返回主菜单", "GhostButton", 140)
	menu_button.pressed.connect(func() -> void: menu_pressed.emit())
	buttons.add_child(menu_button)
	column.add_child(buttons)
	_primary.call_deferred("grab_focus")


func _score_panel(result: Dictionary) -> PanelContainer:
	var panel := UI.card(true)
	var column := UI.vbox(UI.GAP_SM)
	panel.add_child(column)
	var black := int(result.get("black", 0))
	var white := int(result.get("white", 0))
	column.add_child(_score_row("黑方（加权目数）", str(black), black >= white))
	column.add_child(_score_row("白方（加权目数）", str(white), white >= black))
	column.add_child(UI.divider())
	var meta := UI.hbox(UI.GAP)
	var universes: Array = result.get("universes", [])
	meta.add_child(UI.dim(tr("存活宇宙 %d") % universes.size()))
	meta.add_child(UI.spacer_w(UI.GAP))
	meta.add_child(UI.dim(tr("手数 %d") % int(result.get("moves", 0))))
	meta.add_child(UI.spacer_w(UI.GAP))
	meta.add_child(UI.dim(tr("%s棋盘") % L.board_text(int(result.get("board_size", 9)))))
	column.add_child(meta)
	return panel


func _score_row(caption: String, value: String, emphasise: bool) -> HBoxContainer:
	var row := UI.hbox(UI.GAP)
	row.add_child(UI.muted(caption, false))
	var spring := Control.new()
	spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spring)
	var value_label := UI.label(value, "H3Label")
	if emphasise:
		value_label.add_theme_color_override("font_color", QGPalette.ACCENT)
	row.add_child(value_label)
	return row


func _headline(winner: int) -> String:
	match winner:
		QGTypes.WINNER_BLACK:
			return "黑方胜"
		QGTypes.WINNER_WHITE:
			return "白方胜"
		_:
			return "和棋"


func _headline_colour(winner: int) -> Color:
	match winner:
		QGTypes.WINNER_BLACK:
			return QGPalette.ACCENT
		QGTypes.WINNER_WHITE:
			return QGPalette.VIOLET
		_:
			return QGPalette.TEXT


func _names_line(names: Dictionary) -> String:
	var black := String(names.get(QGTypes.BLACK, "黑方"))
	var white := String(names.get(QGTypes.WHITE, "白方"))
	return tr("%s（黑）  对  %s（白）") % [black, white]
