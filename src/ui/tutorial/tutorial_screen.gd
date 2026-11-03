## 互动教程: five short steps that teach the one mechanic this game adds to Go.
##
## The tutorial owns its own `QGGame` instead of going through `QGSession`: it is
## a scripted lesson, not a match, and it must stay deterministic no matter what
## the player clicks. It reuses the real `QGBoardView`, so what the player learns
## on is exactly what they play on.
class_name QGTutorialScreen
extends "res://src/ui/shell/screen.gd"

const BoardView := preload("res://src/ui/match/board_view.gd")

const BOARD_PX := 392
const STEP_COUNT := 5

const STEPS := [
	{
		"title": "这就是一盘围棋",
		"body": "目标没变：围出更多地盘，把对方的子围死。普通落子、气、提子、劫，都按围棋的规则来。\n\n量子围棋只多了一件事——你可以一手同时落在两个点上。",
		"hint": "点「下一步」开始落子。",
	},
	{
		"title": "先落一颗普通子",
		"body": "黑先。点棋盘上任意一个空交叉点，落一颗黑子。",
		"hint": "这一手只影响眼前这一个宇宙，和普通围棋一样。",
	},
	{
		"title": "现在试一次量子步",
		"body": "量子步一次点两个空点：A 点留在当前宇宙，B 点落进一个新建的宇宙，两边各占 50% 的可能性。\n\n先按「量子步」，再依次点两个空点。",
		"hint": "落下之后，你会看到两个棋盘并排出现。",
	},
	{
		"title": "提掉虚子，假宇宙消失",
		"body": "量子步之后，两个宇宙里各有一颗子是「虚」的——它可能根本不存在，但正常对局里谁也看不出是哪一颗。这盘棋你赢在知道它可能假，而不是知道哪个假。\n\n接下来这一课我替你揭开：带紫色虚线的那颗就是本局的虚子。\n\n堵住它最后一口气，就等于完成一次「观测」。",
		"hint": "在带紫色虚线的棋盘上，点虚子下面那个空交叉点。",
	},
	{
		"title": "坍缩之后按权重算分",
		"body": "虚子被提走，那个宇宙被证明是假的，连同它的 50% 一起消失，可能性回到另一个宇宙——棋盘又回到一个确定的世界。\n\n正常对局里，虚子在你提掉它之前一直看不出来；对局结束后可以复盘，那时候才看得到当时哪颗是虚的。",
		"hint": "这就是全部规则。祝你下得开心。",
	},
]

var _game: QGGame = null
var _step: int = 0
var _focus_id: int = 0
var _quantum_mode: bool = false
var _pending_a: int = -1
var _boards: Array[QGBoardView] = []
var _board_columns: Array[Control] = []
var _view_ids: Dictionary = {}
var _board_row: HBoxContainer = null
var _step_label: Label = null
var _title_label: Label = null
var _body_label: Label = null
var _hint_label: Label = null
var _quantum_button: Button = null
var _next_button: Button = null
## The universe the lesson's phantom lives in, resolved from the seeded coin.
var _phantom_universe: int = -1


func _ready() -> void:
	build_page("教程", "三分钟学会量子围棋", "跟着做一遍，比读规则快。")
	add_topbar_note("互动教程")

	var row := UI.hbox(UI.GAP_LG)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(row)
	row.add_child(_build_info_column())
	_board_row = UI.hbox(UI.GAP_LG)
	_board_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board_row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(_board_row)

	_go_to_step(0)


func on_show() -> void:
	# Restart the lesson whenever the player comes back to it.
	_go_to_step(0)


# --------------------------------------------------------------------------
# Layout
# --------------------------------------------------------------------------

func _build_info_column() -> Control:
	var wrapper := UI.vbox(0)
	wrapper.custom_minimum_size = Vector2(360, 0)
	wrapper.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var card := UI.card()
	wrapper.add_child(card)
	var column := UI.vbox(UI.GAP)
	card.add_child(column)

	_step_label = UI.kicker("")
	column.add_child(_step_label)
	column.add_child(UI.spacer_h(UI.GAP_XS))

	_title_label = UI.h2("")
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_title_label)
	column.add_child(UI.divider())

	_body_label = UI.body("")
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_body_label)

	column.add_child(UI.spacer_h(UI.GAP))
	_hint_label = UI.muted("", true)
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_hint_label)

	column.add_child(UI.spacer_h(UI.GAP_LG))
	var buttons := UI.vbox(UI.GAP_SM)
	column.add_child(buttons)

	_quantum_button = UI.button("量子步", "PrimaryButton", 0, 44)
	_quantum_button.pressed.connect(_on_quantum_pressed)
	buttons.add_child(_quantum_button)

	_next_button = UI.button("下一步", "PrimaryButton", 0, 44)
	_next_button.pressed.connect(_on_next_pressed)
	buttons.add_child(_next_button)

	var skip := UI.button("跳过教程", "GhostButton", 0, 34)
	skip.pressed.connect(func() -> void: go("menu"))
	buttons.add_child(skip)

	# Push the card to the top and leave the rest empty.
	wrapper.add_child(UI.spacer_h(UI.GAP_SM))
	return wrapper


# --------------------------------------------------------------------------
# Step machine
# --------------------------------------------------------------------------

func _go_to_step(step: int) -> void:
	_step = step
	_quantum_mode = false
	_pending_a = -1
	# 按钮文字是 _on_quantum_pressed 里改的；重进教程时只重置 _quantum_mode 会留下
	# "取消量子步" 的旧文字，看起来像按钮默认被选中。
	if _quantum_button != null:
		_quantum_button.text = "量子步"
	_prepare_game_for_step(step)
	_focus_id = _game.live_ids()[0] if not _game.live_ids().is_empty() else 0
	_rebuild_boards()

	var info: Dictionary = STEPS[step]
	_step_label.text = tr("第 %d 步 / 共 %d 步") % [step + 1, STEP_COUNT]
	_title_label.text = String(info["title"])
	_body_label.text = String(info["body"])
	_hint_label.text = String(info["hint"])

	_quantum_button.visible = step == 2
	_quantum_button.disabled = false
	_next_button.visible = step == 0 or step == STEP_COUNT - 1
	_next_button.text = "开始" if step == 0 else "完成"
	if step == 2:
		_quantum_button.grab_focus()
	elif _next_button.visible:
		_next_button.grab_focus()


func _prepare_game_for_step(step: int) -> void:
	match step:
		0, 1:
			_game = QGGame.create(9)
		2:
			# Continue from step 1 when the player actually placed a stone,
			# otherwise start clean so the lesson still works after a skip.
			if _game == null or _game.live_ids().size() != 1:
				_game = QGGame.create(9)
				_game.apply_move(0, _index(4, 4), QGTypes.BLACK)
		3:
			_game = _build_collapse_scenario()
		4:
			if _game == null:
				_game = _build_collapse_scenario()
				_resolve_collapse_demo()


## A two-universe position where the phantom sits in the corner with exactly one
## liberty, so the next click is a real capture and a real collapse.
##
## Which sibling carries the phantom is a seeded coin, so the lesson searches for
## a seed that puts it on the corner in the way the scripted moves expect. That
## keeps the engine free of test-only hooks.
func _build_collapse_scenario() -> QGGame:
	var point_a := _index(8, 8)
	var point_b := _index(0, 0)
	_phantom_universe = -1
	for seed_value in range(256):
		var probe := QGGame.create(9, seed_value)
		var split := probe.apply_quantum(0, point_a, point_b, QGTypes.BLACK)
		if not split["ok"]:
			continue
		for child_id in split["children"]:
			var child := probe.get_universe(child_id)
			if child.phantom_point != point_b:
				continue
			_phantom_universe = child_id
			# White takes the phantom's upper liberty, black plays elsewhere, and it
			# is white's turn again with the corner at one liberty.
			probe.apply_move(child_id, _index(0, 1), QGTypes.WHITE)
			probe.apply_move(child_id, _index(8, 0), QGTypes.BLACK)
			return probe
	# Should never happen, but a broken lesson must not crash the screen.
	_phantom_universe = -1
	return QGGame.create(9)


## Used when the player reaches the last step without performing the capture.
func _resolve_collapse_demo() -> void:
	if _phantom_universe >= 0 and _game.live_ids().has(_phantom_universe):
		_game.apply_move(_phantom_universe, _index(1, 0), QGTypes.WHITE)


func _on_next_pressed() -> void:
	_play_click()
	if _step == 0:
		_go_to_step(1)
	elif _step == STEP_COUNT - 1:
		go("menu")
	else:
		_go_to_step(mini(_step + 1, STEP_COUNT - 1))


func _on_quantum_pressed() -> void:
	if _step != 2:
		return
	_play_click()
	_quantum_mode = not _quantum_mode
	_pending_a = -1
	_quantum_button.text = "取消量子步" if _quantum_mode else "量子步"
	if _quantum_mode:
		_hint_label.text = "选好了：点第一个空点作为 A 点。"
	else:
		_hint_label.text = "量子步已取消。想落普通子直接点棋盘。"
	_rebuild_boards()


func _on_point_clicked(index: int, universe_id: int) -> void:
	_focus_id = universe_id
	match _step:
		1:
			if _game.apply_move(universe_id, index, QGTypes.BLACK)["ok"]:
				_play_stone(QGTypes.BLACK)
				_go_to_step(2)
		2:
			_handle_quantum_click(universe_id, index)
		3:
			_handle_collapse_click(universe_id, index)
	_rebuild_boards()


func _handle_quantum_click(universe_id: int, index: int) -> void:
	if not _quantum_mode:
		_hint_label.text = "先按「量子步」，再点两个空点。"
		return
	if _pending_a < 0:
		_pending_a = index
		_hint_label.text = "A 点已选。再点一个空点作为 B 点，棋盘就会分裂。"
		return
	if index == _pending_a:
		_hint_label.text = "A 点和 B 点不能是同一个点，换一个。"
		return
	var colour := _game.turn_of(universe_id)
	var result := _game.apply_quantum(universe_id, _pending_a, index, colour)
	if not result["ok"]:
		_hint_label.text = "这个位置不能落子（已有棋子或被劫住），换一个点试试。"
		return
	_play_split()
	_pending_a = -1
	_quantum_mode = false
	_go_to_step(3)


func _handle_collapse_click(universe_id: int, index: int) -> void:
	var result := _game.apply_move(universe_id, index, QGTypes.WHITE)
	if not result["ok"]:
		_hint_label.text = "这个点不能落子，找虚子旁边那个空交叉点。"
		return
	_play_stone(QGTypes.WHITE)
	if not Array(result["collapsed"]).is_empty():
		_play_collapse()
		_go_to_step(4)
	else:
		_hint_label.text = "提子成功了，但没有提到虚子。点虚子旁边那个空交叉点，才能完成观测。"


func _can_click(universe_id: int) -> bool:
	match _step:
		1:
			return _game.turn_of(universe_id) == QGTypes.BLACK
		2:
			return _game.turn_of(universe_id) != QGTypes.EMPTY
		3:
			# Only the phantom's universe is playable in the collapse lesson.
			return universe_id == _phantom_universe and _game.turn_of(universe_id) == QGTypes.WHITE
		_:
			return false


# --------------------------------------------------------------------------
# Boards
# --------------------------------------------------------------------------

func _rebuild_boards() -> void:
	# Detach and free the previous columns immediately: a board view is the node
	# whose signal we may be handling right now, so it must leave the tree before
	# the new step builds its boards in the same space.
	for column in _board_columns:
		if is_instance_valid(column):
			if column.get_parent() != null:
				column.get_parent().remove_child(column)
			column.queue_free()
	_board_columns.clear()
	_boards.clear()
	_view_ids.clear()
	if not is_instance_valid(_board_row):
		return
	for id in _game.live_ids():
		var universe := _game.get_universe(id)
		if universe == null:
			continue
		var column := UI.vbox(UI.GAP_SM)
		column.alignment = BoxContainer.ALIGNMENT_CENTER
		var caption := UI.label(
			tr("宇宙 %d · 权重 %d%%") % [id, universe.weight], "DimLabel"
		)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(caption)

		var view := BoardView.new()
		view.custom_minimum_size = Vector2(BOARD_PX, BOARD_PX)
		# The lesson always reveals the phantom: it is the one place where the
		# player is allowed to see what a normal match hides.
		view.apply_state(
			universe.position,
			universe.sealed,
			universe.last_move,
			universe.ko_point,
			_can_click(id),
			universe.turn,
			_quantum_mode and id == _focus_id,
			_pending_a if id == _focus_id else -1,
			true,
			[] as Array[int],
			true
		)
		view.point_clicked.connect(_on_point_clicked.bind(id))
		column.add_child(view)
		_boards.append(view)
		_view_ids[id] = view
		_board_columns.append(column)
		_board_row.add_child(column)


# --------------------------------------------------------------------------
# Test hooks. The smoke test drives the lesson through the real widgets; these
# accessors keep it from reaching into private state.
# --------------------------------------------------------------------------

func current_step() -> int:
	return _step


func step_title() -> String:
	return _title_label.text if _title_label != null else ""


func board_for(universe_id: int) -> QGBoardView:
	return _view_ids.get(universe_id, null)


func live_universe_count() -> int:
	return _game.live_ids().size() if _game != null else 0


## The universe the lesson's phantom lives in (-1 outside the collapse step).
func phantom_universe() -> int:
	return _phantom_universe


## Whether the lesson is currently in quantum-move mode (used by tests and by
## callers that need to reset the button state).
func quantum_mode_on() -> bool:
	return _quantum_mode


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

func _index(row: int, column: int) -> int:
	return row * 9 + column


func _play_click() -> void:
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("play_click"):
		sfx.call("play_click")


func _play_stone(colour: int) -> void:
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("play_stone"):
		sfx.call("play_stone", colour)


func _play_split() -> void:
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("play_split"):
		sfx.call("play_split")


func _play_collapse() -> void:
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("play_collapse"):
		sfx.call("play_collapse")
