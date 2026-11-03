## Compact wire codec for engine state.
##
## Game state is a tree of universes; every universe is a small board. Encoding
## boards as `PackedByteArray` instead of `Array[int]` keeps a sync packet at
## roughly 200 bytes per universe, which matters because the host broadcasts the
## full authoritative state after every move.
class_name QGWire
extends RefCounted

const QGTypesRef := preload("res://src/core/qg_types.gd")


## Serialises a game into a byte array that can cross the network or be written
## to disk.
static func encode_state(game: QGGame) -> PackedByteArray:
	var state := {
		"v": 3,
		"n": game.board_size,
		"root": game.root_id,
		"next": game.next_id,
		"phase": game.phase,
		"winner": game.winner,
		"moves": game.move_count,
		"seed": game.seed_value,
		"universes": _encode_universes(game),
		"dead": game.dead_marks.duplicate(true),
		"confirmed": game.score_confirmed.duplicate(true),
	}
	return var_to_bytes(state)


static func decode_state(bytes: PackedByteArray) -> Dictionary:
	var state: Variant = bytes_to_var(bytes)
	if typeof(state) != TYPE_DICTIONARY:
		return {}
	return state


## Serialises a command dictionary (send/receive side of `{t:"cmd"}`).
static func encode_command(command: Dictionary) -> PackedByteArray:
	return var_to_bytes(command)


static func decode_command(bytes: PackedByteArray) -> Dictionary:
	var command: Variant = bytes_to_var(bytes)
	if typeof(command) != TYPE_DICTIONARY:
		return {}
	return command


static func _encode_universes(game: QGGame) -> Dictionary:
	var out := {}
	for id in game.universes.keys():
		var universe: QGGame.Universe = game.universes[id]
		out[id] = {
			"w": universe.weight,
			"t": universe.turn,
			"p": universe.parent,
			"r": universe.partner,
			"q": universe.split_point,
			"s": universe.phantom_point,
			"k": universe.ko_point,
			"c": universe.children,
			"a": universe.alive,
			"e": universe.sealed,
			"z": universe.consecutive_passes,
			"l": universe.last_move,
			"b": universe.position.cells,
			"f": universe.position.phantom,
		}
	return out


## Rebuilds a `QGGame` from an encoded state. The result is authoritative and
## safe to hand to the UI.
static func decode_game(bytes: PackedByteArray) -> QGGame:
	var state := decode_state(bytes)
	var game := QGGame.new()
	game.board_size = int(state.get("n", 9))
	game.root_id = int(state.get("root", 0))
	game.next_id = int(state.get("next", 1))
	game.phase = int(state.get("phase", QGGame.PHASE_PLAYING))
	game.winner = int(state.get("winner", 0))
	game.move_count = int(state.get("moves", 0))
	game.seed_value = int(state.get("seed", 0))
	game._rng = RandomNumberGenerator.new()
	game._rng.seed = game.seed_value
	game.universes.clear()

	var universes: Dictionary = state.get("universes", {})
	for raw_id in universes.keys():
		var data: Dictionary = universes[raw_id]
		var universe := QGGame.Universe.new()
		universe.id = int(raw_id)
		universe.weight = int(data.get("w", 0))
		universe.turn = int(data.get("t", 0))
		universe.parent = int(data.get("p", -1))
		universe.partner = int(data.get("r", -1))
		universe.split_point = int(data.get("q", -1))
		universe.phantom_point = int(data.get("s", -1))
		universe.ko_point = int(data.get("k", -1))
		universe.children = _int_array(data.get("c", []))
		universe.alive = bool(data.get("a", true))
		universe.sealed = bool(data.get("e", false))
		universe.consecutive_passes = int(data.get("z", 0))
		universe.last_move = int(data.get("l", -1))
		var position := QGPosition.new(game.board_size)
		var cells: PackedByteArray = data.get("b", PackedByteArray())
		var phantom: PackedByteArray = data.get("f", PackedByteArray())
		for index in range(mini(cells.size(), position.cells.size())):
			position.cells[index] = cells[index]
		for index in range(mini(phantom.size(), position.phantom.size())):
			position.phantom[index] = phantom[index]
		universe.position = position
		game.universes[universe.id] = universe

	var dead: Dictionary = state.get("dead", {})
	for raw_id in dead.keys():
		var indexes: Array = []
		for index in dead[raw_id]:
			indexes.append(int(index))
		if not indexes.is_empty():
			game.dead_marks[int(raw_id)] = indexes

	var confirmed: Dictionary = state.get("confirmed", {})
	for raw_colour in confirmed.keys():
		game.score_confirmed[int(raw_colour)] = bool(confirmed[raw_colour])
	return game


static func _int_array(value: Variant) -> Array[int]:
	var out: Array[int] = []
	for item in value:
		out.append(int(item))
	return out
