## Shared constants and small helpers for the Quantum Go rules engine.
##
## The engine is deliberately free of any Godot node/UI dependency so that it can
## run headless, on a dedicated server, and inside unit tests.
class_name QGTypes
extends RefCounted

const EMPTY := 0
const BLACK := 1
const WHITE := 2

## Result of scoring a whole game.
const WINNER_NONE := 0
const WINNER_BLACK := 1
const WINNER_WHITE := 2

## Reasons a move can be rejected. Stable strings: they cross the network.
const ERR_OUT_OF_RANGE := "out_of_range"
const ERR_OCCUPIED := "occupied"
const ERR_KO := "ko"
const ERR_SUICIDE := "suicide"
const ERR_NOT_YOUR_TURN := "not_your_turn"
const ERR_GAME_OVER := "game_over"
const ERR_SCORING := "scoring"
const ERR_SEALED := "sealed"
const ERR_QUANTUM_EXHAUSTED := "quantum_exhausted"
const ERR_BAD_POINTS := "bad_points"


static func opponent(color: int) -> int:
	return WHITE if color == BLACK else BLACK


static func color_name(color: int) -> String:
	match color:
		BLACK:
			return "black"
		WHITE:
			return "white"
		_:
			return "empty"


static func color_from_name(name: String) -> int:
	match name:
		"black":
			return BLACK
		"white":
			return WHITE
		_:
			return EMPTY


static func winner_name(winner: int) -> String:
	match winner:
		WINNER_BLACK:
			return "black"
		WINNER_WHITE:
			return "white"
		_:
			return "none"
