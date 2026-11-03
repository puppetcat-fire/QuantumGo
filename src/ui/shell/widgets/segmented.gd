## A row of exclusive chips that behaves like a segmented control.
##
## Used wherever a value has a small fixed set of choices (board size). Chips are
## real buttons, so keyboard and screen readers work without extra code.
class_name QGSegmented
extends HBoxContainer

signal changed(index: int)

const UI := preload("res://src/ui/shell/ui_kit.gd")

var _buttons: Array[Button] = []
var _index: int = 0


func setup(options: Array, selected: int = 0) -> QGSegmented:
	add_theme_constant_override("separation", 6)
	var group := ButtonGroup.new()
	group.allow_unpress = false
	for option_index in options.size():
		var chip := UI.button(String(options[option_index]), "SegmentButton", 0, 36)
		chip.toggle_mode = true
		chip.button_group = group
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.toggled.connect(_on_toggled.bind(option_index))
		add_child(chip)
		_buttons.append(chip)
	set_selected(selected)
	return self


func get_selected() -> int:
	return _index


func set_selected(selected: int, emit: bool = false) -> void:
	if _buttons.is_empty():
		_index = selected
		return
	_index = clampi(selected, 0, _buttons.size() - 1)
	for button_index in _buttons.size():
		_buttons[button_index].set_pressed_no_signal(button_index == _index)
	if emit:
		changed.emit(_index)


func _on_toggled(on: bool, index: int) -> void:
	if not on:
		return
	_index = index
	changed.emit(_index)
