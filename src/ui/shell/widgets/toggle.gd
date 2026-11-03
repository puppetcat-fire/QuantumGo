## A designed on/off switch.
##
## Godot's CheckButton brings stock light-theme icons that read as "unfinished"
## next to a dark custom UI, so the switch is drawn: a rounded track and a knob.
## It is still a `BaseButton` with `toggle_mode`, so keyboard focus, hover,
## disabled and `toggled` all behave exactly like a built-in control.
class_name QGToggle
extends BaseButton

const TH := preload("res://src/ui/theme/qg_theme.gd")

var _track_off: StyleBoxFlat = null
var _track_on: StyleBoxFlat = null
var _focus: StyleBoxFlat = null
var _t: float = 0.0
var _tween: Tween = null


func _init() -> void:
	toggle_mode = true
	custom_minimum_size = Vector2(54, 30)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_track_off = TH.box(QGPalette.BG_PANEL_LIGHT, 13, 1, TH.hairline(0.14))
	_track_on = TH.box(QGPalette.ACCENT, 13)
	_focus = TH.box(Color(0, 0, 0, 0), 15, 1, Color(QGPalette.ACCENT, 0.6))
	toggled.connect(_on_toggled)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


## Sets the switch without emitting `toggled`, and snaps the animation. Used
## when loading persisted settings.
func set_on(value: bool) -> void:
	set_pressed_no_signal(value)
	_t = 1.0 if value else 0.0
	queue_redraw()


func is_on() -> bool:
	return button_pressed


func _on_toggled(on: bool) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_set_progress, _t, 1.0 if on else 0.0, 0.16) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _set_progress(value: float) -> void:
	_t = value
	queue_redraw()


func _draw() -> void:
	var track_height := minf(size.y, 26.0)
	var rect := Rect2(0.0, (size.y - track_height) * 0.5, size.x, track_height)
	draw_style_box(_track_off, rect)
	if _t > 0.001:
		_track_on.bg_color.a = clampf(_t, 0.0, 1.0)
		draw_style_box(_track_on, rect)

	var knob_radius := track_height * 0.5 - 4.0
	var knob_x := lerpf(knob_radius + 4.0, size.x - knob_radius - 4.0, _t)
	var knob_centre := Vector2(knob_x, size.y * 0.5)
	draw_circle(knob_centre + Vector2(0, 1), knob_radius + 1.0, Color(QGPalette.BG_DEEP, 0.45))
	draw_circle(knob_centre, knob_radius, QGPalette.TEXT)

	if has_focus():
		draw_style_box(_focus, Rect2(-3, -3, size.x + 6, size.y + 6))
