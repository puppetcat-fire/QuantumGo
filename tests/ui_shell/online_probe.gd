## Shared helpers for the two-process online flow test.
##
## The test scripts drive the real shell UI (find the button, press it) instead of
## calling private methods, so the checks cover the wiring the player actually
## touches. Kept free of state: each process keeps its own counters.
extends RefCounted

const NUMBER_FIELD_SCRIPT := "res://src/ui/shell/widgets/number_field.gd"


static func find_button(node: Node, text: String) -> Button:
	if node == null:
		return null
	if node is Button and String(node.text).contains(text):
		return node
	for child in node.get_children():
		var found := find_button(child, text)
		if found != null:
			return found
	return null


static func find_label_text(node: Node, text: String) -> String:
	if node == null:
		return ""
	if node is Label and String(node.text).contains(text):
		return String(node.text)
	for child in node.get_children():
		var found := find_label_text(child, text)
		if not found.is_empty():
			return found
	return ""


static func find_line_edit(node: Node, placeholder_marker: String) -> LineEdit:
	if node is LineEdit:
		if placeholder_marker.is_empty() or String(node.placeholder_text).contains(placeholder_marker):
			return node
	for child in node.get_children():
		var found := find_line_edit(child, placeholder_marker)
		if found != null:
			return found
	return null


## All port fields on the lobby screen, in build order: host port first.
static func find_number_fields(node: Node, out: Array = []) -> Array:
	if node != null and node.get_script() != null and String(node.get_script().resource_path) == NUMBER_FIELD_SCRIPT:
		out.append(node)
	for child in node.get_children():
		find_number_fields(child, out)
	return out


## IPv4 addresses a second machine on the same LAN could type in.
static func local_ipv4() -> Array[String]:
	var addresses: Array[String] = []
	for raw in IP.get_local_addresses():
		var address := String(raw)
		if address.contains(":"):
			continue
		if address.begins_with("127.") or address.begins_with("169.254."):
			continue
		addresses.append(address)
	return addresses


static func snapshot_leaderboard(leaderboard: Node) -> Dictionary:
	return {
		"players": leaderboard.get("players").duplicate(true),
		"history": leaderboard.get("history").duplicate(true),
	}


static func restore_leaderboard(leaderboard: Node, snapshot: Dictionary) -> void:
	leaderboard.set("players", snapshot["players"])
	var history: Array = leaderboard.get("history")
	history.assign(snapshot["history"])
	leaderboard.call("save_data")


static func snapshot_settings(settings: Node) -> Dictionary:
	return {
		"board_size": settings.get("board_size"),
		"player_name": settings.get("player_name"),
		"server_port": settings.get("server_port"),
		"last_address": settings.get("last_address"),
	}


static func restore_settings(settings: Node, snapshot: Dictionary) -> void:
	for key in snapshot:
		settings.set(key, snapshot[key])
	settings.call("save_settings")
