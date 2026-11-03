## 排行榜: local standings, recent matches, and an honest note that the online
## ranking will be Steam's later.
##
## Everything comes from the `Leaderboard` autoload; this screen owns no state and
## rebuilds itself on every show, so a match recorded a second ago is already here.
class_name QGLeaderboardScreen
extends "res://src/ui/shell/screen.gd"

const HISTORY_PREVIEW := 7

var _table_card: PanelContainer = null
var _history_card: PanelContainer = null


func _ready() -> void:
	build_page("排行榜", "本地积分榜",
		"这台电脑上打过的对局都会记在这里。之后接入 Steam 时，在线排名会放到 Steam 排行榜。")
	add_topbar_note("只在本机")

	var columns := UI.hbox(UI.GAP_LG)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)

	_table_card = UI.card()
	_table_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_table_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_child(_table_card)

	var side := UI.vbox(UI.GAP_LG)
	side.custom_minimum_size = Vector2(400, 0)
	side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_child(side)
	_history_card = UI.card()
	_history_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(_history_card)
	side.add_child(_build_note_card())


func on_show() -> void:
	refresh()


## Public so the shell can refresh it after a match, even while hidden.
func refresh() -> void:
	_rebuild_table()
	_rebuild_history()


# --------------------------------------------------------------------------
# Standings
# --------------------------------------------------------------------------

func _rebuild_table() -> void:
	_clear(_table_card)
	var standings: Array = Leaderboard.standings()
	var column := UI.vbox(UI.GAP)
	_table_card.add_child(column)

	var head := UI.hbox(UI.GAP)
	head.add_child(UI.kicker("积分榜"))
	var spring := Control.new()
	spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spring)
	head.add_child(UI.chip(tr("%d 位玩家") % standings.size(), QGPalette.TEXT_MUTED))
	column.add_child(head)

	if standings.is_empty():
		column.add_child(_build_empty_state())
		return

	column.add_child(UI.divider())
	column.add_child(_header_row())
	column.add_child(UI.divider())

	var rows := UI.vbox(2)
	for index in standings.size():
		rows.add_child(_standings_row(index, standings[index]))
	var scroll := UI.scroll(rows)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)

	column.add_child(UI.divider())
	column.add_child(UI.dim("初始 1200 分 · 每局按 Elo（K=32）结算"))


func _header_row() -> HBoxContainer:
	var row := UI.hbox(UI.GAP)
	row.add_child(_cell("名次", 52, HORIZONTAL_ALIGNMENT_LEFT, "DimLabel"))
	row.add_child(_cell("玩家", 0, HORIZONTAL_ALIGNMENT_LEFT, "DimLabel"))
	row.add_child(_cell("积分", 92, HORIZONTAL_ALIGNMENT_RIGHT, "DimLabel"))
	row.add_child(_cell("战绩", 120, HORIZONTAL_ALIGNMENT_RIGHT, "DimLabel"))
	row.add_child(_cell("胜率", 80, HORIZONTAL_ALIGNMENT_RIGHT, "DimLabel"))
	return row


func _standings_row(index: int, entry: Dictionary) -> PanelContainer:
	var name := String(entry.get("name", "玩家"))
	var is_me := name == _player_name()
	var panel := UI.card(true)
	if is_me:
		panel.theme_type_variation = &"RowPanelHot"
	else:
		panel.theme_type_variation = &"RowPanelAlt" if index % 2 == 1 else &"RowPanel"
	panel.custom_minimum_size = Vector2(0, 42)

	var row := UI.hbox(UI.GAP)
	panel.add_child(row)

	var rank := _cell("%d" % (index + 1), 52, HORIZONTAL_ALIGNMENT_LEFT, "H3Label")
	rank.add_theme_color_override("font_color", _rank_colour(index))
	row.add_child(rank)

	var name_label := _cell(name, 0, HORIZONTAL_ALIGNMENT_LEFT, "BodyLabel")
	if is_me:
		name_label.add_theme_color_override("font_color", QGPalette.ACCENT)
	row.add_child(name_label)

	row.add_child(_cell(str(int(entry.get("rating", 0))), 92, HORIZONTAL_ALIGNMENT_RIGHT, "H3Label"))
	row.add_child(_cell(tr("%d 胜 %d 负") % [int(entry.get("wins", 0)), int(entry.get("losses", 0))],
		120, HORIZONTAL_ALIGNMENT_RIGHT, "MutedLabel"))
	row.add_child(_cell("%d%%" % int(round(float(entry.get("win_rate", 0.0)) * 100.0)),
		80, HORIZONTAL_ALIGNMENT_RIGHT, "MutedLabel"))
	return panel


func _build_empty_state() -> Control:
	var centre := CenterContainer.new()
	centre.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var column := UI.vbox(UI.GAP)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.custom_minimum_size = Vector2(420, 0)

	var title := UI.h2("还没有排行记录")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var copy_line := UI.muted("完成第一局之后，双方的积分和胜率会出现在这里。", true)
	copy_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(copy_line)
	column.add_child(UI.spacer_h(UI.GAP_SM))
	var start := UI.button("去打一局", "PrimaryButton", 168)
	start.pressed.connect(func() -> void: shell.start_local_match())
	var button_row := UI.hbox(0)
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_child(start)
	column.add_child(button_row)
	centre.add_child(column)
	return centre


func _rank_colour(index: int) -> Color:
	match index:
		0:
			return QGPalette.WARNING
		1:
			return QGPalette.STONE_WHITE_EDGE
		2:
			return QGPalette.BOARD_WOOD_DARK
		_:
			return QGPalette.TEXT_MUTED


func _cell(text: String, width: int, alignment: HorizontalAlignment, variation: String) -> Label:
	var cell := UI.label(text, variation)
	cell.horizontal_alignment = alignment
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL if width == 0 else Control.SIZE_FILL
	if width > 0:
		cell.custom_minimum_size = Vector2(width, 0)
	return cell


# --------------------------------------------------------------------------
# Recent matches
# --------------------------------------------------------------------------

func _rebuild_history() -> void:
	_clear(_history_card)
	var history: Array = Leaderboard.history
	var column := UI.vbox(UI.GAP)
	_history_card.add_child(column)

	var head := UI.hbox(UI.GAP)
	head.add_child(UI.h2("最近对局"))
	var spring := Control.new()
	spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spring)
	head.add_child(UI.chip(tr("%d 盘") % history.size(), QGPalette.TEXT_MUTED))
	column.add_child(head)
	column.add_child(UI.divider())

	if history.is_empty():
		column.add_child(UI.spacer_h(UI.GAP_SM))
		column.add_child(UI.muted("还没有对局记录。", true))
		column.add_child(UI.dim("打完一盘回来就能在这里复盘。"))
		return

	var list := UI.vbox(UI.GAP_SM)
	for index in mini(history.size(), HISTORY_PREVIEW):
		if index > 0:
			list.add_child(UI.divider())
		list.add_child(_history_row(history[index]))
	column.add_child(list)

	if history.size() > HISTORY_PREVIEW:
		column.add_child(UI.dim(tr("仅显示最近 %d 盘，共 %d 盘") % [HISTORY_PREVIEW, history.size()]))


func _history_row(entry: Dictionary) -> VBoxContainer:
	var winner := int(entry.get("winner", QGTypes.WINNER_NONE))
	var black := String(entry.get("black", "黑方"))
	var white := String(entry.get("white", "白方"))

	var column := UI.vbox(2)
	var line := UI.hbox(UI.GAP_XS)
	line.add_child(_history_name(black, winner == QGTypes.WINNER_BLACK))
	line.add_child(UI.dim("vs"))
	line.add_child(_history_name(white, winner == QGTypes.WINNER_WHITE))
	var spring := Control.new()
	spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(spring)
	line.add_child(UI.dim(_winner_text(winner)))
	column.add_child(line)

	var detail := UI.hbox(UI.GAP_SM)
	detail.add_child(UI.dim(_short_date(String(entry.get("date", "")))))
	detail.add_child(UI.dim(L.board_text(int(entry.get("board_size", 9)))))
	detail.add_child(UI.dim("单机" if String(entry.get("mode", "local")) == "local" else "联机"))
	column.add_child(detail)
	return column


func _history_name(name: String, won: bool) -> Label:
	var label := UI.label(name, "BodyLabel")
	label.add_theme_color_override("font_color", QGPalette.ACCENT if won else QGPalette.TEXT_MUTED)
	return label


func _winner_text(winner: int) -> String:
	match winner:
		QGTypes.WINNER_BLACK:
			return "黑胜"
		QGTypes.WINNER_WHITE:
			return "白胜"
		_:
			return "和棋"


func _build_note_card() -> PanelContainer:
	var card := UI.card(true)
	var row := UI.hbox(UI.GAP)
	card.add_child(row)
	row.add_child(UI.status_dot(QGPalette.VIOLET, 6))
	row.add_child(UI.muted("在线排名之后会接入 Steam 排行榜；这一页的积分与战绩只保存在这台电脑上。", true))
	return card


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

func _short_date(raw: String) -> String:
	var cleaned := raw.replace("T", " ")
	if cleaned.length() >= 16:
		return cleaned.substr(5, 11)
	return cleaned


func _player_name() -> String:
	var name := Settings.player_name.strip_edges()
	return name if not name.is_empty() else "玩家"


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
