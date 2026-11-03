## A compact integer stepper: [−] [value] [+].
##
## Ports and small numbers do not deserve a SpinBox: this keeps one visual
## language (ghost buttons + one LineEdit) and clamps/reports a clean int.
class_name QGNumberField
extends HBoxContainer

signal value_changed(value: int)

const UI := preload("res://src/ui/shell/ui_kit.gd")
const TH := preload("res://src/ui/theme/qg_theme.gd")

var min_value: int = 0
var max_value: int = 65535
var step: int = 1

var _value: int = 0
var _built: bool = false
var _line: LineEdit = null
var _minus: Button = null
var _plus: Button = null


func configure(min_v: int, max_v: int, initial: int, step_value: int = 1) -> QGNumberField:
	min_value = min_v
	max_value = max_v
	step = step_value
	if not _built:
		_build()
	set_value(initial)
	return self


func get_value() -> int:
	return _value


func set_value(new_value: int, emit: bool = false) -> void:
	var clamped := clampi(new_value, min_value, max_value)
	var changed := clamped != _value
	_value = clamped
	if _built:
		if _line.text != str(_value):
			_line.text = str(_value)
		_refresh_buttons()
	if emit and changed:
		value_changed.emit(_value)


func _build() -> void:
	_built = true
	add_theme_constant_override("separation", 6)

	_minus = UI.button("−", "GhostButton", 42, TH.INPUT_HEIGHT)
	_minus.focus_mode = Control.FOCUS_NONE
	_minus.add_theme_font_size_override("font_size", 20)
	_minus.pressed.connect(_on_step.bind(-1))
	add_child(_minus)

	_line = UI.line_edit("", "", 96)
	_line.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line.max_length = 7
	_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_line.text_changed.connect(_on_text_changed)
	_line.text_submitted.connect(func(_text: String) -> void: _commit_text())
	_line.focus_exited.connect(_commit_text)
	add_child(_line)

	_plus = UI.button("+", "GhostButton", 42, TH.INPUT_HEIGHT)
	_plus.focus_mode = Control.FOCUS_NONE
	_plus.add_theme_font_size_override("font_size", 20)
	_plus.pressed.connect(_on_step.bind(1))
	add_child(_plus)


func _on_step(direction: int) -> void:
	set_value(_value + direction * step, true)


func _on_text_changed(text: String) -> void:
	# Keep the field numeric without fighting the caret: strip anything else.
	var cleaned := ""
	for character in text:
		if character >= "0" and character <= "9":
			cleaned += character
	if cleaned != text:
		_line.text = cleaned
		_line.caret_column = cleaned.length()


func _commit_text() -> void:
	var typed := _line.text.strip_edges()
	if typed.is_empty():
		_line.text = str(_value)
		return
	set_value(int(typed), true)


func _refresh_buttons() -> void:
	if _minus == null:
		return
	_minus.disabled = _value <= min_value
	_plus.disabled = _value >= max_value
