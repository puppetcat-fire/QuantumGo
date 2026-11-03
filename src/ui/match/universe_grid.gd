## Responsive container for 1..6 universe cards.
##
## Two layouts, chosen by the match screen:
##   grid   — equal square boards; searches the column count that yields the
##            largest square and centres every row (1..N boards).
##   focus  — one large focused board plus a column of small thumbnails for the
##            other universes. Used for 13x13/19x19 with 3+ universes: at those
##            sizes an equal grid would shrink the cells below a clickable size,
##            while the focused board stays big enough to play on.
##
## Cards never overlap: each one is fitted into its own cell.
class_name QGUniverseGrid
extends Container

const GAP := 14.0
const CARD_PAD := 10.0
const HEADER_HEIGHT := 38.0
const MIN_BOARD := 24.0

const THUMB_GAP := 12.0
const THUMB_MAX_BOARD := 300.0
const THUMB_MIN_BOARD := 96.0

var focus_layout := false
var focus_position := 0


func _ready() -> void:
	child_order_changed.connect(queue_sort)


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		layout_cards()


func _get_minimum_size() -> Vector2:
	return Vector2(180.0, 140.0)


## Switches layout mode. `position` is the index of the focused card.
func set_layout_mode(p_focus_layout: bool, p_focus_position: int) -> void:
	if focus_layout == p_focus_layout and focus_position == p_focus_position:
		return
	focus_layout = p_focus_layout
	focus_position = p_focus_position
	queue_sort()


func layout_cards() -> void:
	var cards: Array[Control] = []
	for child in get_children():
		if child is Control and child.visible:
			cards.append(child)
	var count := cards.size()
	if count == 0:
		return
	var area := size
	if area.x < 8.0 or area.y < 8.0:
		return

	if focus_layout and count > 1:
		_layout_focus(cards, area)
		return
	_layout_grid(cards, area)


func _layout_grid(cards: Array[Control], area: Vector2) -> void:
	var count := cards.size()
	var best_cols := 1
	var best_board := -1.0
	for cols in range(1, count + 1):
		var rows := int(ceil(float(count) / float(cols)))
		var board_w := (area.x - GAP * float(cols - 1)) / float(cols) - CARD_PAD * 2.0
		var board_h := (area.y - GAP * float(rows - 1)) / float(rows) - HEADER_HEIGHT - CARD_PAD * 2.0
		var board := minf(board_w, board_h)
		if board > best_board:
			best_board = board
			best_cols = cols
	best_board = maxf(best_board, MIN_BOARD)

	var rows := int(ceil(float(count) / float(best_cols)))
	var card_width := best_board + CARD_PAD * 2.0
	var card_height := best_board + HEADER_HEIGHT + CARD_PAD * 2.0
	var total_height := card_height * float(rows) + GAP * float(rows - 1)
	var y := (area.y - total_height) * 0.5
	for row in range(rows):
		var in_row := mini(best_cols, count - row * best_cols)
		var total_width := card_width * float(in_row) + GAP * float(in_row - 1)
		var x := (area.x - total_width) * 0.5
		for col in range(in_row):
			var card := cards[row * best_cols + col]
			fit_child_in_rect(card, Rect2(Vector2(x, y), Vector2(card_width, card_height)))
			x += card_width + GAP
		y += card_height + GAP


func _layout_focus(cards: Array[Control], area: Vector2) -> void:
	var focused_index := clampi(focus_position, 0, cards.size() - 1)
	var focused: Control = cards[focused_index]
	var others: Array[Control] = []
	for i in range(cards.size()):
		if i != focused_index:
			others.append(cards[i])
	var other_count := others.size()
	if other_count == 0:
		_layout_grid(cards, area)
		return

	# Thumbnail pane on the right: two columns from three universes up, so the
	# pane stays narrow and the focused board keeps as much width as possible.
	var thumb_cols := 1
	if other_count >= 3:
		thumb_cols = 2
	var thumb_rows := int(ceil(float(other_count) / float(thumb_cols)))
	var thumb_board := clampf(
		(area.y - THUMB_GAP * float(thumb_rows - 1)) / float(thumb_rows) - HEADER_HEIGHT - CARD_PAD * 2.0,
		THUMB_MIN_BOARD,
		THUMB_MAX_BOARD
	)
	var thumb_card_width := thumb_board + CARD_PAD * 2.0
	var thumb_card_height := thumb_board + HEADER_HEIGHT + CARD_PAD * 2.0
	var pane_width := thumb_card_width * float(thumb_cols) + THUMB_GAP * float(thumb_cols - 1)

	# Focused board: whatever is left of the pane, but never smaller than a
	# playable board (the thumbnail pane shrinks first because it is clamped).
	var focused_board := minf(
		area.x - pane_width - 18.0 - CARD_PAD * 2.0,
		area.y - HEADER_HEIGHT - CARD_PAD * 2.0
	)
	focused_board = maxf(focused_board, 160.0)
	var focused_card_width := focused_board + CARD_PAD * 2.0
	var focused_card_height := focused_board + HEADER_HEIGHT + CARD_PAD * 2.0

	# The focused board is height-limited, so centre the whole composition
	# (board + thumbnail pane) instead of leaving a dead gap in the middle.
	var group_width := focused_card_width + 18.0 + pane_width
	var group_x := maxf(0.0, (area.x - group_width) * 0.5)
	var pane_x := group_x + focused_card_width + 18.0
	var focused_rect := Rect2(
		Vector2(group_x, (area.y - focused_card_height) * 0.5),
		Vector2(focused_card_width, focused_card_height)
	)
	fit_child_in_rect(focused, focused_rect)

	# Thumbnails: centred vertically, last row centred inside the pane.
	var total_height := thumb_card_height * float(thumb_rows) + THUMB_GAP * float(thumb_rows - 1)
	var y := (area.y - total_height) * 0.5
	for row in range(thumb_rows):
		var in_row := mini(thumb_cols, other_count - row * thumb_cols)
		var row_width := thumb_card_width * float(in_row) + THUMB_GAP * float(in_row - 1)
		var x := pane_x + (pane_width - row_width) * 0.5
		for col in range(in_row):
			var card: Control = others[row * thumb_cols + col]
			fit_child_in_rect(card, Rect2(Vector2(x, y), Vector2(thumb_card_width, thumb_card_height)))
			x += thumb_card_width + THUMB_GAP
		y += thumb_card_height + THUMB_GAP
