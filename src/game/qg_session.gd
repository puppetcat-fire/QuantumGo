## Transport-agnostic match session.
##
## Three modes share one API so the UI never branches on "online or not":
##   LOCAL  — two players on one machine, both colours controllable
##   HOST   — this peer is authoritative and serves the match
##   CLIENT — this peer mirrors the host's authoritative state
##
## The host is the only peer that mutates `game` from commands. A client sends a
## command and waits for the authoritative state packet.
class_name QGSession
extends Node

signal state_changed
signal match_started(meta: Dictionary)
signal match_ended(result: Dictionary)
signal event_fired(event: Dictionary)
signal status_changed(text: String)
signal move_rejected(reason: String)
signal lobby_changed(info: Dictionary)
signal opponent_left

enum Mode { LOCAL, HOST, CLIENT }

const DEFAULT_PORT := 27777
const HOST_PEER_ID := 1

var mode: int = Mode.LOCAL
var game: QGGame = null
var my_color: int = QGTypes.EMPTY
var player_name: String = "玩家"
var started: bool = false
var match_meta: Dictionary = {}
var local_port: int = DEFAULT_PORT

var _transport: QGTransport = null
var _peer_names: Dictionary = {}
var _peer_colours: Dictionary = {}
var _awaiting_reply: int = 0

## Snapshots of the authoritative game, oldest first, one per state change. The
## replay screen walks this list; the phantom stones are revealed there because
## the match is over by the time anyone looks.
const HISTORY_LIMIT := 600
var history: Array[Dictionary] = []


func _ready() -> void:
	set_process(false)


# --------------------------------------------------------------------------
# Lifecycle
# --------------------------------------------------------------------------

## Start a hot-seat match. Both colours are controllable.
func start_local(board_size: int = 9) -> Dictionary:
	leave()
	mode = Mode.LOCAL
	my_color = QGTypes.EMPTY
	game = QGGame.create(board_size, randi())
	started = true
	match_meta = {
		"board_size": board_size,
		"names": {QGTypes.BLACK: "黑方", QGTypes.WHITE: "白方"},
		"mode": "local",
	}
	_reset_history()
	match_started.emit(match_meta)
	state_changed.emit()
	return {"ok": true}


func host_match(board_size: int, name: String, port: int = DEFAULT_PORT) -> Dictionary:
	leave()
	player_name = name.strip_edges() if not name.strip_edges().is_empty() else "房主"
	game = QGGame.create(board_size, randi())
	mode = Mode.HOST
	my_color = QGTypes.BLACK
	started = false
	local_port = port
	match_meta = {"board_size": board_size, "mode": "host"}

	_ensure_transport()
	var error := _transport.start_host(port, 1)
	if error != OK:
		mode = Mode.LOCAL
		game = null
		return {"ok": false, "reason": tr("无法在端口 %d 上开启房间") % port}

	_peer_names = {HOST_PEER_ID: player_name}
	_peer_colours = {HOST_PEER_ID: QGTypes.BLACK}
	lobby_changed.emit(lobby_info())
	status_changed.emit(tr("房间已创建，等待对手加入（端口 %d）") % port)
	return {"ok": true, "port": port}


func join_match(address: String, port: int, name: String) -> Dictionary:
	leave()
	player_name = name.strip_edges() if not name.strip_edges().is_empty() else "玩家"
	mode = Mode.CLIENT
	my_color = QGTypes.EMPTY
	game = null
	started = false
	local_port = port
	match_meta = {"mode": "client"}

	_ensure_transport()
	var error := _transport.start_client(address, port)
	if error != OK:
		mode = Mode.LOCAL
		return {"ok": false, "reason": tr("无法连接到 %s:%d") % [address, port]}

	status_changed.emit(tr("正在连接 %s:%d …") % [address, port])
	return {"ok": true}


func leave() -> void:
	if _transport != null:
		_transport.stop()
	started = false
	game = null
	mode = Mode.LOCAL
	my_color = QGTypes.EMPTY
	_peer_names.clear()
	_peer_colours.clear()
	_awaiting_reply = 0
	match_meta = {}


# --------------------------------------------------------------------------
# Queries used by the UI
# --------------------------------------------------------------------------

func can_play(universe_id: int) -> bool:
	if game == null or game.is_over():
		return false
	var turn := game.turn_of(universe_id)
	if turn == QGTypes.EMPTY:
		return false
	if mode == Mode.LOCAL:
		return true
	return turn == my_color


func acting_color(universe_id: int) -> int:
	if game == null:
		return QGTypes.EMPTY
	return game.turn_of(universe_id)


func is_online() -> bool:
	return mode == Mode.HOST or mode == Mode.CLIENT


func lobby_info() -> Dictionary:
	return {
		"mode": mode,
		"host": _peer_names.get(HOST_PEER_ID, "房主"),
		"guest": _peer_names.get(2, ""),
		"ready": _peer_colours.size() >= 2,
		"port": local_port,
	}


func colour_name_of_peer(peer_id: int) -> String:
	return QGTypes.color_name(int(_peer_colours.get(peer_id, QGTypes.EMPTY)))


# --------------------------------------------------------------------------
# Commands
# --------------------------------------------------------------------------

func submit_move(universe_id: int, point: int) -> Dictionary:
	return _submit({"type": "move", "u": universe_id, "p": point})


func submit_quantum(universe_id: int, point_a: int, point_b: int) -> Dictionary:
	return _submit({"type": "quantum", "u": universe_id, "a": point_a, "b": point_b})


func submit_pass(universe_id: int) -> Dictionary:
	return _submit({"type": "pass", "u": universe_id})


## Scoring phase: toggle a dead-stone mark. Marks are shared, so either player
## may edit them.
func submit_mark(universe_id: int, point: int) -> Dictionary:
	return _submit({"type": "mark", "u": universe_id, "p": point})


## Scoring phase: sign off on the result. Hot seat confirms both colours at once;
## online each peer confirms its own colour and the host finalises when both are in.
func submit_confirm_score() -> Dictionary:
	return _submit({"type": "confirm_score"})


## Resign. `colour` only matters in hot-seat mode, where the screen has to say
## which of the two players is giving up; online the seat decides.
func submit_resign(colour: int = QGTypes.EMPTY) -> Dictionary:
	return _submit({"type": "resign", "c": colour})


## Starts the next game with the same seats. Hot seat restarts locally, the host
## resets its authoritative game and rebroadcasts, the client asks the host.
func rematch() -> Dictionary:
	match mode:
		Mode.LOCAL:
			return start_local(int(match_meta.get("board_size", 9)))
		Mode.HOST:
			if _transport == null:
				return {"ok": false, "reason": "not_connected"}
			if _peer_colours.size() < 2:
				return {"ok": false, "reason": "opponent_missing"}
			game = QGGame.create(int(match_meta.get("board_size", 9)), randi())
			_start_match()
			return {"ok": true}
		Mode.CLIENT:
			if _transport == null:
				return {"ok": false, "reason": "not_connected"}
			_transport.send(HOST_PEER_ID, {"t": "rematch"})
			status_changed.emit("已请求再来一局")
			return {"ok": true, "pending": true}
	return {"ok": false, "reason": "unknown_mode"}


## Take back the last move. Hot-seat only: in an online match the opponent has
## already seen the position, so undo has to be requested, not executed.
func submit_undo() -> Dictionary:
	if game == null:
		return {"ok": false, "reason": QGTypes.ERR_GAME_OVER}
	if mode != Mode.LOCAL:
		return {"ok": false, "reason": "undo_local_only"}
	if not game.can_undo():
		return {"ok": false, "reason": "nothing_to_undo"}
	if not game.undo():
		return {"ok": false, "reason": "nothing_to_undo"}
	started = true
	state_changed.emit()
	return {"ok": true}


func _submit(command: Dictionary) -> Dictionary:
	if game == null:
		return {"ok": false, "reason": QGTypes.ERR_GAME_OVER}

	if mode == Mode.CLIENT:
		if _transport == null:
			return {"ok": false, "reason": "未连接"}
		_awaiting_reply += 1
		_transport.send(HOST_PEER_ID, {"t": "cmd", "cmd": command})
		return {"ok": true, "pending": true}

	var colour := _command_colour(command)
	var result := _apply_command(command, colour)
	if not result.get("ok", false):
		move_rejected.emit(String(result.get("reason", "")))
		return result

	_record_history()
	_report_achievements()

	if mode == Mode.HOST and _transport != null:
		_broadcast_state({})
	# State first, then the result: a result overlay that appears before the final
	# board would show the previous position behind it.
	state_changed.emit()
	_check_outcome()
	return result


## Platform hooks for the moment-to-moment achievements. Missing Platform autoload
## (tools, tests) simply means nothing happens.
func _report_achievements() -> void:
	if game == null:
		return
	var platform := get_node_or_null("/root/Platform")
	if platform == null:
		return
	for event in game.events:
		match String(event.get("type", "")):
			"split":
				platform.call("unlock_achievement", "FIRST_QUANTUM_SPLIT")
			"collapse":
				platform.call("unlock_achievement", "FIRST_COLLAPSE")


func _command_colour(command: Dictionary) -> int:
	var kind := String(command.get("type", ""))
	if kind == "confirm_score":
		# Online: my seat. Hot seat: both colours confirm in one action, which the
		# apply step handles explicitly.
		return my_color
	if kind == "mark":
		return QGTypes.EMPTY
	if kind == "resign":
		if mode == Mode.LOCAL:
			# Hot seat: the screen names the player who gives up. Fall back to the
			# first side that is actually to move when it does not (tools, tests,
			# or a focused universe that just got sealed).
			var requested := int(command.get("c", QGTypes.EMPTY))
			if requested == QGTypes.BLACK or requested == QGTypes.WHITE:
				return requested
			for universe_id in game.live_ids():
				var side := game.turn_of(universe_id)
				if side == QGTypes.BLACK or side == QGTypes.WHITE:
					return side
			return QGTypes.BLACK
		return my_color
	var universe_id := int(command.get("u", -1))
	return game.turn_of(universe_id)


func _apply_command(command: Dictionary, colour: int) -> Dictionary:
	var kind := String(command.get("type", ""))
	var universe_id := int(command.get("u", -1))
	match kind:
		"move":
			return game.apply_move(universe_id, int(command.get("p", -1)), colour)
		"quantum":
			return game.apply_quantum(universe_id, int(command.get("a", -1)), int(command.get("b", -1)), colour)
		"pass":
			return game.apply_pass(universe_id, colour)
		"resign":
			return game.resign(colour)
		"mark":
			return game.toggle_dead(universe_id, int(command.get("p", -1)))
		"confirm_score":
			if mode == Mode.LOCAL:
				# Both players sit at one keyboard, so one click signs off both.
				var first := game.confirm_scoring(QGTypes.BLACK)
				if not first.get("ok", false):
					return first
				return game.confirm_scoring(QGTypes.WHITE)
			return game.confirm_scoring(colour)
		_:
			return {"ok": false, "reason": "unknown_command"}


func _check_outcome() -> void:
	if game == null or not game.is_over():
		return
	if mode == Mode.HOST and _transport != null:
		_transport.broadcast({"t": "over", "result": _result_payload()})
	started = false
	_report_match_result()
	match_ended.emit(_result_payload())


## Achievements and the Steam leaderboard only make sense once per finished
## match, so they are reported here rather than in the per-move path.
func _report_match_result() -> void:
	var platform := get_node_or_null("/root/Platform")
	if platform == null or game == null:
		return

	var score := game.weighted_score()
	var my_points := 0
	var won := false
	if mode == Mode.LOCAL:
		# Hot seat: both players share the PC, so any finished match is "yours".
		won = true
		my_points = maxi(int(score["black"]), int(score["white"]))
	else:
		won = game.winner == my_color
		my_points = int(score["black"]) if my_color == QGTypes.BLACK else int(score["white"])

	if won:
		platform.call("unlock_achievement", "WIN_FIRST_MATCH")
	if my_points > 0:
		platform.call("submit_leaderboard_score", "TOTAL_WEIGHTED_SCORE", my_points)


func _result_payload() -> Dictionary:
	var score := game.weighted_score()
	return {
		"winner": game.winner,
		"black": score["black"],
		"white": score["white"],
		"universes": score["universes"],
		"moves": game.move_count,
		"board_size": game.board_size,
		"meta": match_meta,
	}


# --------------------------------------------------------------------------
# Transport plumbing
# --------------------------------------------------------------------------

func _ensure_transport() -> void:
	if _transport != null and is_instance_valid(_transport):
		return
	var enet_script := load("res://src/net/qg_enet_transport.gd")
	if enet_script == null:
		push_error("ENet transport script missing")
		return
	_transport = enet_script.new()
	_transport.name = "Transport"
	add_child(_transport)
	_transport.peer_joined.connect(_on_peer_joined)
	_transport.peer_left.connect(_on_peer_left)
	_transport.packet_received.connect(_on_packet)
	_transport.transport_error.connect(_on_transport_error)


func _on_transport_error(message: String) -> void:
	status_changed.emit(message)


func _on_peer_joined(peer_id: int) -> void:
	if mode == Mode.CLIENT:
		# The transport reports the host peer once the connection is actually
		# established; that is the moment the join request can be sent.
		if peer_id == HOST_PEER_ID:
			_transport.send(HOST_PEER_ID, {"t": "hello", "name": player_name})
			status_changed.emit("已连接，正在进入房间…")
		return
	if mode != Mode.HOST:
		return
	# First guest is white. The lobby stays open until two players exist.
	if not _peer_colours.has(peer_id):
		_peer_colours[peer_id] = QGTypes.WHITE
	lobby_changed.emit(lobby_info())


func _on_peer_left(peer_id: int) -> void:
	_peer_colours.erase(peer_id)
	_peer_names.erase(peer_id)
	if started:
		opponent_left.emit()
		status_changed.emit("对手已离开")
	else:
		lobby_changed.emit(lobby_info())
		status_changed.emit("对手已离开，等待新的对手")


func _on_packet(from_peer: int, packet: Dictionary) -> void:
	match String(packet.get("t", "")):
		"hello":
			_on_hello(from_peer, packet)
		"welcome":
			_on_welcome(packet)
		"lobby":
			lobby_changed.emit(packet.get("info", {}))
		"start":
			_on_start(packet)
		"cmd":
			_on_remote_command(from_peer, packet)
		"state":
			_on_state(packet)
		"over":
			_on_over(packet)
		"reject":
			_awaiting_reply = maxi(0, _awaiting_reply - 1)
			move_rejected.emit(String(packet.get("reason", "")))
		"rematch":
			_on_rematch_request(from_peer)


func _on_hello(peer_id: int, packet: Dictionary) -> void:
	if mode != Mode.HOST:
		return
	var name := String(packet.get("name", "玩家"))
	_peer_names[peer_id] = name
	if not _peer_colours.has(peer_id):
		_peer_colours[peer_id] = QGTypes.WHITE
	_transport.send(peer_id, {
		"t": "welcome",
		"colour": _peer_colours[peer_id],
		"names": _peer_names,
	})
	lobby_changed.emit(lobby_info())
	if _peer_colours.size() >= 2:
		_start_match()


func _on_welcome(packet: Dictionary) -> void:
	my_color = int(packet.get("colour", QGTypes.WHITE))
	var names: Dictionary = packet.get("names", {})
	for key in names.keys():
		_peer_names[int(key)] = String(names[key])
	lobby_changed.emit(lobby_info())
	status_changed.emit("已进入房间，等待房主开始")


func _on_start(packet: Dictionary) -> void:
	var state: PackedByteArray = packet.get("state", PackedByteArray())
	game = QGWire.decode_game(state)
	match_meta = packet.get("meta", {})
	started = true
	match_started.emit(match_meta)
	state_changed.emit()


func _start_match() -> void:
	match_meta = {
		"board_size": game.board_size,
		"mode": "online",
		"names": _peer_names.duplicate(),
		"colours": _peer_colours.duplicate(),
	}
	var payload := {
		"t": "start",
		"meta": match_meta,
		"state": QGWire.encode_state(game),
	}
	_transport.broadcast(payload)
	started = true
	_reset_history()
	match_started.emit(match_meta)
	state_changed.emit()


func _on_remote_command(from_peer: int, packet: Dictionary) -> void:
	if mode != Mode.HOST:
		return
	var colour := int(_peer_colours.get(from_peer, QGTypes.EMPTY))
	if colour == QGTypes.EMPTY:
		_transport.send(from_peer, {"t": "reject", "reason": "not_seated"})
		return
	var command: Dictionary = packet.get("cmd", {})
	var result := _apply_command(command, colour)
	if not result.get("ok", false):
		_transport.send(from_peer, {"t": "reject", "reason": String(result.get("reason", ""))})
		return
	_broadcast_state(_event_payload())
	_record_history()
	# 远端落子改的是本机（权威）game，必须通知本机 UI 重绘：只广播给客方会让房主
	# 停在旧盘面，两边看到的棋盘不一致，各自都以为轮到对方走。
	state_changed.emit()
	_check_outcome()


func _on_state(packet: Dictionary) -> void:
	if mode != Mode.CLIENT:
		return
	var state: PackedByteArray = packet.get("state", PackedByteArray())
	game = QGWire.decode_game(state)
	_awaiting_reply = maxi(0, _awaiting_reply - 1)
	_record_history()
	var event: Dictionary = packet.get("event", {})
	if not event.is_empty():
		event_fired.emit(event)
	state_changed.emit()


# --------------------------------------------------------------------------
# Replay history
# --------------------------------------------------------------------------

func _reset_history() -> void:
	history.clear()
	_record_history()


func _record_history() -> void:
	if game == null:
		return
	history.append(game.to_dict())
	while history.size() > HISTORY_LIMIT:
		history.pop_front()


## Snapshot `index` of the current match, ready for the replay screen.
func history_snapshot(index: int) -> Dictionary:
	if index < 0 or index >= history.size():
		return {}
	return history[index]


func history_size() -> int:
	return history.size()


func _on_over(packet: Dictionary) -> void:
	started = false
	_report_match_result()
	match_ended.emit(packet.get("result", {}))


func _on_rematch_request(from_peer: int) -> void:
	if mode != Mode.HOST:
		return
	if not _peer_colours.has(from_peer):
		return
	if _peer_colours.size() < 2:
		return
	game = QGGame.create(int(match_meta.get("board_size", 9)), randi())
	_start_match()


func _broadcast_state(event: Dictionary) -> void:
	if _transport == null:
		return
	var payload := {"t": "state", "state": QGWire.encode_state(game), "event": event}
	_transport.broadcast(payload)
	if not event.is_empty():
		event_fired.emit(event)


func _event_payload() -> Dictionary:
	if game == null or game.events.is_empty():
		return {}
	return {"events": game.events.duplicate(true)}
