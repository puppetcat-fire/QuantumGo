## One universe drawn as a Go board.
##
## This widget is pure presentation: it is fed a snapshot of a QGGame.Universe
## every time the session changes, and it emits `point_clicked(index)` when the
## player clicks an intersection. It never touches the rules engine or the
## session, so the same widget renders live universes, the focused universe and
## the spectator view without branching.
class_name QGBoardView
extends Control

signal point_clicked(index: int)

const UIKit := preload("res://src/ui/match/ui_kit.gd")

const COORD_LETTERS := "ABCDEFGHJKLMNOPQRST"

var board_size: int = 9
var board_position: QGPosition = null
var sealed: bool = false
var last_move: int = -1
var ko_point: int = -1
var interactive: bool = false
var quantum_mode: bool = false
## Scoring phase: stones marked dead, dimmed and crossed out.
var dead_points: Array[int] = []
## Phantom stones are indistinguishable during play — that uncertainty is the
## game. Only the tutorial, the result screen and the replay turn this on.
var reveal_phantoms: bool = false
var pending_a: int = -1
var acting_color: int = QGTypes.EMPTY

var _hover_index: int = -1
var _show_coords: bool = true
var _coords_enabled: bool = true
var _wood_style: StyleBoxFlat = null
var _sealed_style: StyleBoxFlat = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	_wood_style = UIKit.flat_box(QGPalette.BOARD_WOOD, 8, QGPalette.BOARD_WOOD_DARK, 2)
	_sealed_style = UIKit.flat_box(Color(QGPalette.BG_DEEP, 0.30), 8)
	resized.connect(queue_redraw)
	mouse_exited.connect(_on_mouse_exited)
	var settings := get_node_or_null("/root/Settings")
	if settings != null and "show_coordinates" in settings:
		_show_coords = bool(settings.get("show_coordinates"))


## Copies one universe snapshot into the widget. Called by the card, not by the
## session: the widget must stay a dumb view.
func apply_state(
	p_position: QGPosition,
	p_sealed: bool,
	p_last_move: int,
	p_ko_point: int,
	p_can_play: bool,
	p_acting_colour: int,
	p_quantum_mode: bool,
	p_pending_a: int,
	p_show_coords: bool = true,
	p_dead_points: Array[int] = [],
	p_reveal_phantoms: bool = false
) -> void:
	board_position = p_position
	board_size = p_position.size if p_position != null else board_size
	sealed = p_sealed
	last_move = p_last_move
	ko_point = p_ko_point
	interactive = p_can_play
	acting_color = p_acting_colour
	quantum_mode = p_quantum_mode
	pending_a = p_pending_a
	_coords_enabled = p_show_coords
	dead_points = p_dead_points
	reveal_phantoms = p_reveal_phantoms
	_hover_index = -1
	# Non-interactive boards (waiting for the opponent, thumbnails) let the click
	# bubble up to the card so clicking them still focuses that universe.
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_PASS
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if interactive else Control.CURSOR_ARROW
	queue_redraw()


## Test/shell hook: behaves like a click on `index` and emits `point_clicked`.
## Authorisation is decided by the match screen (it owns the session).
func activate_point(index: int) -> void:
	if index < 0 or index >= board_size * board_size:
		return
	point_clicked.emit(index)


func hovered_index() -> int:
	return _hover_index


# --------------------------------------------------------------------------
# Input
# --------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var index := _index_at(event.position)
		if index != _hover_index:
			_hover_index = index
			queue_redraw()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if not interactive:
			return
		var index := _index_at(event.position)
		if index >= 0:
			activate_point(index)
			accept_event()


func _on_mouse_exited() -> void:
	if _hover_index != -1:
		_hover_index = -1
		queue_redraw()


# --------------------------------------------------------------------------
# Geometry
# --------------------------------------------------------------------------

## Board layout in local coordinates. A Go board is square with a little wood
## margin on every side; the margin also hosts the coordinate labels.
func _geometry() -> Dictionary:
	var side := minf(size.x, size.y)
	var outer := maxf(2.0, side * 0.010)
	var wood_side := side - outer * 2.0
	var n := maxi(board_size, 2)
	var spacing := wood_side / float(n + 0.5)
	var edge := spacing * 0.75
	var wood_pos := (size - Vector2(wood_side, wood_side)) * 0.5
	var origin := wood_pos + Vector2(edge, edge)
	return {
		"side": side,
		"spacing": spacing,
		"radius": spacing * 0.47,
		"origin": origin,
		"wood_pos": wood_pos,
		"wood_side": wood_side,
		"wood_rect": Rect2(wood_pos, Vector2(wood_side, wood_side)),
	}


func _index_at(local: Vector2) -> int:
	if board_position == null or board_size <= 0:
		return -1
	var geo := _geometry()
	var origin: Vector2 = geo["origin"]
	var spacing: float = geo["spacing"]
	var rel := local - origin
	var col := int(roundf(rel.x / spacing))
	var row := int(roundf(rel.y / spacing))
	if col < 0 or col >= board_size or row < 0 or row >= board_size:
		return -1
	var centre := origin + Vector2(float(col) * spacing, float(row) * spacing)
	if (local - centre).length() > spacing * 0.58:
		return -1
	return row * board_size + col


func _centre_of(index: int, origin: Vector2, spacing: float) -> Vector2:
	@warning_ignore("integer_division")
	var row: int = index / board_size
	var col: int = index % board_size
	return origin + Vector2(float(col) * spacing, float(row) * spacing)


# --------------------------------------------------------------------------
# Drawing
# --------------------------------------------------------------------------

func _draw() -> void:
	if board_position == null or board_size <= 0:
		return
	var geo := _geometry()
	var side: float = geo["side"]
	if side < 24.0:
		return
	var wood_rect: Rect2 = geo["wood_rect"]
	var origin: Vector2 = geo["origin"]
	var spacing: float = geo["spacing"]
	var radius: float = geo["radius"]
	var n := board_size

	draw_style_box(_wood_style, wood_rect)
	_draw_wood_grain(wood_rect, side)
	_draw_grid(origin, spacing, n)
	_draw_star_points(origin, spacing, n)
	_draw_coordinates(geo, n)
	_draw_stones(origin, spacing, radius, n)
	_draw_last_move(origin, spacing, radius)
	_draw_ko_marker(origin, spacing)
	_draw_hover(origin, spacing, radius)
	_draw_pending_a(origin, spacing, radius)
	if sealed:
		draw_style_box(_sealed_style, wood_rect)


func _draw_wood_grain(rect: Rect2, side: float) -> void:
	var grain := QGPalette.BOARD_WOOD_DARK
	var fractions := [0.07, 0.16, 0.27, 0.38, 0.52, 0.63, 0.74, 0.86, 0.95]
	var alphas := [0.05, 0.035, 0.06, 0.03, 0.05, 0.04, 0.06, 0.03, 0.045]
	var width := maxf(1.0, side * 0.003)
	for i in range(fractions.size()):
		var y := rect.position.y + rect.size.y * float(fractions[i])
		draw_line(
			Vector2(rect.position.x + rect.size.x * 0.03, y),
			Vector2(rect.position.x + rect.size.x * 0.97, y),
			Color(grain, float(alphas[i])),
			width,
			true
		)
	for x_fraction in [0.17, 0.41, 0.66, 0.90]:
		var x := rect.position.x + rect.size.x * float(x_fraction)
		draw_line(
			Vector2(x, rect.position.y + rect.size.y * 0.04),
			Vector2(x, rect.position.y + rect.size.y * 0.96),
			Color(grain, 0.022),
			width,
			true
		)


func _draw_grid(origin: Vector2, spacing: float, n: int) -> void:
	var line_width := maxf(1.0, spacing * 0.035)
	var span := float(n - 1) * spacing
	var right := origin.x + span
	var bottom := origin.y + span
	for i in range(n):
		var offset := float(i) * spacing
		draw_line(Vector2(origin.x, origin.y + offset), Vector2(right, origin.y + offset), QGPalette.BOARD_LINE, line_width, true)
		draw_line(Vector2(origin.x + offset, origin.y), Vector2(origin.x + offset, bottom), QGPalette.BOARD_LINE, line_width, true)
	# The border lines read slightly heavier on a real board.
	draw_line(origin, Vector2(right, origin.y), QGPalette.BOARD_LINE, line_width * 1.6, true)
	draw_line(Vector2(origin.x, bottom), Vector2(right, bottom), QGPalette.BOARD_LINE, line_width * 1.6, true)
	draw_line(origin, Vector2(origin.x, bottom), QGPalette.BOARD_LINE, line_width * 1.6, true)
	draw_line(Vector2(right, origin.y), Vector2(right, bottom), QGPalette.BOARD_LINE, line_width * 1.6, true)


func _star_points() -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	var seen := {}
	var low := 3 if board_size >= 13 else 2
	var high := board_size - 1 - low
	@warning_ignore("integer_division")
	var mid: int = board_size / 2
	var cols := [low, high]
	if board_size >= 19:
		cols = [low, mid, high]
	for row in [low, high]:
		for col in cols:
			var point := Vector2i(col, row)
			if not seen.has(point):
				seen[point] = true
				points.append(point)
	if board_size % 2 == 1:
		var centre := Vector2i(mid, mid)
		if not seen.has(centre):
			seen[centre] = true
			points.append(centre)
	if board_size >= 19:
		for point in [Vector2i(mid, low), Vector2i(mid, high), Vector2i(low, mid), Vector2i(high, mid)]:
			if not seen.has(point):
				seen[point] = true
				points.append(point)
	return points


func _draw_star_points(origin: Vector2, spacing: float, n: int) -> void:
	var star_radius := maxf(1.8, spacing * 0.10)
	for point in _star_points():
		var centre := origin + Vector2(float(point.x) * spacing, float(point.y) * spacing)
		draw_circle(centre, star_radius, QGPalette.BOARD_LINE)


func _draw_coordinates(geo: Dictionary, n: int) -> void:
	var spacing: float = geo["spacing"]
	if not _show_coords or not _coords_enabled or spacing < 14.0:
		return
	var font := UIKit.font()
	var font_size := clampi(int(roundf(spacing * 0.34)), 9, 15)
	var colour := Color(QGPalette.BOARD_WOOD_DARK.darkened(0.45), 0.95)
	var origin: Vector2 = geo["origin"]
	var edge := spacing * 0.75
	for col in range(n):
		if col >= COORD_LETTERS.length():
			break
		var x_centre := origin.x + float(col) * spacing
		var bottom_y := origin.y + float(n - 1) * spacing + edge * 0.42
		_draw_centered_text(font, COORD_LETTERS[col], Vector2(x_centre, bottom_y), font_size, colour)
	for row in range(n):
		var y_centre := origin.y + float(row) * spacing
		var left_x := origin.x - edge * 0.42
		_draw_centered_text(font, str(n - row), Vector2(left_x, y_centre), font_size, colour)


func _draw_centered_text(font: Font, text: String, centre: Vector2, font_size: int, colour: Color) -> void:
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var ascent := font.get_ascent(font_size)
	var descent := font.get_descent(font_size)
	var baseline := centre + Vector2(-text_size.x * 0.5, (ascent - descent) * 0.5)
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, colour)


func _draw_stones(origin: Vector2, spacing: float, radius: float, n: int) -> void:
	for index in range(n * n):
		var colour := int(board_position.cells[index])
		if colour == QGTypes.EMPTY:
			continue
		var centre := _centre_of(index, origin, spacing)
		# A phantom only looks different when the game is over (or in the tutorial):
		# during play both players must see an ordinary stone.
		var ghost: bool = reveal_phantoms and board_position.is_phantom(index)
		_draw_stone(centre, radius, colour, ghost)
		if dead_points.has(index):
			_draw_dead_mark(centre, radius)


## Scoring phase: a dead stone is dimmed and crossed out so both players can see
## what has been agreed before they confirm the result.
func _draw_dead_mark(centre: Vector2, radius: float) -> void:
	draw_circle(centre, radius * 1.02, Color(QGPalette.BG_DEEP, 0.35))
	var arm := radius * 0.56
	var width := maxf(1.4, radius * 0.16)
	var colour := Color(QGPalette.DANGER, 0.92)
	draw_line(centre + Vector2(-arm, -arm), centre + Vector2(arm, arm), colour, width, true)
	draw_line(centre + Vector2(-arm, arm), centre + Vector2(arm, -arm), colour, width, true)


func _draw_stone(centre: Vector2, radius: float, colour: int, phantom: bool) -> void:
	if radius < 1.0:
		return
	var shadow_alpha := 0.18 if phantom else 0.30
	draw_circle(centre + Vector2(0.0, radius * 0.10), radius * 0.99, Color(0.0, 0.0, 0.0, shadow_alpha))

	var base := QGPalette.stone_color(colour)
	var fill := base
	if phantom:
		fill = base.lerp(QGPalette.PHANTOM_TINT, 0.62)
		fill.a = 0.66
	draw_circle(centre, radius, fill)

	if phantom:
		# A phantom is a stone that this branch may prove false: violet, ghosted,
		# and ringed so it never reads as a normal stone.
		draw_circle(centre, radius * 0.72, Color(QGPalette.PHANTOM_TINT, 0.20))
		_draw_dashed_ring(centre, radius * 1.14, QGPalette.VIOLET, maxf(1.2, radius * 0.10))
		draw_arc(centre, radius * 0.96, 0.0, TAU, 40, Color(QGPalette.VIOLET, 0.85), maxf(1.0, radius * 0.07), true)
		return

	var edge_colour := QGPalette.STONE_BLACK_EDGE if colour == QGTypes.BLACK else QGPalette.STONE_WHITE_EDGE
	draw_arc(centre, radius * 0.97, 0.0, TAU, 40, edge_colour, maxf(1.0, radius * 0.075), true)
	if colour == QGTypes.BLACK:
		draw_circle(centre + Vector2(-radius * 0.30, -radius * 0.34), radius * 0.33, Color(1.0, 1.0, 1.0, 0.10))
		draw_circle(centre + Vector2(radius * 0.22, radius * 0.28), radius * 0.42, Color(0.0, 0.0, 0.0, 0.18))
	else:
		draw_circle(centre + Vector2(-radius * 0.28, -radius * 0.32), radius * 0.34, Color(1.0, 1.0, 1.0, 0.85))
		draw_circle(centre + Vector2(radius * 0.10, radius * 0.22), radius * 0.52, Color(0.80, 0.83, 0.88, 0.16))


func _draw_dashed_ring(centre: Vector2, ring_radius: float, colour: Color, width: float) -> void:
	var segments := 20
	var step := TAU / float(segments)
	for i in range(segments):
		if i % 2 == 1:
			continue
		draw_arc(centre, ring_radius, float(i) * step, float(i + 1) * step, 6, colour, width, true)


func _draw_last_move(origin: Vector2, spacing: float, radius: float) -> void:
	if last_move < 0 or last_move >= board_size * board_size:
		return
	if int(board_position.cells[last_move]) == QGTypes.EMPTY:
		return
	var centre := _centre_of(last_move, origin, spacing)
	var marker_radius := maxf(2.0, radius * 0.20)
	draw_circle(centre, marker_radius * 1.9, Color(QGPalette.LAST_MOVE, 0.22))
	draw_circle(centre, marker_radius, QGPalette.LAST_MOVE)


func _draw_ko_marker(origin: Vector2, spacing: float) -> void:
	if ko_point < 0 or ko_point >= board_size * board_size:
		return
	if int(board_position.cells[ko_point]) != QGTypes.EMPTY:
		return
	var centre := _centre_of(ko_point, origin, spacing)
	var half := spacing * 0.16
	var colour := Color(QGPalette.BOARD_LINE.darkened(0.25), 0.9)
	draw_rect(Rect2(centre - Vector2(half, half), Vector2(half * 2.0, half * 2.0)), colour, false, maxf(1.0, spacing * 0.05))


func _draw_hover(origin: Vector2, spacing: float, radius: float) -> void:
	if not interactive or _hover_index < 0 or board_position == null:
		return
	if not board_position.is_empty(_hover_index) or _hover_index == pending_a:
		return
	var centre := _centre_of(_hover_index, origin, spacing)
	if quantum_mode or pending_a >= 0:
		draw_circle(centre, radius, Color(QGPalette.VIOLET, 0.20))
		_draw_dashed_ring(centre, radius * 1.10, Color(QGPalette.VIOLET, 0.75), maxf(1.0, radius * 0.08))
		return
	var colour := QGPalette.stone_color(acting_color)
	var fill := colour
	fill.a = 0.34
	draw_circle(centre, radius, fill)
	var edge := QGPalette.STONE_BLACK_EDGE if acting_color == QGTypes.BLACK else QGPalette.STONE_WHITE_EDGE
	draw_arc(centre, radius * 0.97, 0.0, TAU, 36, Color(edge, 0.9), maxf(1.0, radius * 0.07), true)


func _draw_pending_a(origin: Vector2, spacing: float, radius: float) -> void:
	if pending_a < 0 or pending_a >= board_size * board_size:
		return
	var centre := _centre_of(pending_a, origin, spacing)
	draw_circle(centre, radius * 0.92, Color(QGPalette.VIOLET, 0.22))
	draw_arc(centre, radius * 0.98, 0.0, TAU, 44, QGPalette.VIOLET, maxf(1.5, radius * 0.09), true)
	var font := UIKit.bold_font()
	var font_size := clampi(int(roundf(radius * 1.15)), 10, 26)
	_draw_centered_text(font, "A", centre, font_size, QGPalette.VIOLET)
