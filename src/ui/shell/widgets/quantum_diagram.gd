## The product's one illustration: a quantum move splitting reality in two.
##
## Drawn rather than imported, so it stays sharp at any size and needs no art
## pipeline. It is the menu's hero image and the rules page's diagram, which is
## deliberate: the same picture a player sees before their first game is the one
## that explains the variant.
class_name QGQuantumDiagram
extends Control

const ACCENT_A := QGPalette.ACCENT
const ACCENT_B := QGPalette.PHANTOM_TINT

var _time: float = 0.0
var _animate: bool = true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func set_animated(value: bool) -> void:
	_animate = value
	set_process(value)
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var unit := minf(size.x, size.y)
	if unit < 80.0:
		return
	var radius := unit * 0.255
	var centre := size * 0.5 + Vector2(0.0, -unit * 0.04)
	var spread := radius * 1.12
	var left_centre := centre + Vector2(-spread, 0.0)
	var right_centre := centre + Vector2(spread, 0.0)
	var font := QGPalette.font()
	var font_size := clampi(int(unit / 26.0), 11, 14)
	var pulse := 0.5 + 0.5 * sin(_time * 1.6) if _animate else 0.55

	# Two universes: a board each, so the picture reads as "Go, twice".
	_universe_disc(left_centre, radius, ACCENT_A, 0.035, 0.55)
	_universe_disc(right_centre, radius, ACCENT_B, 0.045, 0.5)
	var grid_extent := radius * 0.56
	var grid_step := grid_extent / 2.0
	_board_grid(left_centre, grid_extent, grid_step, ACCENT_A)
	_board_grid(right_centre, grid_extent, grid_step, ACCENT_B)

	# The dashed "both at once" link between the two placements, behind the stones.
	_dashed_line(left_centre, right_centre, Color(QGPalette.TEXT, 0.26), 7.0)

	# The stone in each branch: real on the left, phantom on the right.
	var stone_radius := grid_step * 0.52
	var stone_a := left_centre
	var stone_b := right_centre
	draw_circle(stone_a + Vector2(0, 2), stone_radius + 1.0, Color(QGPalette.BG_DEEP, 0.6))
	draw_circle(stone_a, stone_radius, QGPalette.STONE_BLACK)
	draw_arc(stone_a, stone_radius, 0.0, TAU, 40, QGPalette.STONE_BLACK_EDGE, 1.4, true)
	draw_circle(stone_b + Vector2(0, 2), stone_radius + 1.0, Color(QGPalette.BG_DEEP, 0.45))
	draw_circle(stone_b, stone_radius, Color(ACCENT_B, 0.22 + 0.12 * pulse))
	draw_arc(stone_b, stone_radius, 0.0, TAU, 40, Color(ACCENT_B, 0.9), 1.6, true)

	# Labels under each universe.
	var label_width := radius * 2.4
	draw_string(font, Vector2(left_centre.x - label_width * 0.5, centre.y + radius + font_size + 20.0),
		tr("宇宙 A · 权重 50%"), HORIZONTAL_ALIGNMENT_CENTER, label_width, font_size,
		Color(QGPalette.TEXT_MUTED, 0.95))
	draw_string(font, Vector2(right_centre.x - label_width * 0.5, centre.y + radius + font_size + 20.0),
		tr("宇宙 B · 权重 50%"), HORIZONTAL_ALIGNMENT_CENTER, label_width, font_size,
		Color(QGPalette.TEXT_MUTED, 0.95))

	# Branch captions: the sentence that actually teaches the rule.
	draw_string(font, Vector2(left_centre.x - label_width * 0.5, centre.y - radius - 16.0),
		tr("实子"), HORIZONTAL_ALIGNMENT_CENTER, label_width, font_size, Color(ACCENT_A, 0.9))
	draw_string(font, Vector2(right_centre.x - label_width * 0.5, centre.y - radius - 16.0),
		tr("虚子"), HORIZONTAL_ALIGNMENT_CENTER, label_width, font_size, Color(ACCENT_B, 0.95))

	draw_string(font, Vector2(0.0, centre.y + radius + font_size * 2.0 + 40.0),
		tr("一次量子落子 → 两个宇宙；虚子被提 → 该宇宙坍缩"),
		HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, Color(QGPalette.TEXT_DIM, 0.95))


func _universe_disc(centre: Vector2, radius: float, colour: Color, fill: float, ring: float) -> void:
	for step in 3:
		var halo_radius := radius + 14.0 + step * 12.0
		draw_circle(centre, halo_radius, Color(colour, 0.012))
	draw_circle(centre, radius, Color(colour, fill))
	draw_arc(centre, radius, 0.0, TAU, 96, Color(colour, ring), 1.4, true)


func _board_grid(centre: Vector2, extent: float, step: float, colour: Color) -> void:
	var line_colour := Color(colour, 0.13)
	for index in 5:
		var offset := -extent + index * step
		draw_line(centre + Vector2(offset, -extent), centre + Vector2(offset, extent),
			line_colour, 1.0, true)
		draw_line(centre + Vector2(-extent, offset), centre + Vector2(extent, offset),
			line_colour, 1.0, true)
	for corner_x in [-1.0, 1.0]:
		for corner_y in [-1.0, 1.0]:
			draw_circle(centre + Vector2(corner_x, corner_y) * extent, 1.6, Color(colour, 0.3))


func _dashed_line(from_point: Vector2, to_point: Vector2, colour: Color, dash: float) -> void:
	var length := from_point.distance_to(to_point)
	if length <= 0.01:
		return
	var direction := (to_point - from_point) / length
	var travelled := 0.0
	while travelled < length:
		var dash_end := minf(travelled + dash, length)
		draw_line(from_point + direction * travelled, from_point + direction * dash_end, colour, 1.2, true)
		travelled = dash_end + dash
