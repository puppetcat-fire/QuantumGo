## Transport contract for networked matches.
##
## A transport moves dictionaries between peers and nothing else: it does not
## know what a move is. The host is always peer id 1.
##
## Signal semantics:
##   * host side: `peer_joined(guest_id)` for every guest that completes the
##     connection, `peer_left(guest_id)` when one drops;
##   * client side: `peer_joined(1)` exactly once, when the connection to the
##     host is established. This is the only "we are online" signal a client
##     gets, and `QGSession` uses it to send its join request.
##
## Implementations must deliver every packet reliably and in order, on both sides.
class_name QGTransport
extends Node

signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal packet_received(from_peer: int, packet: Dictionary)
signal transport_error(message: String)


func start_host(_port: int, _max_clients: int = 2) -> Error:
	push_error("QGTransport.start_host is abstract")
	return ERR_UNAVAILABLE


func start_client(_address: String, _port: int) -> Error:
	push_error("QGTransport.start_client is abstract")
	return ERR_UNAVAILABLE


func stop() -> void:
	pass


func is_host() -> bool:
	return false


func my_peer_id() -> int:
	return 0


func send(_peer_id: int, _packet: Dictionary) -> void:
	pass


func broadcast(_packet: Dictionary) -> void:
	pass


func peers() -> Array[int]:
	return []
