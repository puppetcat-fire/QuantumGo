## The shell's background: a vertical navy gradient, two soft universe glows and
## a barely-there grid. Everything drawn, so it costs no texture memory and
## scales with any window size.
class_name QGBackdrop
extends Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	if size.x < 2.0 or size.y < 2.0:
		return
	_draw_gradient()
	_draw_grid()
	_glow(Vector2(size.x * 0.88, size.y * 0.06), minf(size.x, size.y) * 0.62,
		QGPalette.VIOLET, 0.05)
	_glow(Vector2(size.x * 0.02, size.y * 1.02), minf(size.x, size.y) * 0.66,
		QGPalette.ACCENT, 0.035)
	_draw_rings()


func _draw_gradient() -> void:
	var bands := 48
	var band_height := size.y / float(bands)
	for band in bands:
		var t := float(band) / float(bands - 1)
		var colour := QGPalette.BG_PANEL_LIGHT.lerp(QGPalette.BG_DEEP, 0.35 + t * 0.65)
		draw_rect(Rect2(0.0, band * band_height, size.x, band_height + 1.0), colour)


func _draw_grid() -> void:
	var step := 96.0
	var colour := Color(QGPalette.TEXT, 0.014)
	var x := step
	while x < size.x:
		draw_line(Vector2(x, 0.0), Vector2(x, size.y), colour, 1.0)
		x += step
	var y := step
	while y < size.y:
		draw_line(Vector2(0.0, y), Vector2(size.x, y), colour, 1.0)
		y += step


func _glow(centre: Vector2, radius: float, colour: Color, peak: float) -> void:
	var steps := 14
	for step in steps:
		var t := float(step) / float(steps - 1)
		var current_radius := radius * (1.0 - t * 0.82)
		draw_circle(centre, current_radius, Color(colour, peak / steps * 1.6))


func _draw_rings() -> void:
	var centre := Vector2(size.x * 0.88, size.y * 0.06)
	var base := minf(size.x, size.y) * 0.34
	for ring in 3:
		var radius := base + ring * 90.0
		draw_arc(centre, radius, PI * 0.55, PI * 1.65, 96, Color(QGPalette.TEXT, 0.03), 1.0, true)
