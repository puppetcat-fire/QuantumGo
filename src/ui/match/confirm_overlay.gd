## Small modal confirmation dialog used by the match screen (resign / leave).
class_name QGConfirmOverlay
extends Control

signal confirmed
signal cancelled

const UIKit := preload("res://src/ui/match/ui_kit.gd")

var _title: Label = null
var _body: Label = null
var _confirm_button: Button = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()


func _build() -> void:
	var scrim := ColorRect.new()
	scrim.color = Color(QGPalette.BG_DEEP, 0.74)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(460.0, 0.0)
	panel.add_theme_stylebox_override(
		"panel", UIKit.flat_box(QGPalette.BG_PANEL, 12, QGPalette.BG_HOVER, 1)
	)
	centre.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	_title = UIKit.make_label("确认", 21, QGPalette.TEXT, true)
	column.add_child(_title)

	_body = UIKit.make_label("", 13, QGPalette.TEXT_MUTED)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(408.0, 0.0)
	column.add_child(_body)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 4.0)
	column.add_child(spacer)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(buttons)

	var cancel_button := UIKit.make_button("取消", "ghost", 110.0)
	cancel_button.custom_minimum_size = Vector2(110.0, 38.0)
	cancel_button.pressed.connect(_on_cancel)
	buttons.add_child(cancel_button)

	_confirm_button = UIKit.make_button("确认", "danger", 130.0)
	_confirm_button.custom_minimum_size = Vector2(130.0, 38.0)
	_confirm_button.pressed.connect(_on_confirm)
	buttons.add_child(_confirm_button)


func open(title: String, body: String, confirm_text: String, danger: bool = true) -> void:
	_title.text = title
	_body.text = body
	_confirm_button.text = confirm_text
	UIKit.style_button(_confirm_button, "danger" if danger else "accent")
	visible = true


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


func _on_confirm() -> void:
	close()
	confirmed.emit()


func _on_cancel() -> void:
	close()
	cancelled.emit()
