## 主菜单: title, the six entry points, and a footer with version + profile.
##
## This is also the only screen with no back button: it is the root of the router.
class_name QGMenuScreen
extends "res://src/ui/shell/screen.gd"

const Diagram := preload("res://src/ui/shell/widgets/quantum_diagram.gd")

var _version_label: Label = null
var _player_label: Label = null
var _board_label: Label = null
var _primary: Button = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := UI.page_margins()
	add_child(margin)
	UI.full_rect(margin)

	var column := UI.vbox(0)
	margin.add_child(column)

	var middle := UI.hbox(UI.GAP_XXL)
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(middle)

	middle.add_child(_build_menu_column())

	var diagram := Diagram.new()
	diagram.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	diagram.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_child(diagram)

	column.add_child(_build_footer())


func _build_menu_column() -> VBoxContainer:
	var column := UI.vbox(UI.GAP)
	column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	column.custom_minimum_size = Vector2(420, 0)

	column.add_child(UI.kicker("QUANTUM GO · 围棋变体"))
	column.add_child(UI.spacer_h(UI.GAP_SM))
	column.add_child(UI.hero("量子围棋"))

	var tagline := UI.muted("一子两处，现实分岔。提子观测，宇宙坍缩。", true)
	tagline.custom_minimum_size = Vector2(360, 0)
	column.add_child(UI.spacer_h(UI.GAP_SM))
	column.add_child(tagline)
	column.add_child(UI.spacer_h(UI.GAP_XL))

	var buttons := UI.vbox(10)
	buttons.custom_minimum_size = Vector2(330, 0)
	_primary = UI.button("单机双人", "PrimaryButton", 0, 52)
	_primary.pressed.connect(_on_local_pressed)
	buttons.add_child(_primary)
	buttons.add_child(_nav_button("新手引导", "tutorial"))
	buttons.add_child(_nav_button("联机对战", "lobby"))
	buttons.add_child(_nav_button("排行榜", "leaderboard"))
	buttons.add_child(_nav_button("规则", "rules"))
	buttons.add_child(_nav_button("设置", "settings"))
	column.add_child(buttons)

	column.add_child(UI.spacer_h(UI.GAP_SM))
	var quit := UI.button("退出游戏", "GhostButton", 330, 38)
	quit.pressed.connect(_on_quit_pressed)
	column.add_child(quit)

	column.add_child(UI.spacer_h(UI.GAP_SM))
	_board_label = UI.dim("")
	column.add_child(_board_label)
	return column


func _nav_button(text: String, screen_id: String) -> Button:
	var button := UI.button(text, "", 0, 46)
	button.pressed.connect(func() -> void: go(screen_id))
	return button


func _build_footer() -> VBoxContainer:
	var footer := UI.vbox(UI.GAP)
	footer.add_child(UI.divider())
	footer.add_child(UI.spacer_h(UI.GAP))
	var row := UI.hbox(UI.GAP_SM)
	_version_label = UI.dim("")
	row.add_child(_version_label)
	var spring := Control.new()
	spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spring)
	_player_label = UI.dim("")
	row.add_child(_player_label)
	var separator := UI.vertical_divider(12)
	separator.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(separator)
	row.add_child(UI.dim("设置里可修改玩家名称与默认棋盘"))
	footer.add_child(row)
	# Extra bottom breathing room so the footer does not sit on the last pixel.
	footer.add_child(UI.spacer_h(3))
	return footer


func on_show() -> void:
	_refresh_footer()
	if _primary != null:
		_primary.grab_focus()


func _refresh_footer() -> void:
	var version := String(ProjectSettings.get_setting("application/config/version", "1.0.0"))
	var engine_info := Engine.get_version_info()
	_version_label.text = "v%s · Godot %d.%d" % [version, int(engine_info.get("major", 4)), int(engine_info.get("minor", 6))]
	var display_name := _player_name()
	var default_name := "Player" if L.is_english() else "玩家"
	_player_label.text = default_name if display_name == default_name else tr("玩家：%s") % display_name
	_board_label.text = tr("单机默认 %s棋盘") % L.board_text(Settings.board_size)


func _player_name() -> String:
	var name := Settings.player_name.strip_edges()
	if name.is_empty():
		return "玩家"
	# The shipped default profile name is Chinese; show the English one when the
	# UI is English instead of a stray Chinese word in the footer.
	if name == "玩家" and L.is_english():
		return "Player"
	return name


func _on_local_pressed() -> void:
	shell.start_local_match()


func _on_quit_pressed() -> void:
	shell.quit_game()
