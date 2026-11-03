## A single Go position: stones, phantom flags, ko point.
##
## A "phantom" stone is a stone that a quantum split introduced into a branch
## where it is not actually real. It occupies its point and can be captured like
## any other stone; capturing it is what collapses the branch (the observation).
## Positions are treated as immutable values: `try_move` returns a new Position.
class_name QGPosition
extends RefCounted

const EMPTY := QGTypes.EMPTY
const BLACK := QGTypes.BLACK
const WHITE := QGTypes.WHITE


var size: int = 0
var cells: PackedByteArray = PackedByteArray()
var phantom: PackedByteArray = PackedByteArray()


func _init(board_size: int = 0) -> void:
	resize(board_size)


func resize(board_size: int) -> void:
	size = board_size
	var count := size * size
	cells = PackedByteArray()
	cells.resize(count)
	cells.fill(EMPTY)
	phantom = PackedByteArray()
	phantom.resize(count)
	phantom.fill(0)


func clone() -> QGPosition:
	var copy := QGPosition.new(size)
	copy.cells = cells.duplicate()
	copy.phantom = phantom.duplicate()
	return copy


func is_inside(row: int, col: int) -> bool:
	return row >= 0 and row < size and col >= 0 and col < size


func to_index(row: int, col: int) -> int:
	return row * size + col


func row_of(index: int) -> int:
	@warning_ignore("integer_division")
	return index / size


func col_of(index: int) -> int:
	return index % size


func neighbors(index: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var row := row_of(index)
	var col := col_of(index)
	if row > 0:
		out.append(index - size)
	if row < size - 1:
		out.append(index + size)
	if col > 0:
		out.append(index - 1)
	if col < size - 1:
		out.append(index + 1)
	return out


func get_cell(index: int) -> int:
	return cells[index]


func is_empty(index: int) -> bool:
	return cells[index] == EMPTY


func is_phantom(index: int) -> bool:
	return phantom[index] != 0


## All connected stones of the same colour that include `index`.
func group_of(index: int) -> PackedInt32Array:
	var group := PackedInt32Array()
	var colour := cells[index]
	if colour == EMPTY:
		return group
	var seen := PackedByteArray()
	seen.resize(cells.size())
	seen.fill(0)
	var stack := PackedInt32Array([index])
	while not stack.is_empty():
		var current: int = stack[stack.size() - 1]
		stack.remove_at(stack.size() - 1)
		if seen[current] != 0:
			continue
		if cells[current] != colour:
			continue
		seen[current] = 1
		group.append(current)
		for neighbour in neighbors(current):
			if seen[neighbour] == 0 and cells[neighbour] == colour:
				stack.append(neighbour)
	return group


## Empty points adjacent to any stone of `group`.
func liberties_of(group: PackedInt32Array) -> PackedInt32Array:
	var seen := PackedByteArray()
	seen.resize(cells.size())
	seen.fill(0)
	var out := PackedInt32Array()
	for stone in group:
		for neighbour in neighbors(stone):
			if cells[neighbour] == EMPTY and seen[neighbour] == 0:
				seen[neighbour] = 1
				out.append(neighbour)
	return out


## Attempts a normal move, returning a result dictionary.
##
## On success the dictionary contains:
##   position: QGPosition   -- the new position (the receiver is untouched)
##   captured: PackedInt32Array -- indexes of stones removed by this move
##   ko: int                -- ko point for the opponent, -1 when there is none
## On failure: `ok` is false and `reason` holds a QGTypes.ERR_* string.
func try_move(index: int, colour: int, ko_point: int) -> Dictionary:
	if index < 0 or index >= cells.size():
		return _fail(QGTypes.ERR_OUT_OF_RANGE)
	if cells[index] != EMPTY:
		return _fail(QGTypes.ERR_OCCUPIED)
	if index == ko_point:
		return _fail(QGTypes.ERR_KO)

	var next := clone()
	next.cells[index] = colour
	next.phantom[index] = 0

	var them := QGTypes.opponent(colour)
	var captured := PackedInt32Array()
	var captured_phantom := PackedInt32Array()
	for neighbour in next.neighbors(index):
		if next.cells[neighbour] != them:
			continue
		var group := next.group_of(neighbour)
		if next.liberties_of(group).is_empty():
			for stone in group:
				if next.cells[stone] == them:
					if next.phantom[stone] != 0:
						captured_phantom.append(stone)
					next.cells[stone] = EMPTY
					next.phantom[stone] = 0
					captured.append(stone)

	# Suicide is illegal. This also covers the "played into own eye" case that
	# incremental liberty bookkeeping tends to get wrong.
	var own_group := next.group_of(index)
	var own_liberties := next.liberties_of(own_group)
	if own_liberties.is_empty():
		return _fail(QGTypes.ERR_SUICIDE)

	var next_ko := -1
	if captured.size() == 1 and own_group.size() == 1 and own_liberties.size() == 1:
		next_ko = captured[0]

	return {
		"ok": true,
		"position": next,
		"captured": captured,
		"captured_phantom": captured_phantom,
		"ko": next_ko,
	}


func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


## Area score (Chinese rules): stones plus empty regions bordered by one colour.
## Phantom stones count as stones, because until they are observed they do occupy
## the board and fight for liberties.
func area_score() -> Dictionary:
	var black := 0
	var white := 0
	var visited := PackedByteArray()
	visited.resize(cells.size())
	visited.fill(0)

	for index in range(cells.size()):
		var colour := cells[index]
		if colour == BLACK:
			black += 1
			continue
		if colour == WHITE:
			white += 1
			continue
		if visited[index] != 0:
			continue

		var region := PackedInt32Array()
		var borders_black := false
		var borders_white := false
		var stack := PackedInt32Array([index])
		while not stack.is_empty():
			var current: int = stack[stack.size() - 1]
			stack.remove_at(stack.size() - 1)
			if visited[current] != 0:
				continue
			if cells[current] != EMPTY:
				continue
			visited[current] = 1
			region.append(current)
			for neighbour in neighbors(current):
				var neighbour_colour := cells[neighbour]
				if neighbour_colour == BLACK:
					borders_black = true
				elif neighbour_colour == WHITE:
					borders_white = true
				elif visited[neighbour] == 0:
					stack.append(neighbour)

		if borders_black and not borders_white:
			black += region.size()
		elif borders_white and not borders_black:
			white += region.size()
		# A region touching both colours is dame and scores for nobody.

	return {"black": black, "white": white}


func to_dict() -> Dictionary:
	return {
		"size": size,
		"cells": Array(cells),
		"phantom": Array(phantom),
	}


static func from_dict(data: Dictionary) -> QGPosition:
	var position := QGPosition.new(int(data.get("size", 0)))
	var cells_value: Array = data.get("cells", [])
	var phantom_value: Array = data.get("phantom", [])
	for index in range(mini(cells_value.size(), position.cells.size())):
		position.cells[index] = int(cells_value[index])
	for index in range(mini(phantom_value.size(), position.phantom.size())):
		position.phantom[index] = int(phantom_value[index])
	return position
