## Top bar of the match screen: brand, mode, turn indicator, action buttons.
##
## The HUD is a dumb surface: it renders what the match screen tells it and emits
## intent signals. All rules decisions live in match.gd / the session.
class_name QGMatchHud
extends PanelContainer

signal quantum_toggled(on: bool)
signal pass_pressed
signal resign_pressed
signal undo_pressed
signal exit_pressed
signal confirm_score_pressed

const UIKit := preload("res://src/ui/match/ui_kit.gd")

const DEFAULT_QUANTUM_TOOLTIP := "依次点击两个空点，把现实分裂成两个宇宙（也可按住 Shift 点击）"

var _mode_pill_label: Label = null
var _turn_dot: Panel = null
var _turn_label: Label = null
var _status_label: Label = null
var _quantum_button: Button = null
var _undo_button: Button = null
var _pass_button: Button = null
var _resign_button: Button = null
var _confirm_button: Button = null


func _ready() -> void:
	custom_minimum_size = Vector2(0.0, 64.0)
	add_theme_stylebox_override("panel", UIKit.panel_style())
	_build()


func _build() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 9)
	margin.add_theme_constant_override("margin_bottom", 9)
	add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	margin.add_child(row)

	# --- brand -------------------------------------------------------------
	var brand := VBoxContainer.new()
	brand.add_theme_constant_override("separation", 0)
	brand.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	brand.add_child(UIKit.make_label("量子围棋", 20, QGPalette.TEXT, true))
	var subtitle := UIKit.make_label("QUANTUM GO", 9, QGPalette.TEXT_DIM)
	brand.add_child(subtitle)
	row.add_child(brand)

	var mode_pill := PanelContainer.new()
	mode_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mode_pill.add_theme_stylebox_override(
		"panel", UIKit.flat_box(QGPalette.BG_PANEL_LIGHT, 6, QGPalette.BG_HOVER, 1, 9, 3)
	)
	_mode_pill_label = UIKit.make_label("本地双人", 11, QGPalette.TEXT_MUTED)
	mode_pill.add_child(_mode_pill_label)
	row.add_child(mode_pill)

	# --- turn / status -----------------------------------------------------
	var centre := VBoxContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	centre.add_theme_constant_override("separation", 1)
	row.add_child(centre)

	var turn_row := HBoxContainer.new()
	turn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	turn_row.add_theme_constant_override("separation", 9)
	centre.add_child(turn_row)

	_turn_dot = Panel.new()
	_turn_dot.custom_minimum_size = Vector2(14.0, 14.0)
	_turn_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_turn_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_turn_dot.add_theme_stylebox_override("panel", UIKit.stone_dot_style(QGTypes.BLACK, 14.0))
	turn_row.add_child(_turn_dot)

	_turn_label = UIKit.make_label("黑方行棋", 18, QGPalette.TEXT, true)
	turn_row.add_child(_turn_label)

	_status_label = UIKit.make_label("", 11, QGPalette.TEXT_MUTED)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.clip_text = true
	centre.add_child(_status_label)

	# --- actions -----------------------------------------------------------
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(actions)

	_quantum_button = UIKit.make_button("量子步", "toggle", 88.0)
	_quantum_button.toggle_mode = true
	_quantum_button.tooltip_text = DEFAULT_QUANTUM_TOOLTIP
	_quantum_button.toggled.connect(_on_quantum_toggled)
	actions.add_child(_quantum_button)

	_undo_button = UIKit.make_button("悔棋 U", "ghost", 78.0)
	_undo_button.tooltip_text = "撤销上一步（U，仅本地双人）"
	_undo_button.pressed.connect(func() -> void: undo_pressed.emit())
	actions.add_child(_undo_button)

	_pass_button = UIKit.make_button("停一手 P", "ghost", 86.0)
	_pass_button.tooltip_text = "在当前宇宙停一手（P）"
	_pass_button.pressed.connect(func() -> void: pass_pressed.emit())
	actions.add_child(_pass_button)

	_resign_button = UIKit.make_button("认输 R", "ghost", 78.0)
	_resign_button.tooltip_text = "认输（R），会先确认"
	_resign_button.pressed.connect(func() -> void: resign_pressed.emit())
	actions.add_child(_resign_button)

	# Scoring phase: the only action that matters is signing off on the result.
	_confirm_button = UIKit.make_button("确认结算", "primary", 110.0)
	_confirm_button.tooltip_text = "标记完死子后确认；双方都确认才结束对局"
	_confirm_button.pressed.connect(func() -> void: confirm_score_pressed.emit())
	_confirm_button.visible = false
	actions.add_child(_confirm_button)

	var exit_button := UIKit.make_button("退出", "ghost", 70.0)
	exit_button.tooltip_text = "返回主菜单"
	exit_button.pressed.connect(func() -> void: exit_pressed.emit())
	actions.add_child(exit_button)


# --------------------------------------------------------------------------
# Public surface used by match.gd
# --------------------------------------------------------------------------

func set_mode(mode: int) -> void:
	_mode_pill_label.text = UIKit.mode_text(mode)
	if mode == QGSession.Mode.LOCAL:
		_mode_pill_label.add_theme_color_override("font_color", QGPalette.TEXT_MUTED)
	else:
		_mode_pill_label.add_theme_color_override("font_color", QGPalette.ACCENT)


func set_turn(colour: int, text: String, waiting: bool) -> void:
	_turn_dot.add_theme_stylebox_override("panel", UIKit.stone_dot_style(colour, 14.0))
	_turn_label.text = text
	_turn_label.add_theme_color_override("font_color", QGPalette.WARNING if waiting else QGPalette.TEXT)


func set_status(text: String) -> void:
	_status_label.text = text


func set_quantum_checked(on: bool) -> void:
	_quantum_button.set_pressed_no_signal(on)


## One-line explanation shown while the 量子步 button is unavailable.
func set_quantum_reason(reason: String) -> void:
	if reason.is_empty():
		_quantum_button.tooltip_text = DEFAULT_QUANTUM_TOOLTIP
		_quantum_button.add_theme_color_override("font_disabled_color", QGPalette.TEXT_DIM)
	else:
		_quantum_button.tooltip_text = reason
		_quantum_button.add_theme_color_override("font_disabled_color", QGPalette.WARNING)


func set_quantum_enabled(on: bool) -> void:
	_quantum_button.disabled = not on


func quantum_checked() -> bool:
	return _quantum_button.button_pressed


func set_undo_enabled(on: bool) -> void:
	_undo_button.disabled = not on


func set_pass_enabled(on: bool) -> void:
	_pass_button.disabled = not on


func set_resign_enabled(on: bool) -> void:
	_resign_button.disabled = not on


## Scoring phase: moving and passing are over, so the action bar collapses to a
## single "confirm the result" button. Marking dead stones happens on the boards.
func set_scoring_mode(on: bool) -> void:
	_quantum_button.visible = not on
	_undo_button.visible = not on
	_pass_button.visible = not on
	_resign_button.visible = not on
	_confirm_button.visible = on


## Disables the confirm button once this side has signed off, and explains why.
func set_confirm_state(enabled: bool, text: String) -> void:
	_confirm_button.disabled = not enabled
	_confirm_button.text = text if not text.is_empty() else "确认结算"


func _on_quantum_toggled(on: bool) -> void:
	quantum_toggled.emit(on)
