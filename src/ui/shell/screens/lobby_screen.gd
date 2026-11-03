## 联机对战: create a room, or join one on the local network.
##
## The screen is a small state machine so the player can always tell what the
## game is doing: idle (two cards) → hosting / joining (one focused card with
## copyable addresses) → in-lobby (both players listed, match about to start).
##
## It talks to `Session` only; the wire protocol stays out of the UI.
class_name QGLobbyScreen
extends "res://src/ui/shell/screen.gd"

const TH := preload("res://src/ui/theme/qg_theme.gd")
const NF := preload("res://src/ui/shell/widgets/number_field.gd")
const SEG := preload("res://src/ui/shell/widgets/segmented.gd")

const BOARD_SIZES := [5, 9, 13, 19]
const BOARD_LABELS := ["5 路", "9 路", "13 路", "19 路"]
const JOIN_TIMEOUT := 12.0

const STATE_IDLE := "idle"
const STATE_HOSTING := "hosting"
const STATE_JOINING := "joining"
const STATE_IN_LOBBY := "in_lobby"

var _state := STATE_IDLE
var _status := ""
var _error := ""
var _target := ""
var _body: VBoxContainer = null
var _status_label: Label = null
var _status_dot: TextureRect = null
var _board_seg = null
var _host_port = null
var _join_address: LineEdit = null
var _join_port = null
var _pulse_time := 0.0
var _join_elapsed := 0.0
var _timed_out := false
var _pulse_dots: Array = []
var _pulse_labels: Array = []


func _ready() -> void:
	build_page("联机对战", "两台电脑，同一个棋盘",
		"房主创建房间，把本机地址发给对手；对手输入地址即可加入。")
	add_topbar_note("局域网 · 2 人")

	_body = UI.vbox(UI.GAP_LG)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_body)

	content.add_child(UI.divider())
	var status_row := UI.hbox(UI.GAP_SM)
	_status_dot = UI.status_dot(QGPalette.TEXT_DIM, 6)
	status_row.add_child(_status_dot)
	_status_label = UI.dim("")
	status_row.add_child(_status_label)
	content.add_child(status_row)
	set_process(true)


# --------------------------------------------------------------------------
# Lifecycle
# --------------------------------------------------------------------------

func on_show() -> void:
	if Session.is_online() and not Session.started:
		var info: Dictionary = Session.lobby_info()
		if bool(info.get("ready", false)):
			_state = STATE_IN_LOBBY
		elif Session.mode == QGSession.Mode.HOST:
			_state = STATE_HOSTING
		else:
			_state = STATE_JOINING
		_status = "已进入房间，等待对局开始。" if _state == STATE_IN_LOBBY else "等待对手加入…"
	else:
		_reset_to_idle()
	_sync_status()
	_render()


func on_hide() -> void:
	# Walking away from the lobby closes the room: a host with no UI to wait in
	# must not keep a port open.
	if Session.is_online() and not Session.started:
		Session.leave()
		_reset_to_idle()


func _reset_to_idle() -> void:
	_state = STATE_IDLE
	_status = "尚未连接 · 创建房间或加入房间后在这里显示连接状态"
	_error = ""
	_target = ""
	_timed_out = false
	_join_elapsed = 0.0


# --------------------------------------------------------------------------
# Session plumbing
# --------------------------------------------------------------------------

## Forwarded by the shell from `Session.status_changed`.
func set_status(text: String) -> void:
	_status = text
	_sync_status()


## Forwarded by the shell from `Session.lobby_changed`.
func set_lobby(info: Dictionary) -> void:
	if not Session.is_online() or Session.started:
		return
	if bool(info.get("ready", false)):
		_state = STATE_IN_LOBBY
		_status = "对手已加入，双方就位。"
	else:
		# A lobby event can also arrive while we are still alone in the room
		# (the host announcing itself, or a guest leaving): stay on the waiting
		# card that matches our role instead of pretending both players are here.
		_state = STATE_HOSTING if Session.mode == QGSession.Mode.HOST else STATE_JOINING
		_status = "等待对手加入…" if _state == STATE_HOSTING else "正在连接房主…"
	_error = ""
	_sync_status()
	_render()


func _on_host_pressed() -> void:
	var board_size := _selected_board_size()
	var port := int(_host_port.get_value())
	Settings.board_size = board_size
	Settings.server_port = port
	Settings.save_settings()
	var result: Dictionary = Session.host_match(board_size, Settings.player_name, port)
	_error = "" if bool(result.get("ok", false)) else String(result.get("reason", "无法创建房间"))
	if _error.is_empty():
		_state = STATE_HOSTING
		_status = "房间已创建，等待对手加入。"
	else:
		_state = STATE_IDLE
		_status = _error
		shell.toast(_error)
	_sync_status()
	_render()


func _on_join_pressed() -> void:
	var address := _join_address.text.strip_edges()
	if address.is_empty():
		_error = "请填写房主的 IP 地址。"
		_status = _error
		_sync_status()
		_render()
		return
	var port := int(_join_port.get_value())
	Settings.last_address = address
	Settings.server_port = port
	Settings.save_settings()
	var result: Dictionary = Session.join_match(address, port, Settings.player_name)
	_error = "" if bool(result.get("ok", false)) else String(result.get("reason", "无法连接"))
	if _error.is_empty():
		_target = address
		_state = STATE_JOINING
		_timed_out = false
		_join_elapsed = 0.0
		_status = tr("正在连接 %s:%d …") % [address, port]
	else:
		_state = STATE_IDLE
		_status = _error
		shell.toast(_error)
	_sync_status()
	_render()


func _on_cancel_pressed() -> void:
	Session.leave()
	_reset_to_idle()
	_status = "已取消。"
	_sync_status()
	_render()


func _on_copy_pressed(text: String) -> void:
	DisplayServer.clipboard_set(text)
	if shell != null:
		shell.toast(tr("已复制 %s") % text)


# --------------------------------------------------------------------------
# Rendering
# --------------------------------------------------------------------------

func _render() -> void:
	_clear(_body)
	_pulse_dots.clear()
	_pulse_labels.clear()
	match _state:
		STATE_HOSTING:
			_body.add_child(_build_hosting("房间已创建，等待对手", "对手加入后自动开局"))
		STATE_IN_LOBBY:
			_body.add_child(_build_hosting("双方已就位，即将开局", "开局后自动进入对局界面"))
		STATE_JOINING:
			_body.add_child(_build_joining())
		_:
			_body.add_child(_build_idle())


func _build_idle() -> VBoxContainer:
	var column := UI.vbox(UI.GAP_LG)
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var row := UI.hbox(UI.GAP_LG)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(_build_host_card())
	row.add_child(_build_join_card())
	column.add_child(row)

	if not _error.is_empty():
		column.add_child(_build_error_strip(_error))
	column.add_child(_build_tip_strip())
	return column


func _build_host_card() -> PanelContainer:
	var card := UI.card()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := UI.vbox(UI.GAP)
	card.add_child(column)

	column.add_child(UI.kicker("房主 · 执黑"))
	column.add_child(UI.h2("创建房间"))
	column.add_child(UI.muted("对手加入后自动开局，你执黑先行。", true))
	column.add_child(UI.spacer_h(UI.GAP_SM))

	_board_seg = SEG.new().setup(BOARD_LABELS, _board_index(Settings.board_size))
	column.add_child(UI.field("棋盘大小", _board_seg))

	_host_port = NF.new().configure(1024, 65535, Settings.server_port)
	column.add_child(UI.field("端口", _host_port))

	column.add_child(UI.spacer_h(UI.GAP_SM))
	var create := UI.button("创建房间", "PrimaryButton", 0, 48)
	create.pressed.connect(_on_host_pressed)
	column.add_child(create)

	column.add_child(UI.divider())
	column.add_child(UI.dim("创建后会显示本机地址，复制给对手即可。", true))
	return card


func _build_join_card() -> PanelContainer:
	var card := UI.card()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := UI.vbox(UI.GAP)
	card.add_child(column)

	column.add_child(UI.kicker("客方 · 执白"))
	column.add_child(UI.h2("加入房间"))
	column.add_child(UI.muted("输入房主屏幕上显示的地址和端口。", true))
	column.add_child(UI.spacer_h(UI.GAP_SM))

	_join_address = UI.line_edit("例如 192.168.1.4", _remembered_address(), 0)
	column.add_child(UI.field("IP 地址", _join_address))

	_join_port = NF.new().configure(1024, 65535, Settings.server_port)
	column.add_child(UI.field("端口", _join_port))

	column.add_child(UI.spacer_h(UI.GAP_SM))
	var join := UI.button("加入房间", "PrimaryButton", 0, 48)
	join.pressed.connect(_on_join_pressed)
	column.add_child(join)

	column.add_child(UI.divider())
	column.add_child(UI.dim("同一 Wi-Fi 下直接用局域网地址；跨网络需要端口转发。", true))
	return card


func _build_hosting(title: String, hint: String) -> Control:
	var centre := UI.hbox(0)
	centre.size_flags_vertical = Control.SIZE_EXPAND_FILL
	centre.add_child(_spring())
	var card := UI.card()
	card.theme_type_variation = &"AccentPanel"
	card.custom_minimum_size = Vector2(680, 0)
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	centre.add_child(card)
	centre.add_child(_spring())

	var column := UI.vbox(12)
	card.add_child(column)

	var head := UI.hbox(UI.GAP_SM)
	var dot := UI.status_dot(QGPalette.WARNING, 8)
	_pulse_dots.append(dot)
	head.add_child(dot)
	head.add_child(UI.kicker("等待中"))
	column.add_child(head)
	column.add_child(UI.h2(title))

	var waiting_label := UI.muted("", true)
	waiting_label.set_meta("base", hint)
	_pulse_labels.append(waiting_label)
	column.add_child(waiting_label)

	if Session.mode == QGSession.Mode.HOST:
		column.add_child(_build_address_panel())
	else:
		column.add_child(_build_target_panel())

	column.add_child(_build_players_row())
	column.add_child(UI.divider())

	var footer := UI.hbox(UI.GAP)
	footer.add_child(UI.dim("先手为黑 · 离开本页会关闭房间"))
	var spring := Control.new()
	spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spring)
	var cancel := UI.button("取消房间", "GhostButton", 132)
	cancel.pressed.connect(_on_cancel_pressed)
	footer.add_child(cancel)
	column.add_child(footer)
	return centre


func _build_address_panel() -> PanelContainer:
	var panel := UI.card(true)
	var column := UI.vbox(6)
	panel.add_child(column)

	var port := int(Session.lobby_info().get("port", Settings.server_port))
	column.add_child(_address_row("端口", str(port), "所有地址共用"))
	column.add_child(UI.divider())

	# Two addresses per row keeps the card compact even on machines with several
	# virtual adapters (Hyper-V, WSL), and every address stays visible.
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)
	for entry in _share_addresses():
		grid.add_child(_address_cell(String(entry["address"]), String(entry["tag"])))
	column.add_child(grid)
	return panel


func _address_cell(address: String, tag_text: String) -> HBoxContainer:
	var cell := UI.hbox(8)
	cell.custom_minimum_size = Vector2(0, 34)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value_label := UI.label(address, "BodyLabel")
	value_label.add_theme_font_override("font", QGPalette.number_font())
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.add_child(value_label)
	cell.add_child(UI.chip(tag_text, QGPalette.TEXT_MUTED))
	var copy := UI.button("复制", "GhostButton", 56, 28)
	copy.add_theme_font_size_override("font_size", 12)
	copy.pressed.connect(_on_copy_pressed.bind(address))
	cell.add_child(copy)
	return cell


func _address_row(caption: String, value: String, tag_text: String) -> HBoxContainer:
	var row := UI.hbox(UI.GAP)
	row.custom_minimum_size = Vector2(0, 34)
	var caption_label := UI.dim(caption)
	caption_label.custom_minimum_size = Vector2(150, 0)
	row.add_child(caption_label)
	row.add_child(UI.label(value, "H3Label"))
	var spring := Control.new()
	spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spring)
	row.add_child(UI.chip(tag_text, QGPalette.TEXT_MUTED))
	var copy := UI.button("复制", "GhostButton", 64, 28)
	copy.add_theme_font_size_override("font_size", 12)
	copy.pressed.connect(_on_copy_pressed.bind(value))
	row.add_child(copy)
	return row


func _build_target_panel() -> PanelContainer:
	var panel := UI.card(true)
	var column := UI.vbox(UI.GAP_SM)
	panel.add_child(column)
	var port := int(_join_port.get_value()) if _join_port != null else Settings.server_port
	column.add_child(_address_row("正在连接", "%s:%d" % [_target, port], "房主地址"))
	column.add_child(UI.muted("等待房主响应。", true))
	return panel


func _build_players_row() -> HBoxContainer:
	var info: Dictionary = Session.lobby_info()
	var row := UI.hbox(UI.GAP)
	var host_name := String(info.get("host", "房主"))
	var guest_name := String(info.get("guest", ""))
	row.add_child(_player_panel("房主", host_name, "黑", QGPalette.STONE_BLACK_EDGE, true))
	var waiting := guest_name.strip_edges().is_empty()
	row.add_child(_player_panel("对手", "等待加入…" if waiting else guest_name, "白" if not waiting else "空闲",
		QGPalette.STONE_WHITE_EDGE, not waiting))
	return row


func _player_panel(caption: String, name: String, chip_text: String, stone: Color, ready: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"StatPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := UI.hbox(UI.GAP_SM)
	panel.add_child(row)
	row.add_child(UI.status_dot(stone, 9))
	row.add_child(UI.dim(caption))
	var name_label := UI.label(name, "BodyLabel")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not ready:
		name_label.add_theme_color_override("font_color", QGPalette.TEXT_DIM)
	row.add_child(name_label)
	row.add_child(UI.chip(chip_text, QGPalette.TEXT_MUTED if ready else QGPalette.TEXT_DIM))
	return panel


func _build_joining() -> Control:
	var centre := UI.hbox(0)
	centre.size_flags_vertical = Control.SIZE_EXPAND_FILL
	centre.add_child(_spring())
	var card := UI.card()
	card.theme_type_variation = &"AccentPanel"
	card.custom_minimum_size = Vector2(680, 0)
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	centre.add_child(card)
	centre.add_child(_spring())

	var column := UI.vbox(UI.GAP)
	card.add_child(column)

	var head := UI.hbox(UI.GAP_SM)
	var dot := UI.status_dot(QGPalette.WARNING, 8)
	_pulse_dots.append(dot)
	head.add_child(dot)
	head.add_child(UI.kicker("连接中"))
	column.add_child(head)
	column.add_child(UI.h2("正在进入房间"))

	var wait_label := UI.muted("", true)
	wait_label.set_meta("base", "等待房主响应")
	_pulse_labels.append(wait_label)
	column.add_child(wait_label)

	column.add_child(UI.spacer_h(UI.GAP_SM))
	column.add_child(_build_target_panel())

	var tips := UI.vbox(UI.GAP_XS)
	tips.add_child(UI.dim("· 两台电脑要连在同一个局域网"))
	tips.add_child(UI.dim("· 房主需要在防火墙提示里允许游戏访问网络"))
	tips.add_child(UI.dim("· 端口要和房主显示的一致，默认 27777"))
	column.add_child(tips)

	column.add_child(UI.spacer_h(UI.GAP_SM))
	column.add_child(UI.divider())
	var footer := UI.hbox(UI.GAP)
	footer.add_child(UI.dim("连不上时换一个地址再试一次。"))
	var spring := Control.new()
	spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spring)
	var cancel := UI.button("取消连接", "GhostButton", 132)
	cancel.pressed.connect(_on_cancel_pressed)
	footer.add_child(cancel)
	column.add_child(footer)
	return centre


func _build_tip_strip() -> PanelContainer:
	var strip := UI.card(true)
	var row := UI.hbox(UI.GAP)
	strip.add_child(row)
	row.add_child(UI.status_dot(QGPalette.ACCENT, 6))
	row.add_child(UI.muted("两台电脑需要连在同一个路由器或 Wi-Fi 下。连接失败时，先确认防火墙放行了端口。", true))
	return strip


func _build_error_strip(message: String) -> PanelContainer:
	var strip := UI.card(true)
	var row := UI.hbox(UI.GAP)
	strip.add_child(row)
	row.add_child(UI.status_dot(QGPalette.DANGER, 6))
	var label := UI.muted(message, true)
	label.add_theme_color_override("font_color", QGPalette.DANGER)
	row.add_child(label)
	return strip


# --------------------------------------------------------------------------
# Status line + animation
# --------------------------------------------------------------------------

func _sync_status() -> void:
	if _status_label == null:
		return
	if _error.is_empty():
		_status_label.text = _status
		_status_label.add_theme_color_override("font_color", QGPalette.TEXT_MUTED)
	else:
		_status_label.text = _error
		_status_label.add_theme_color_override("font_color", QGPalette.DANGER)
	if _status_dot != null:
		var colour := QGPalette.TEXT_DIM
		if not _error.is_empty():
			colour = QGPalette.DANGER
		elif _state == STATE_IN_LOBBY:
			colour = QGPalette.SUCCESS
		elif _state == STATE_HOSTING or _state == STATE_JOINING:
			colour = QGPalette.WARNING
		_status_dot.texture = TH.circle_texture(colour, 6)
		_status_dot.modulate.a = 1.0


func _process(delta: float) -> void:
	if _state != STATE_HOSTING and _state != STATE_JOINING:
		return
	_pulse_time += delta
	var alpha := 0.35 + 0.65 * (0.5 + 0.5 * sin(_pulse_time * 4.0))
	for dot in _pulse_dots:
		if is_instance_valid(dot):
			dot.modulate.a = alpha
	var dots := ".".repeat(int(_pulse_time * 2.0) % 4)
	for label in _pulse_labels:
		if is_instance_valid(label):
			label.text = "%s %s" % [String(label.get_meta("base", "")), dots]
	if _state == STATE_JOINING:
		_join_elapsed += delta
		if _join_elapsed > JOIN_TIMEOUT and not _timed_out:
			_timed_out = true
			_error = "连接超时。请确认地址、端口，并检查防火墙。"
			_sync_status()


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

func _selected_board_size() -> int:
	if _board_seg == null:
		return int(BOARD_SIZES[1])
	return int(BOARD_SIZES[_board_seg.get_selected()])


func _board_index(size: int) -> int:
	var index := BOARD_SIZES.find(size)
	return index if index >= 0 else 1


## Last address typed by the player, but never the loopback default: prefilling
## "127.0.0.1" on a fresh profile would look like a real (wrong) setting.
func _remembered_address() -> String:
	var remembered := Settings.last_address.strip_edges()
	if remembered.is_empty() or remembered == "127.0.0.1":
		return ""
	return remembered


func _spring() -> Control:
	var spring := Control.new()
	spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spring


## IPv4 addresses a friend on the same network can type in. Virtual adapters
## (Hyper-V, WSL) show up too, so each row is tagged instead of hidden: the
## player picks the one that matches their Wi-Fi.
func _share_addresses() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for raw in IP.get_local_addresses():
		var address := String(raw)
		if address.contains(":"):
			continue
		if address.begins_with("127.") or address.begins_with("169.254."):
			continue
		var tag_text := "局域网"
		if address.begins_with("172.16.") or address.begins_with("172.17.") \
				or address.begins_with("172.18.") or address.begins_with("172.19.") \
				or address.begins_with("172.2") or address.begins_with("172.3"):
			tag_text = "虚拟网卡"
		rows.append({"address": address, "tag": tag_text})
	if rows.is_empty():
		rows.append({"address": "127.0.0.1", "tag": "本机"})
	rows.sort_custom(_address_before)
	return rows


## Home-router addresses first, then any other IPv4 the player can try.
func _address_before(a: Dictionary, b: Dictionary) -> bool:
	var left := String(a["address"])
	var right := String(b["address"])
	var left_rank := _address_rank(left)
	var right_rank := _address_rank(right)
	if left_rank != right_rank:
		return left_rank < right_rank
	return left < right


func _address_rank(address: String) -> int:
	if address.begins_with("192.168."):
		return 0
	if address.begins_with("10."):
		return 1
	if address.begins_with("172."):
		return 2
	return 3


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
