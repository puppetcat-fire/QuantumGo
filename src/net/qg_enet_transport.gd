## ENet transport for online matches.
##
## Implements `QGTransport` on top of `ENetMultiplayerPeer`. `QGSession` creates
## this node once and keeps it as the `Transport` child of the `Session`
## autoload, so its absolute path (`/root/Session/Transport`) is identical on
## both peers — which is exactly what `@rpc` needs to route a call.
##
## Packets are plain dictionaries serialised with `var_to_bytes` and carried by
## a single reliable, ordered RPC. The transport never looks inside them: it
## delivers dictionaries, nothing else.
##
## The transport also keeps the link alive: both peers send a one-byte reliable
## heartbeat once a second. ENet's own idle detection can take a very long time
## when the peer that dies had nothing to acknowledge, which would leave the
## other side sitting in a match forever; with keepalives a dead peer is noticed
## in a few seconds and reported through `peer_left` + `transport_error`.
##
## Failure handling: every recoverable network failure (port busy, refused
## connection, timeout, peer gone) is reported through `transport_error` with a
## message meant for the player. `push_error` is reserved for programming
## mistakes, not for network conditions.
class_name QGEnetTransport
extends QGTransport

## Peer id of the server. The contract fixes it to 1.
const HOST_PEER_ID := 1

const PORT_MIN := 1
const PORT_MAX := 65535

## How long a client waits for the ENet handshake before giving up. ENet's own
## timeout for a dead connection is much longer, which is fine for gameplay but
## far too slow to tell a player "could not connect".
const CONNECT_TIMEOUT_MSEC := 8000

## Keepalive cadence and the silence after which a peer is considered gone.
## The heartbeat travels through the same reliable RPC as game packets and is
## recognised by a one-byte sentinel: a serialised dictionary always starts with
## the Dictionary type marker, so a one-byte payload cannot be a real packet.
## (A zero-byte packed array is not usable: Godot's raw-argument fast path drops
## empty packed arrays, which shows up as "called with 0 arguments".)
const KEEPALIVE_INTERVAL_MSEC := 1000
const PEER_TIMEOUT_MSEC := 6000
const KEEPALIVE_SENTINEL := 0

@rpc("any_peer", "call_remote", "reliable")
func _rpc_packet(payload: PackedByteArray) -> void:
	var sender := multiplayer.get_remote_sender_id()
	_peer_last_seen[sender] = Time.get_ticks_msec()
	if payload.size() == 1 and payload[0] == KEEPALIVE_SENTINEL:
		return # Keepalive: no game packet inside.
	var packet: Variant = bytes_to_var(payload)
	if typeof(packet) != TYPE_DICTIONARY:
		transport_error.emit("收到无法解析的网络数据包，已忽略")
		return
	packet_received.emit(sender, packet)


var _peer: ENetMultiplayerPeer = null
var _host_mode := false
var _connecting := false
var _connect_started_msec := 0
var _connect_address := ""
var _connect_port := 0
var _known_peers: Dictionary = {}
var _peer_last_seen: Dictionary = {}
var _last_keepalive_msec := 0
var _send_failure_reported := false
var _signals_attached := false

## Peers are kept alive across a deferred frame so that `stop()` may be called
## from inside one of their own signals (for example a UI reaction to
## `peer_left`) without destroying a peer that is still unwinding its poll.
var _retired_peers: Array = []
var _purge_queued := false


func _ready() -> void:
	set_process(false)


# --------------------------------------------------------------------------
# Lifecycle
# --------------------------------------------------------------------------

func start_host(port: int, max_clients: int = 2) -> Error:
	stop()
	if port < PORT_MIN or port > PORT_MAX:
		transport_error.emit(tr("端口 %d 无效，有效范围是 %d-%d") % [port, PORT_MIN, PORT_MAX])
		return ERR_INVALID_PARAMETER

	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, maxi(1, max_clients))
	if error != OK:
		peer.close()
		transport_error.emit(tr("端口 %d 已被占用，无法创建房间") % port)
		return error

	_activate(peer, true)
	return OK


func start_client(address: String, port: int) -> Error:
	stop()
	var target := address.strip_edges()
	if target.is_empty():
		transport_error.emit("服务器地址不能为空")
		return ERR_INVALID_PARAMETER
	if port < PORT_MIN or port > PORT_MAX:
		transport_error.emit(tr("端口 %d 无效，有效范围是 %d-%d") % [port, PORT_MIN, PORT_MAX])
		return ERR_INVALID_PARAMETER

	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(target, port)
	if error != OK:
		peer.close()
		transport_error.emit(tr("无法连接到 %s:%d，请确认地址与端口") % [target, port])
		return error

	_activate(peer, false)
	_connecting = true
	_connect_started_msec = Time.get_ticks_msec()
	_connect_address = target
	_connect_port = port
	return OK


func stop() -> void:
	_teardown()


# --------------------------------------------------------------------------
# Queries
# --------------------------------------------------------------------------

func is_host() -> bool:
	return _host_mode and _peer != null


func my_peer_id() -> int:
	if _peer == null:
		return 0
	if _peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return 0
	return _peer.get_unique_id()


## Connected remote peers: the guests on the host, the host (id 1) on a client.
func peers() -> Array[int]:
	var out: Array[int] = []
	if not _is_connected():
		return out
	for peer_id in multiplayer.get_peers():
		out.append(int(peer_id))
	out.sort()
	return out


# --------------------------------------------------------------------------
# Sending
# --------------------------------------------------------------------------

func send(peer_id: int, packet: Dictionary) -> void:
	if not _can_send_to(peer_id):
		_report_send_failure()
		return
	_rpc_packet.rpc_id(peer_id, var_to_bytes(packet))


func broadcast(packet: Dictionary) -> void:
	if not _is_connected():
		return
	if multiplayer.get_peers().is_empty():
		return
	_rpc_packet.rpc(var_to_bytes(packet))


func _can_send_to(peer_id: int) -> bool:
	if not _known_peers.has(peer_id):
		return false
	if not _is_connected():
		return false
	return multiplayer.get_peers().has(peer_id)


func _is_connected() -> bool:
	if _peer == null:
		return false
	var api := multiplayer
	if api == null or api.multiplayer_peer != _peer:
		return false
	return _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## One report per failed connection, not one per rejected command: a client that
## keeps clicking after the host vanished must not flood the status strip.
func _report_send_failure() -> void:
	if _send_failure_reported:
		return
	_send_failure_reported = true
	transport_error.emit("网络连接已断开，数据未能发送")


# --------------------------------------------------------------------------
# Activation and teardown
# --------------------------------------------------------------------------

func _activate(peer: ENetMultiplayerPeer, host_mode: bool) -> void:
	_peer = peer
	_host_mode = host_mode
	_connecting = false
	_send_failure_reported = false
	_known_peers.clear()
	_peer_last_seen.clear()
	_last_keepalive_msec = Time.get_ticks_msec()
	multiplayer.multiplayer_peer = peer
	_attach_signals()
	set_process(true)


func _teardown() -> void:
	var peer := _peer
	var known: Array = _known_peers.keys()
	_peer = null
	_host_mode = false
	_connecting = false
	_connect_started_msec = 0
	_connect_address = ""
	_connect_port = 0
	_send_failure_reported = false
	_known_peers.clear()
	_peer_last_seen.clear()
	set_process(false)
	# Detach first: otherwise clearing the peer makes SceneMultiplayer emit
	# `server_disconnected`, and the player would see "connection lost" after
	# deliberately leaving the match.
	_detach_signals()
	if peer == null:
		return
	# Queue a graceful ENet disconnect for every connected peer before the host
	# is destroyed. Without this the pending reliable packets (the final state
	# and the "over" packet) are discarded and the other side never learns how
	# the match ended.
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		for raw_id in known:
			var peer_id := int(raw_id)
			if peer.get_peer(peer_id) != null:
				peer.disconnect_peer(peer_id, false)
	var api := multiplayer
	if api != null and api.multiplayer_peer == peer:
		api.multiplayer_peer = null
	peer.close()
	_retire_peer(peer)


func _retire_peer(peer: ENetMultiplayerPeer) -> void:
	_retired_peers.append(peer)
	if _purge_queued:
		return
	_purge_queued = true
	call_deferred("_purge_retired_peers")


func _purge_retired_peers() -> void:
	_purge_queued = false
	_retired_peers.clear()


# --------------------------------------------------------------------------
# Multiplayer API signals
# --------------------------------------------------------------------------

func _attach_signals() -> void:
	if _signals_attached:
		return
	var api := multiplayer
	if api == null:
		return
	if not api.peer_connected.is_connected(_on_peer_connected):
		api.peer_connected.connect(_on_peer_connected)
	if not api.peer_disconnected.is_connected(_on_peer_disconnected):
		api.peer_disconnected.connect(_on_peer_disconnected)
	if not api.connected_to_server.is_connected(_on_connected_to_server):
		api.connected_to_server.connect(_on_connected_to_server)
	if not api.connection_failed.is_connected(_on_connection_failed):
		api.connection_failed.connect(_on_connection_failed)
	if not api.server_disconnected.is_connected(_on_server_disconnected):
		api.server_disconnected.connect(_on_server_disconnected)
	_signals_attached = true


func _detach_signals() -> void:
	if not _signals_attached:
		return
	_signals_attached = false
	var api := multiplayer
	if api == null:
		return
	if api.peer_connected.is_connected(_on_peer_connected):
		api.peer_connected.disconnect(_on_peer_connected)
	if api.peer_disconnected.is_connected(_on_peer_disconnected):
		api.peer_disconnected.disconnect(_on_peer_disconnected)
	if api.connected_to_server.is_connected(_on_connected_to_server):
		api.connected_to_server.disconnect(_on_connected_to_server)
	if api.connection_failed.is_connected(_on_connection_failed):
		api.connection_failed.disconnect(_on_connection_failed)
	if api.server_disconnected.is_connected(_on_server_disconnected):
		api.server_disconnected.disconnect(_on_server_disconnected)


func _on_peer_connected(peer_id: int) -> void:
	if _peer == null or _known_peers.has(peer_id):
		return
	_known_peers[peer_id] = true
	_peer_last_seen[peer_id] = Time.get_ticks_msec()
	if peer_id == HOST_PEER_ID:
		# The client is online now: this is the one moment `QGSession` can send
		# its join request, so `peer_joined(1)` must fire exactly once here.
		_connecting = false
		_connect_started_msec = 0
	peer_joined.emit(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	if not _known_peers.has(peer_id):
		return
	_known_peers.erase(peer_id)
	_peer_last_seen.erase(peer_id)
	peer_left.emit(peer_id)


func _on_connected_to_server() -> void:
	if _peer == null:
		return
	_connecting = false
	_connect_started_msec = 0
	# Normally peer_connected(1) fires and _on_peer_connected emits peer_joined, which
	# is what makes QGSession send `hello`. Some platform/timing combinations only
	# report connected_to_server; without this fallback the guest sits connected but
	# never joins and the host waits forever. _on_peer_connected is idempotent.
	if not _known_peers.has(HOST_PEER_ID):
		_on_peer_connected(HOST_PEER_ID)


func _on_connection_failed() -> void:
	if _peer == null:
		return
	var address := _connect_address
	var port := _connect_port
	_teardown()
	transport_error.emit(tr("无法连接到 %s:%d，请确认房主已创建房间") % [address, port])


func _on_server_disconnected() -> void:
	if _peer == null:
		return
	if _known_peers.has(HOST_PEER_ID):
		_known_peers.erase(HOST_PEER_ID)
		_peer_last_seen.erase(HOST_PEER_ID)
		peer_left.emit(HOST_PEER_ID)
	_teardown()
	transport_error.emit("与房主的连接已断开")


# --------------------------------------------------------------------------
# Keepalive and timeout handling
# --------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if _peer == null:
		set_process(false)
		return
	if _connecting:
		if Time.get_ticks_msec() - _connect_started_msec >= CONNECT_TIMEOUT_MSEC:
			var address := _connect_address
			var port := _connect_port
			_connecting = false
			_teardown()
			transport_error.emit(tr("连接 %s:%d 超时，请检查地址、端口与防火墙") % [address, port])
		return
	if not _is_connected():
		return
	_send_keepalive_if_due()
	_drop_silent_peers()


func _send_keepalive_if_due() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_keepalive_msec < KEEPALIVE_INTERVAL_MSEC:
		return
	_last_keepalive_msec = now
	if _host_mode:
		if not multiplayer.get_peers().is_empty():
			_rpc_packet.rpc(PackedByteArray([KEEPALIVE_SENTINEL]))
	elif multiplayer.get_peers().has(HOST_PEER_ID):
		_rpc_packet.rpc_id(HOST_PEER_ID, PackedByteArray([KEEPALIVE_SENTINEL]))


func _drop_silent_peers() -> void:
	var now := Time.get_ticks_msec()
	var lost: Array[int] = []
	for raw_id in _known_peers.keys():
		var peer_id := int(raw_id)
		if now - int(_peer_last_seen.get(peer_id, now)) > PEER_TIMEOUT_MSEC:
			lost.append(peer_id)
	for peer_id in lost:
		if not _host_mode and peer_id == HOST_PEER_ID:
			_known_peers.erase(peer_id)
			_peer_last_seen.erase(peer_id)
			peer_left.emit(peer_id)
			_teardown()
			transport_error.emit("与房主的连接已断开")
			return
		_drop_peer(peer_id)


func _drop_peer(peer_id: int) -> void:
	if not _known_peers.has(peer_id):
		return
	_known_peers.erase(peer_id)
	_peer_last_seen.erase(peer_id)
	peer_left.emit(peer_id)
	var api: Variant = multiplayer
	if api != null and api.has_method("disconnect_peer") and api.get_peers().has(peer_id):
		api.call("disconnect_peer", peer_id)
