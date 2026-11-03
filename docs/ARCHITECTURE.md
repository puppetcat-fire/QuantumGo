# Quantum Go — architecture and contracts

This document is the contract between the rules engine, the session layer, the
network transport and the UI. If code and this file disagree, the code is wrong.

## Layers

```
src/core/     rules engine, pure data, zero Godot nodes, zero I/O
src/game/     session (local / host / client), settings, leaderboard, persistence
src/net/      ENet transport + wire codec
src/ui/       scenes, board widgets, menus, HUD
```

Rules for every layer:

* `src/core` never references a scene, a node, an autoload, input or the clock.
* `src/game` owns the authoritative game and decides what is legal to submit.
* `src/net` is transport only: it delivers dictionaries between peers and says
  nothing about the game.
* `src/ui` reads state and calls `QGSession.submit_*`. It never mutates
  `QGGame` directly.

## Board coordinates

A point is a single `int` index: `index = row * board_size + column`, row 0 is
the top row, column 0 the left column. All engine APIs take indices.

## Engine API (`QGGame`)

```gdscript
QGGame.create(size: int) -> QGGame
game.apply_move(universe_id: int, index: int, colour: int) -> Dictionary
game.apply_quantum(universe_id: int, point_a: int, point_b: int, colour: int) -> Dictionary
game.apply_pass(universe_id: int, colour: int) -> Dictionary
game.resign(colour: int) -> Dictionary
game.undo() -> bool
game.live_ids() -> Array[int]
game.turn_of(universe_id: int) -> int          # EMPTY when nobody may move there
game.can_split(universe_id: int) -> bool
game.weighted_score() -> Dictionary            # {black, white, winner, universes}
game.to_dict() / QGGame.from_dict(dict)
```

Every mutating call returns `{"ok": bool, "reason": String}` on failure and a
payload on success. `reason` values are `QGTypes.ERR_*` strings and cross the
network unchanged.

Result dictionaries of a successful call:

* `apply_move`: `{ok, captured: PackedInt32Array, collapsed: Array[int]}`
* `apply_quantum`: `{ok, child: int, collapsed: Array[int]}`
* `apply_pass`: `{ok, sealed: bool}`
* `resign`: `{ok, winner: int}`

`game.events` is a transient list describing what just happened
(`move` / `split` / `pass` / `sealed` / `collapse` / `resign` / `game_over`).
The UI uses it for animation; it is never trusted as state.

## Session API (`QGSession`, autoload name `Session`)

```gdscript
enum Mode { LOCAL, HOST, CLIENT }

session.start_local(board_size: int) -> void
session.host_match(board_size: int, player_name: String, port: int) -> Dictionary
session.join_match(address: String, port: int, player_name: String) -> Dictionary
session.leave() -> void

session.submit_move(universe_id: int, point: int) -> Dictionary
session.submit_quantum(universe_id: int, point_a: int, point_b: int) -> Dictionary
session.submit_pass(universe_id: int) -> Dictionary
session.submit_resign() -> Dictionary

session.game: QGGame            # authoritative (host/local) or mirrored (client)
session.mode: int
session.my_color: int           # EMPTY in LOCAL mode: both colours are yours
session.started: bool
session.can_play(universe_id: int) -> bool
session.acting_color(universe_id: int) -> int
```

Signals: `state_changed`, `match_started(meta)`, `match_ended(result)`,
`event_fired(event)`, `status_changed(text)`, `move_rejected(reason)`,
`lobby_changed(info)`.

`state_changed` fires after any state mutation, local or remote. The UI may
redraw the whole board on it; the state is small.

## Wire protocol

Transport is `QGTransport` (see `src/net/qg_transport.gd`): reliable ordered
dictionaries, host is peer id 1. On the client side the transport emits
`peer_joined(1)` exactly once when the connection is established — that is what
triggers the join request below. `QGSession` owns the protocol:

| direction | packet | meaning |
|---|---|---|
| C → H | `{t:"hello", name:String}` | join request |
| H → C | `{t:"welcome", colour:int, names:Dictionary}` | colour assignment |
| H → C | `{t:"lobby", info:Dictionary}` | lobby changed |
| H → all | `{t:"start", meta:Dictionary, state:PackedByteArray}` | match begins |
| C → H | `{t:"cmd", cmd:Dictionary}` | move / quantum / pass / resign |
| H → all | `{t:"state", state:PackedByteArray, event:Dictionary}` | authoritative state |
| H → all | `{t:"over", result:Dictionary}` | match finished |
| C → H | `{t:"rematch"}` | request the next game |
| H → all | `{t:"reject", reason:String}` | command refused |

`state` is produced by `QGWire.encode_state` / `QGWire.decode_state`. The host is
always authoritative: a client never applies a command locally before the host's
state packet arrives.

## Determinism

The engine uses no randomness. Given the same initial state and the same command
sequence every peer computes the same game, so the wire only needs the full state
and tests can replay a match byte for byte.

## Testing

* `tests/run_tests.gd` — rules engine, headless.
* `tests/run_ui_smoke.gd` — loads every scene, checks no script error.
* `tests/run_screenshots.gd` — renders frames to `tmp/screens/` for visual review.
* Network integration tests start one headless host and one headless client.
