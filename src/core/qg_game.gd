## Authoritative Quantum Go rules engine.
##
## Model
## -----
## A game is a tree of *universes*. Every universe is an ordinary Go position
## with its own turn order, its own ko point, and an integer `weight` (percent).
## The weights of all live universes always add up to 100.
##
## A quantum move names two empty points A and B. It does not happen in one
## place: reality branches.
##   * the universe you were playing in keeps half the weight and receives the
##     stone at A (a real stone),
##   * a new child universe receives the other half of the weight and the stone
##     at B, and that stone is marked *phantom*: in this branch it is the stone
##     that quantum mechanics has not decided about yet.
##
## Capturing a phantom stone is an observation. The branch that carried the
## phantom is proven false, it collapses together with all of its descendants,
## and its weight flows back to its parent. This is what keeps the tree from
## exploding, and it is the only way a branch can die.
##
## Both players see every live universe; the hidden information is which weight
## a position will eventually be worth, not what the board looks like. That
## keeps the game honest online and makes replays exact: the engine is fully
## deterministic and uses no randomness at all.
class_name QGGame
extends RefCounted

const EMPTY := QGTypes.EMPTY
const BLACK := QGTypes.BLACK
const WHITE := QGTypes.WHITE

const PHASE_PLAYING := 0
const PHASE_SCORING := 1
const PHASE_OVER := 2

const MIN_BOARD := 5
const MAX_BOARD := 19
const UNDO_DEPTH := 64

## Playability limits. Without them a hot-seat match reaches dozens of universes
## of 1–2% weight each: nobody can read that board, and a sync packet grows to
## tens of kilobytes. Six live universes and an 8% floor keep the tree small
## enough to show on one screen while still allowing four levels of splitting.
const MAX_LIVE_UNIVERSES := 6
const MIN_SPLIT_WEIGHT := 8


## One branch of reality.
##
## A quantum move does not extend a universe, it replaces it: the universe that
## was being played in is retired and two sibling universes are born, one per
## candidate point. Exactly one sibling carries the *phantom* stone — the stone
## that may turn out never to have existed — and which sibling that is gets
## decided by a seeded coin flip. Players never see the coin: that uncertainty is
## the game.
class Universe:
	extends RefCounted

	var id: int = -1
	var position: QGPosition = null
	var weight: int = 100
	var turn: int = BLACK
	## The universe this one was split from (retired once the split happens).
	var parent: int = -1
	## The other universe born in the same split, -1 for the root.
	var partner: int = -1
	## Board index of the stone this universe placed when it was born, -1 for the
	## root. Its sibling placed the other point of the same quantum move.
	var split_point: int = -1
	## Board index of this universe's phantom stone, -1 when its own stone is real.
	## Ancestors' phantom stones stay flagged in `position`, so a deep branch
	## carries one phantom for every split on its path that it was on the false side.
	var phantom_point: int = -1
	var ko_point: int = -1
	var children: Array[int] = []
	var alive: bool = true
	var sealed: bool = false
	var consecutive_passes: int = 0
	var last_move: int = -1

	func is_phantom_holder() -> bool:
		return phantom_point >= 0

	func clone() -> Universe:
		var copy := Universe.new()
		copy.id = id
		copy.position = position.clone()
		copy.weight = weight
		copy.turn = turn
		copy.parent = parent
		copy.partner = partner
		copy.split_point = split_point
		copy.phantom_point = phantom_point
		copy.ko_point = ko_point
		copy.children = children.duplicate()
		copy.alive = alive
		copy.sealed = sealed
		copy.consecutive_passes = consecutive_passes
		copy.last_move = last_move
		return copy

	func to_dict() -> Dictionary:
		return {
			"id": id,
			"position": position.to_dict(),
			"weight": weight,
			"turn": turn,
			"parent": parent,
			"partner": partner,
			"split_point": split_point,
			"phantom_point": phantom_point,
			"ko_point": ko_point,
			"children": children.duplicate(),
			"alive": alive,
			"sealed": sealed,
			"consecutive_passes": consecutive_passes,
			"last_move": last_move,
		}

	static func from_dict(data: Dictionary) -> Universe:
		var universe := Universe.new()
		universe.id = int(data.get("id", -1))
		universe.position = QGPosition.from_dict(data.get("position", {}))
		universe.weight = int(data.get("weight", 0))
		universe.turn = int(data.get("turn", BLACK))
		universe.parent = int(data.get("parent", -1))
		universe.partner = int(data.get("partner", -1))
		universe.split_point = int(data.get("split_point", -1))
		universe.phantom_point = int(data.get("phantom_point", -1))
		universe.ko_point = int(data.get("ko_point", -1))
		universe.children = _to_int_array(data.get("children", []))
		universe.alive = bool(data.get("alive", true))
		universe.sealed = bool(data.get("sealed", false))
		universe.consecutive_passes = int(data.get("consecutive_passes", 0))
		universe.last_move = int(data.get("last_move", -1))
		return universe

	static func _to_int_array(value: Variant) -> Array[int]:
		var out: Array[int] = []
		for item in value:
			out.append(int(item))
		return out


var board_size: int = 9
var universes: Dictionary = {}
var root_id: int = 0
var next_id: int = 1
var phase: int = PHASE_PLAYING
var winner: int = QGTypes.WINNER_NONE
var move_count: int = 0
var events: Array[Dictionary] = []

## Scoring phase: stones both players agree are dead, per universe. Marks are
## shared state — either side may toggle them — and the result only becomes final
## once both colours confirm.
var dead_marks: Dictionary = {}
var score_confirmed: Dictionary = {}

var _undo_stack: Array[Dictionary] = []

## Seed of the coin that decides which sibling carries the phantom. Both peers
## replay the same sequence, so matches stay verifiable and replays exact, while
## the players themselves never learn the outcome until a stone is captured.
var seed_value: int = 0
var _rng := RandomNumberGenerator.new()


static func create(size: int = 9, seed: int = 0) -> QGGame:
	var game := QGGame.new()
	game._setup(size, seed)
	return game


func _setup(size: int, seed: int = 0) -> void:
	board_size = clampi(size, MIN_BOARD, MAX_BOARD)
	seed_value = seed
	_rng.seed = seed
	universes.clear()
	root_id = 0
	next_id = 1
	phase = PHASE_PLAYING
	winner = QGTypes.WINNER_NONE
	move_count = 0
	events.clear()
	dead_marks.clear()
	score_confirmed.clear()
	_undo_stack.clear()

	var root := Universe.new()
	root.id = 0
	root.position = QGPosition.new(board_size)
	root.weight = 100
	root.turn = BLACK
	root.parent = -1
	root.partner = -1
	root.phantom_point = -1
	root.ko_point = -1
	universes[0] = root


func get_universe(id: int) -> Universe:
	return universes.get(id, null)


func is_over() -> bool:
	return phase == PHASE_OVER


func live_ids() -> Array[int]:
	var out: Array[int] = []
	for id in universes.keys():
		var universe: Universe = universes[id]
		if universe.alive:
			out.append(universe.id)
	out.sort()
	return out


func total_weight() -> int:
	var total := 0
	for id in universes.keys():
		var universe: Universe = universes[id]
		if universe.alive:
			total += universe.weight
	return total


func live_count() -> int:
	var count := 0
	for id in universes.keys():
		var universe: Universe = universes[id]
		if universe.alive:
			count += 1
	return count


## Colour that is allowed to move in `universe_id`, or QGTypes.EMPTY if nobody.
func turn_of(universe_id: int) -> int:
	var universe := get_universe(universe_id)
	if universe == null or not universe.alive or universe.sealed or phase != PHASE_PLAYING:
		return EMPTY
	return universe.turn


func can_split(universe_id: int) -> bool:
	var universe := get_universe(universe_id)
	if universe == null or not universe.alive or universe.sealed:
		return false
	if phase != PHASE_PLAYING:
		return false
	if universe.weight < MIN_SPLIT_WEIGHT:
		return false
	return live_count() < MAX_LIVE_UNIVERSES


## Normal move. `colour` must match the universe's turn.
func apply_move(universe_id: int, index: int, colour: int) -> Dictionary:
	var guard := _guard(universe_id, colour)
	if not guard["ok"]:
		return guard
	var universe: Universe = universes[universe_id]

	var result := universe.position.try_move(index, colour, universe.ko_point)
	if not result["ok"]:
		return {"ok": false, "reason": result["reason"]}

	_push_undo()

	universe.position = result["position"]
	universe.ko_point = result["ko"]
	universe.last_move = index
	universe.consecutive_passes = 0
	universe.turn = QGTypes.opponent(colour)

	move_count += 1
	events.clear()
	events.append({"type": "move", "universe": universe_id, "point": index, "captured": Array(result["captured"])})

	var collapsed := _observe_captures(universe_id, index, result)
	_check_end()
	return {"ok": true, "captured": result["captured"], "collapsed": collapsed}


## Quantum move: reality splits in two.
##
## The universe being played in is retired and replaced by two siblings that share
## its weight. Each sibling rolls its own coin for the stone it just placed: it
## may be real, or it may be a phantom that never existed. Both stones can be
## real, one of them can be, or both can be phantoms — the two rolls are
## independent. Nothing about the roll is shown to either player.
func apply_quantum(universe_id: int, point_a: int, point_b: int, colour: int) -> Dictionary:
	var guard := _guard(universe_id, colour)
	if not guard["ok"]:
		return guard
	if point_a == point_b:
		return {"ok": false, "reason": QGTypes.ERR_BAD_POINTS}
	if not can_split(universe_id):
		return {"ok": false, "reason": QGTypes.ERR_QUANTUM_EXHAUSTED}

	var source: Universe = universes[universe_id]
	if not source.position.is_empty(point_a) or not source.position.is_empty(point_b):
		return {"ok": false, "reason": QGTypes.ERR_OCCUPIED}

	# Validate both placements against a scratch copy before mutating anything:
	# a quantum move is atomic, either both branches exist or neither does.
	var move_a := source.position.try_move(point_a, colour, source.ko_point)
	if not move_a["ok"]:
		return {"ok": false, "reason": move_a["reason"]}
	var move_b := source.position.try_move(point_b, colour, source.ko_point)
	if not move_b["ok"]:
		return {"ok": false, "reason": move_b["reason"]}

	_push_undo()

	var id_a := next_id
	next_id += 1
	var id_b := next_id
	next_id += 1
	@warning_ignore("integer_division")
	var weight_a: int = (source.weight + 1) / 2
	var weight_b: int = source.weight - weight_a

	var child_a := Universe.new()
	child_a.id = id_a
	child_a.parent = universe_id
	child_a.partner = id_b
	child_a.position = move_a["position"]
	child_a.weight = weight_a
	child_a.turn = QGTypes.opponent(colour)
	child_a.ko_point = move_a["ko"]
	child_a.last_move = point_a

	var child_b := Universe.new()
	child_b.id = id_b
	child_b.parent = universe_id
	child_b.partner = id_a
	child_b.position = move_b["position"]
	child_b.weight = weight_b
	child_b.turn = QGTypes.opponent(colour)
	child_b.ko_point = move_b["ko"]
	child_b.last_move = point_b

	child_a.split_point = point_a
	child_b.split_point = point_b

	# One coin per split: exactly one sibling is the phantom, the other is real.
	# Which sibling is the liar is what the players cannot see.
	if (_rng.randi() & 1) == 0:
		child_a.phantom_point = point_a
		child_a.position.phantom[point_a] = 1
	else:
		child_b.phantom_point = point_b
		child_b.position.phantom[point_b] = 1

	# The branch we were playing in is spent: its weight now lives in the children.
	source.weight = 0
	source.alive = false
	source.sealed = false
	source.children.append(id_a)
	source.children.append(id_b)
	universes[id_a] = child_a
	universes[id_b] = child_b

	move_count += 1
	events.clear()
	events.append({
		"type": "split",
		"universe": universe_id,
		"children": [id_a, id_b],
		"point_a": point_a,
		"point_b": point_b,
	})

	var collapsed: Array[int] = []
	collapsed.append_array(_observe_captures(id_a, point_a, move_a))
	collapsed.append_array(_observe_captures(id_b, point_b, move_b))

	_check_end()
	return {"ok": true, "child": id_b, "children": [id_a, id_b], "collapsed": collapsed}


## Passing in a universe. Two passes in a row seal it; once every live universe
## is sealed the game is scored.
func apply_pass(universe_id: int, colour: int) -> Dictionary:
	var guard := _guard(universe_id, colour)
	if not guard["ok"]:
		return guard
	var universe: Universe = universes[universe_id]

	_push_undo()
	universe.consecutive_passes += 1
	universe.turn = QGTypes.opponent(colour)
	universe.ko_point = -1
	universe.last_move = -1
	move_count += 1

	events.clear()
	events.append({"type": "pass", "universe": universe_id})
	if universe.consecutive_passes >= 2:
		universe.sealed = true
		events.append({"type": "sealed", "universe": universe_id})

	_check_end()
	return {"ok": true, "sealed": universe.sealed}


func resign(colour: int) -> Dictionary:
	if phase == PHASE_OVER:
		return {"ok": false, "reason": QGTypes.ERR_GAME_OVER}
	if colour != BLACK and colour != WHITE:
		return {"ok": false, "reason": QGTypes.ERR_BAD_POINTS}
	_push_undo()
	phase = PHASE_OVER
	winner = QGTypes.opponent(colour)
	events.clear()
	events.append({"type": "resign", "colour": colour})
	return {"ok": true, "winner": winner}


## Weighted result over every live universe.
## The value of a universe is its area score multiplied by its weight, so the
## totals are in "percent points" and sum to at most 100 * board area.
## During the scoring phase, stones marked dead are counted as removed.
func weighted_score() -> Dictionary:
	var black_total := 0
	var white_total := 0
	var rows: Array[Dictionary] = []
	for id in live_ids():
		var universe: Universe = universes[id]
		var area := scoring_position(id).area_score()
		var black_value: int = int(area["black"]) * universe.weight
		var white_value: int = int(area["white"]) * universe.weight
		black_total += black_value
		white_total += white_value
		rows.append({
			"id": id,
			"weight": universe.weight,
			"black": area["black"],
			"white": area["white"],
			"black_value": black_value,
			"white_value": white_value,
			"sealed": universe.sealed,
			"dead": marked_dead(id).size(),
		})
	var result := QGTypes.WINNER_NONE
	if black_total > white_total:
		result = QGTypes.WINNER_BLACK
	elif white_total > black_total:
		result = QGTypes.WINNER_WHITE
	return {
		"black": black_total,
		"white": white_total,
		"winner": result,
		"universes": rows,
	}


func undo() -> bool:
	if _undo_stack.is_empty():
		return false
	restore(_undo_stack.pop_back())
	return true


func can_undo() -> bool:
	return not _undo_stack.is_empty()


func _guard(universe_id: int, colour: int) -> Dictionary:
	if phase == PHASE_OVER:
		return {"ok": false, "reason": QGTypes.ERR_GAME_OVER}
	if phase == PHASE_SCORING:
		return {"ok": false, "reason": QGTypes.ERR_SCORING}
	var universe := get_universe(universe_id)
	if universe == null or not universe.alive:
		return {"ok": false, "reason": QGTypes.ERR_BAD_POINTS}
	if universe.sealed:
		return {"ok": false, "reason": QGTypes.ERR_SEALED}
	if universe.turn != colour:
		return {"ok": false, "reason": QGTypes.ERR_NOT_YOUR_TURN}
	return {"ok": true}


## Captures are observations.
##
## A phantom stone is judged only when it takes part in a capture — either it is
## captured, or it belongs to the group that captures. Then its coin is flipped
## for real: an ordinary stone that happened to be uncertain becomes certain, and
## a stone that never existed takes its branch down with it.
func _observe_captures(universe_id: int, move_index: int, move: Dictionary) -> Array[int]:
	var collapsed: Array[int] = []
	var points := PackedInt32Array()
	points.append_array(move["captured_phantom"])
	if not move["captured"].is_empty():
		var position: QGPosition = move["position"]
		for stone in position.group_of(move_index):
			if position.phantom[stone] != 0 and not points.has(stone):
				points.append(stone)
	for point in points:
		var universe := get_universe(universe_id)
		if universe == null or not universe.alive:
			# A previous observation in this same move already took the branch out.
			break
		var owner_id := _find_phantom_owner(universe_id, point)
		if owner_id < 0:
			continue
		if _observe_phantom(owner_id, point, universe_id):
			collapsed.append(owner_id)
	return collapsed


## A phantom under observation is always empty: that is what being the phantom
## means. The branch it belongs to was never real.
func _observe_phantom(owner_id: int, _point: int, _in_universe: int) -> bool:
	_collapse(owner_id)
	return true


## Walks up from `from_id` until it finds the universe that rolled the phantom
## sitting on this point. A phantom only ever appears in the universe that rolled
## it and in that universe's descendants, so the owner is on the ancestor chain.
func _find_phantom_owner(from_id: int, point: int) -> int:
	var current := from_id
	while current >= 0:
		var universe := get_universe(current)
		if universe == null:
			return -1
		if universe.phantom_point == point:
			return current
		current = universe.parent
	return -1


## Kills the branch that carried the phantom. Everything born below it loses its
## possibility, and the weight it held goes to the other half of the same split —
## the sibling that stayed real.
func _collapse(target_id: int) -> void:
	var target := get_universe(target_id)
	if target == null:
		return
	var descendants: Array[int] = []
	_collect_subtree(target_id, descendants)

	var released := 0
	for id in descendants:
		var universe: Universe = universes[id]
		if not universe.alive:
			continue
		released += universe.weight
		universe.alive = false
		universe.sealed = false
	if released <= 0:
		return

	var recipients: Array[int] = []
	var partner := get_universe(target.partner)
	if partner != null:
		_collect_live_subtree(partner.id, recipients)
	if recipients.is_empty():
		recipients = live_ids()
	if not recipients.is_empty():
		_distribute_weight(released, recipients)

	events.append({"type": "collapse", "universe": target_id, "released": released})


## Hands `total` weight to `recipients`, proportional to what they already hold.
func _distribute_weight(total: int, recipients: Array[int]) -> void:
	if recipients.is_empty() or total <= 0:
		return
	var weight_sum := 0
	for id in recipients:
		weight_sum += int(universes[id].weight)
	if weight_sum <= 0:
		@warning_ignore("integer_division")
		var base := total / recipients.size()
		var remainder := total - base * recipients.size()
		for index in recipients.size():
			universes[recipients[index]].weight += base + (1 if index < remainder else 0)
		return
	var given := 0
	for index in recipients.size():
		var id: int = recipients[index]
		var share := 0
		if index == recipients.size() - 1:
			share = total - given
		else:
			share = int(round(float(total) * float(universes[id].weight) / float(weight_sum)))
			share = mini(share, total - given)
		universes[id].weight += share
		given += share


func _collect_subtree(root: int, out: Array[int]) -> void:
	var universe := get_universe(root)
	if universe == null:
		return
	out.append(root)
	for child_id in universe.children:
		_collect_subtree(child_id, out)


## Collects the live universes under `root`. A retired universe is not dead: it
## split, and its children inherited the weight it used to hold, so the walk has
## to pass through retired nodes to reach them.
func _collect_live_subtree(root: int, out: Array[int]) -> void:
	var universe := get_universe(root)
	if universe == null:
		return
	if universe.alive:
		out.append(universe.id)
		return
	for child_id in universe.children:
		_collect_live_subtree(child_id, out)


func _check_end() -> void:
	if phase == PHASE_OVER:
		return
	var alive := live_ids()
	if alive.is_empty():
		phase = PHASE_OVER
		winner = QGTypes.WINNER_NONE
		return
	for id in alive:
		var universe: Universe = universes[id]
		if not universe.sealed:
			return
	begin_scoring()


# --------------------------------------------------------------------------
# Scoring phase
# --------------------------------------------------------------------------

## Every universe is sealed: move to the scoring phase, where the players can
## mark dead stones before both confirm the result.
func begin_scoring() -> Dictionary:
	if phase != PHASE_PLAYING:
		return {"ok": false, "reason": QGTypes.ERR_GAME_OVER}
	for id in live_ids():
		var universe: Universe = universes[id]
		if not universe.sealed:
			return {"ok": false, "reason": "not_all_sealed"}
	phase = PHASE_SCORING
	dead_marks.clear()
	score_confirmed.clear()
	events.clear()
	events.append({"type": "scoring_started"})
	return {"ok": true}


func is_scoring() -> bool:
	return phase == PHASE_SCORING


## Stones currently marked dead in one universe, as a plain index array.
func marked_dead(universe_id: int) -> Array[int]:
	var out: Array[int] = []
	if not dead_marks.has(universe_id):
		return out
	for index in dead_marks[universe_id]:
		out.append(int(index))
	out.sort()
	return out


func is_marked_dead(universe_id: int, index: int) -> bool:
	if not dead_marks.has(universe_id):
		return false
	return dead_marks[universe_id].has(index)


## Toggles a dead-stone mark. Marks are shared: either player may change them,
## and every change clears the confirmations so nobody signs off on a stale board.
func toggle_dead(universe_id: int, index: int) -> Dictionary:
	if phase != PHASE_SCORING:
		return {"ok": false, "reason": "not_scoring"}
	var universe := get_universe(universe_id)
	if universe == null or not universe.alive:
		return {"ok": false, "reason": QGTypes.ERR_BAD_POINTS}
	if index < 0 or index >= universe.position.cells.size():
		return {"ok": false, "reason": QGTypes.ERR_OUT_OF_RANGE}
	if universe.position.cells[index] == EMPTY:
		return {"ok": false, "reason": "not_a_stone"}

	var marked: Array = dead_marks.get(universe_id, []).duplicate()
	if marked.has(index):
		marked.erase(index)
	else:
		marked.append(index)
	if marked.is_empty():
		dead_marks.erase(universe_id)
	else:
		dead_marks[universe_id] = marked

	score_confirmed.clear()
	events.clear()
	events.append({
		"type": "dead_marked",
		"universe": universe_id,
		"point": index,
		"dead": is_marked_dead(universe_id, index),
	})
	return {"ok": true, "dead": is_marked_dead(universe_id, index), "count": marked.size()}


func marked_count() -> int:
	var total := 0
	for universe_id in dead_marks.keys():
		total += dead_marks[universe_id].size()
	return total


func is_confirmed(colour: int) -> bool:
	return bool(score_confirmed.get(colour, false))


func confirm_scoring(colour: int) -> Dictionary:
	if phase != PHASE_SCORING:
		return {"ok": false, "reason": "not_scoring"}
	if colour != BLACK and colour != WHITE:
		return {"ok": false, "reason": QGTypes.ERR_BAD_POINTS}
	score_confirmed[colour] = true
	events.clear()
	events.append({"type": "score_confirmed", "colour": colour})
	if is_confirmed(BLACK) and is_confirmed(WHITE):
		_finalize_scoring()
		return {"ok": true, "final": true, "winner": winner}
	return {"ok": true, "final": false}


## The board as it should be scored: marked dead stones removed.
func scoring_position(universe_id: int) -> QGPosition:
	var universe := get_universe(universe_id)
	if universe == null:
		return QGPosition.new(board_size)
	var position := universe.position.clone()
	for index in marked_dead(universe_id):
		if index >= 0 and index < position.cells.size():
			position.cells[index] = EMPTY
			position.phantom[index] = 0
	return position


func _finalize_scoring() -> void:
	for universe_id in dead_marks.keys():
		var universe := get_universe(int(universe_id))
		if universe == null or not universe.alive:
			continue
		for index in dead_marks[universe_id]:
			if index >= 0 and index < universe.position.cells.size():
				universe.position.cells[index] = EMPTY
				universe.position.phantom[index] = 0
	dead_marks.clear()
	score_confirmed.clear()
	phase = PHASE_OVER
	winner = int(weighted_score()["winner"])
	events.clear()
	events.append({"type": "game_over", "winner": winner})


func _push_undo() -> void:
	_undo_stack.append(snapshot())
	if _undo_stack.size() > UNDO_DEPTH:
		_undo_stack.pop_front()


func snapshot() -> Dictionary:
	return {
		"board_size": board_size,
		"root_id": root_id,
		"next_id": next_id,
		"phase": phase,
		"winner": winner,
		"move_count": move_count,
		"seed": seed_value,
		"universes": _universe_list(),
		"dead_marks": dead_marks.duplicate(true),
		"score_confirmed": score_confirmed.duplicate(true),
	}


func restore(state: Dictionary) -> void:
	board_size = int(state.get("board_size", 9))
	root_id = int(state.get("root_id", 0))
	next_id = int(state.get("next_id", 1))
	phase = int(state.get("phase", PHASE_PLAYING))
	winner = int(state.get("winner", QGTypes.WINNER_NONE))
	move_count = int(state.get("move_count", 0))
	seed_value = int(state.get("seed", 0))
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value
	universes.clear()
	for item in state.get("universes", []):
		var universe := Universe.from_dict(item)
		universes[universe.id] = universe
	dead_marks.clear()
	var stored_marks: Dictionary = state.get("dead_marks", {})
	for key in stored_marks.keys():
		var indexes: Array = []
		for index in stored_marks[key]:
			indexes.append(int(index))
		if not indexes.is_empty():
			dead_marks[int(key)] = indexes
	score_confirmed.clear()
	var stored_confirm: Dictionary = state.get("score_confirmed", {})
	for key in stored_confirm.keys():
		score_confirmed[int(key)] = bool(stored_confirm[key])


func to_dict() -> Dictionary:
	return snapshot()


static func from_dict(state: Dictionary) -> QGGame:
	var game := QGGame.new()
	game.restore(state)
	return game


func _universe_list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ids := universes.keys()
	ids.sort()
	for id in ids:
		out.append(universes[id].to_dict())
	return out
