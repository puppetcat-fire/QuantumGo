## Shown instead of the match screen when `res://src/ui/match/match.tscn` is not
## available (it is built in parallel). The shell must never crash or dead-end
## because another module is late: the player gets a clear message and a way out.
class_name QGMatchPlaceholder
extends Control

signal exit_requested

const UI := preload("res://src/ui/shell/ui_kit.gd")


func _ready() -> void:
	var background := ColorRect.new()
	background.color = Color(QGPalette.BG_DEEP, 0.9)
	add_child(background)
	UI.full_rect(background)

	var centre := CenterContainer.new()
	add_child(centre)
	UI.full_rect(centre)

	var card := UI.card()
	card.custom_minimum_size = Vector2(560, 0)
	centre.add_child(card)

	var column := UI.vbox(UI.GAP)
	card.add_child(column)
	column.add_child(UI.kicker("对局界面"))
	var title := UI.h2("对局界面尚未就绪…")
	column.add_child(title)

	var mode_text := "单机双人" if Session.mode == QGSession.Mode.LOCAL else "联机对战"
	var board_size := Session.game.board_size if Session.game != null else Settings.board_size
	column.add_child(UI.muted(
		tr("对局已经按%s、%s棋盘创建，但界面模块还没有装配完成。返回后其它功能可以照常使用。") % [mode_text, L.board_text(board_size)],
		true))

	column.add_child(UI.spacer_h(UI.GAP_SM))
	column.add_child(UI.divider())
	var row := UI.hbox(UI.GAP)
	row.add_child(UI.dim("对局数据不会丢失，界面就位后重新进入即可。"))
	var spring := Control.new()
	spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spring)
	var back := UI.button("返回主菜单", "PrimaryButton", 168)
	back.pressed.connect(func() -> void: exit_requested.emit())
	row.add_child(back)
	column.add_child(row)
	back.call_deferred("grab_focus")
