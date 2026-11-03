## 设置: everything the player can tune, persisted through the `Settings` autoload.
##
## The screen edits the controls, applies audio immediately for feedback, and
## writes everything with `Settings.save_settings()` on 保存设置.
class_name QGSettingsScreen
extends "res://src/ui/shell/screen.gd"

const NF := preload("res://src/ui/shell/widgets/number_field.gd")
const SEG := preload("res://src/ui/shell/widgets/segmented.gd")
const TG := preload("res://src/ui/shell/widgets/toggle.gd")

const BOARD_SIZES := [5, 9, 13, 19]
const BOARD_LABELS := ["5 路", "9 路", "13 路", "19 路"]

const DEFAULTS := {
	"board_size": 9,
	"player_name": "玩家",
	"server_port": 27777,
	"master_volume": 0.8,
	"music_volume": 0.7,
	"music_enabled": true,
	"show_coordinates": true,
	"animation_speed": 1.0,
	"language": "auto",
}

const LANGUAGE_VALUES := ["auto", "zh", "en"]
const LANGUAGE_LABELS := ["跟随系统", "中文", "English"]

var _name_edit: LineEdit = null
var _board: QGSegmented = null
var _port: NF = null
var _volume: HSlider = null
var _volume_label: Label = null
var _music_toggle: QGToggle = null
var _music_volume: HSlider = null
var _music_volume_label: Label = null
var _speed: HSlider = null
var _speed_label: Label = null
var _coordinates: QGToggle = null
var _language: QGSegmented = null
var _saved_label: Label = null


func _ready() -> void:
	build_page("设置", "对局与显示", "改动会保存在本机；保存后立即生效，重启游戏仍然保留。")
	add_topbar_note("本机配置")

	var columns := UI.hbox(UI.GAP_LG)
	columns.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	content.add_child(columns)

	columns.add_child(_build_game_card())
	columns.add_child(_build_display_card())
	var spring := Control.new()
	spring.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(spring)
	content.add_child(_build_bottom_bar())
	_load_from_settings()


func on_show() -> void:
	_load_from_settings()


# --------------------------------------------------------------------------
# Cards
# --------------------------------------------------------------------------

func _build_game_card() -> PanelContainer:
	var card := UI.card()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := UI.vbox(UI.GAP)
	card.add_child(column)

	column.add_child(UI.section_heading("对战"))
	column.add_child(UI.divider())

	_name_edit = UI.line_edit("你的名字", Settings.player_name, 220)
	_name_edit.max_length = 16
	column.add_child(UI.setting_row("玩家名称", "记入排行榜，联机时显示给对手", _name_edit))
	column.add_child(UI.divider())

	_board = SEG.new().setup(BOARD_LABELS, 1)
	_board.custom_minimum_size = Vector2(300, 0)
	column.add_child(UI.setting_row("默认棋盘", "单机对局和创建房间时的默认大小", _board))
	column.add_child(UI.divider())

	_port = NF.new().configure(1024, 65535, Settings.server_port)
	column.add_child(UI.setting_row("服务器端口", "房主监听、客方默认连接的端口", _port))
	column.add_child(UI.divider())

	var speed_row := UI.hbox(UI.GAP_SM)
	_speed = _make_slider(0.5, 2.0, 0.1, Settings.animation_speed, 200)
	_speed.value_changed.connect(_on_speed_changed)
	speed_row.add_child(_speed)
	_speed_label = UI.label("", "BodyLabel")
	_speed_label.custom_minimum_size = Vector2(58, 0)
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	speed_row.add_child(_speed_label)
	column.add_child(UI.setting_row("动画速度", "落子与坍缩动画的播放速度", speed_row))
	return card


func _build_display_card() -> PanelContainer:
	var card := UI.card()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := UI.vbox(UI.GAP)
	card.add_child(column)

	column.add_child(UI.section_heading("显示与声音"))
	column.add_child(UI.divider())

	_language = SEG.new()
	_language.setup(LANGUAGE_LABELS, _language_index(Settings.language))
	_language.changed.connect(func(_index: int) -> void: _mark_dirty())
	column.add_child(UI.setting_row("语言", "界面语言，切换后立即生效", _language))
	column.add_child(UI.divider())

	_coordinates = TG.new()
	_coordinates.toggled.connect(func(_on: bool) -> void: _mark_dirty())
	column.add_child(UI.setting_row("显示坐标", "在棋盘边缘标出 A–T 与 1–19", _coordinates))
	column.add_child(UI.divider())

	# Phantom stones are deliberately not a setting: they must stay invisible while
	# a match is in progress. They appear on the replay screen instead.
	var volume_row := UI.hbox(UI.GAP_SM)
	_volume = _make_slider(0.0, 1.0, 0.05, Settings.master_volume, 200)
	_volume.value_changed.connect(_on_volume_changed)
	volume_row.add_child(_volume)
	_volume_label = UI.label("", "BodyLabel")
	_volume_label.custom_minimum_size = Vector2(58, 0)
	_volume_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	volume_row.add_child(_volume_label)
	column.add_child(UI.setting_row("主音量", "对局音效的总体音量", volume_row))

	column.add_child(UI.divider())
	_music_toggle = TG.new()
	_music_toggle.toggled.connect(func(_on: bool) -> void: _mark_dirty())
	column.add_child(UI.setting_row("背景音乐", "关闭后只保留落子与坍缩音效", _music_toggle))

	column.add_child(UI.divider())
	var music_row := UI.hbox(UI.GAP_SM)
	_music_volume = _make_slider(0.0, 1.0, 0.05, Settings.music_volume, 200)
	_music_volume.value_changed.connect(_on_music_volume_changed)
	music_row.add_child(_music_volume)
	_music_volume_label = UI.label("", "BodyLabel")
	_music_volume_label.custom_minimum_size = Vector2(58, 0)
	_music_volume_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	music_row.add_child(_music_volume_label)
	column.add_child(UI.setting_row("音乐音量", "相对主音量的比例", music_row))

	column.add_child(UI.spacer_h(UI.GAP_SM))
	var note := UI.card(true)
	var note_row := UI.hbox(UI.GAP_SM)
	note.add_child(note_row)
	note_row.add_child(UI.status_dot(QGPalette.TEXT_DIM, 6))
	note_row.add_child(UI.muted("动画速度较快时，坍缩动画可能被跳过，对局结果不受影响。", true))
	column.add_child(note)
	return card


func _build_bottom_bar() -> HBoxContainer:
	var row := UI.hbox(UI.GAP)
	row.add_child(UI.dim("设置保存在本机。", false))
	_saved_label = UI.label("已保存", "DimLabel")
	_saved_label.add_theme_color_override("font_color", QGPalette.SUCCESS)
	_saved_label.visible = false
	row.add_child(_saved_label)
	var spring := Control.new()
	spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spring)

	var reset := UI.button("恢复默认", "GhostButton", 132)
	reset.pressed.connect(_on_reset_pressed)
	row.add_child(reset)
	var save := UI.button("保存设置", "PrimaryButton", 168)
	save.pressed.connect(_on_save_pressed)
	row.add_child(save)
	return row


func _make_slider(min_value: float, max_value: float, step: float, value: float, width: int) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = value
	slider.custom_minimum_size = Vector2(width, 30)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return slider


# --------------------------------------------------------------------------
# State
# --------------------------------------------------------------------------

func _load_from_settings() -> void:
	if _name_edit == null:
		return
	_name_edit.text = Settings.player_name
	_board.set_selected(_board_index(Settings.board_size))
	_port.set_value(Settings.server_port)
	_volume.set_value_no_signal(Settings.master_volume)
	_music_volume.set_value_no_signal(Settings.music_volume)
	_music_toggle.set_on(Settings.music_enabled)
	_language.set_selected(_language_index(Settings.language))
	_speed.set_value_no_signal(Settings.animation_speed)
	_coordinates.set_on(Settings.show_coordinates)
	_refresh_value_labels()


func _refresh_value_labels() -> void:
	if _volume_label == null:
		return
	_volume_label.text = "%d%%" % int(round(_volume.value * 100.0))
	_music_volume_label.text = "%d%%" % int(round(_music_volume.value * 100.0))
	_music_volume.editable = _music_toggle.is_on()
	_speed_label.text = "%.1f×" % _speed.value


func _on_volume_changed(_value: float) -> void:
	_refresh_value_labels()
	_apply_volume(_volume.value)
	_mark_dirty()


func _on_music_volume_changed(_value: float) -> void:
	_refresh_value_labels()
	_apply_music()
	_mark_dirty()


func _apply_music() -> void:
	Settings.music_volume = clampf(_music_volume.value, 0.0, 1.0)
	Settings.music_enabled = _music_toggle.is_on()
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("refresh_audio_settings"):
		sfx.refresh_audio_settings()


func _apply_language() -> void:
	Settings.language = _selected_language()
	var locale := get_node_or_null("/root/L")
	if locale != null and locale.has_method("set_language"):
		locale.call("set_language", Settings.language)


func _language_index(value: String) -> int:
	var index := LANGUAGE_VALUES.find(value)
	return index if index >= 0 else 0


func _selected_language() -> String:
	var index := _language.get_selected()
	if index < 0 or index >= LANGUAGE_VALUES.size():
		return "auto"
	return String(LANGUAGE_VALUES[index])


func _on_speed_changed(_value: float) -> void:
	_refresh_value_labels()
	_mark_dirty()


func _apply_volume(value: float) -> void:
	var clamped := clampf(value, 0.0, 1.0)
	AudioServer.set_bus_mute(0, clamped <= 0.001)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(clamped, 0.001)))


func _on_save_pressed() -> void:
	var player_name := _name_edit.text.strip_edges()
	Settings.player_name = player_name if not player_name.is_empty() else String(DEFAULTS["player_name"])
	Settings.board_size = _selected_board_size()
	Settings.server_port = int(_port.get_value())
	Settings.master_volume = clampf(_volume.value, 0.0, 1.0)
	Settings.music_volume = clampf(_music_volume.value, 0.0, 1.0)
	Settings.music_enabled = _music_toggle.is_on()
	Settings.language = _selected_language()
	Settings.show_coordinates = _coordinates.is_on()
	Settings.animation_speed = _speed.value
	Settings.save_settings()
	_apply_volume(Settings.master_volume)
	_apply_music()
	_apply_language()
	_name_edit.text = Settings.player_name
	if shell != null:
		shell.toast("设置已保存")
	_flash_saved()


func _on_reset_pressed() -> void:
	_name_edit.text = String(DEFAULTS["player_name"])
	_board.set_selected(_board_index(int(DEFAULTS["board_size"])))
	_port.set_value(int(DEFAULTS["server_port"]))
	_volume.set_value_no_signal(float(DEFAULTS["master_volume"]))
	_music_volume.set_value_no_signal(float(DEFAULTS["music_volume"]))
	_music_toggle.set_on(bool(DEFAULTS["music_enabled"]))
	_language.set_selected(_language_index(String(DEFAULTS["language"])))
	_speed.set_value_no_signal(float(DEFAULTS["animation_speed"]))
	_coordinates.set_on(bool(DEFAULTS["show_coordinates"]))
	_refresh_value_labels()
	_apply_volume(_volume.value)
	_apply_music()
	_mark_dirty()


func _mark_dirty() -> void:
	if _saved_label != null:
		_saved_label.visible = false


func _flash_saved() -> void:
	if _saved_label == null:
		return
	_saved_label.visible = true
	await get_tree().create_timer(2.2).timeout
	if is_instance_valid(_saved_label):
		_saved_label.visible = false


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

func _selected_board_size() -> int:
	if _board == null:
		return int(DEFAULTS["board_size"])
	return int(BOARD_SIZES[_board.get_selected()])


func _board_index(size: int) -> int:
	var index := BOARD_SIZES.find(size)
	return index if index >= 0 else 1
