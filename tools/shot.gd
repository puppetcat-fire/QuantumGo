## Screenshot harness: renders any scene to a PNG so the Lead can review the
## picture without opening the editor.
##
## Usage (windowed, not headless — the renderer needs a display):
##   godot --path <project> --script res://tools/shot.gd -- <scene> <out.png> <scenario> <frames>
##
##   <scene>     res:// path of a scene or script-driven Control
##   <out.png>   absolute or res:// output path
##   <scenario>  empty | midgame | split | collapse | result
##   <frames>    frames to wait before capturing (default 8)
##
## Exits 0 when the PNG was written.
extends SceneTree

const SHOT_DIR := "res://tmp/screens"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var scene_path := "res://src/ui/shell/main.tscn"
	var out_path := "res://tmp/screens/shot.png"
	var scenario := "empty"
	var frames := 8
	if args.size() > 0:
		scene_path = args[0]
	if args.size() > 1:
		out_path = args[1]
	if args.size() > 2:
		scenario = args[2]
	if args.size() > 3:
		frames = int(args[3])

	_prepare(scenario)

	var instance: Node = null
	if scene_path.ends_with(".gd"):
		# Script-driven Control (screens built in code have no .tscn of their own).
		var script: Script = load(scene_path)
		if script == null:
			printerr("shot: cannot load script %s" % scene_path)
			quit(2)
			return
		instance = Control.new()
		instance.set_script(script)
	else:
		var packed: PackedScene = load(scene_path)
		if packed == null:
			printerr("shot: cannot load scene %s" % scene_path)
			quit(2)
			return
		instance = packed.instantiate()
	root.add_child(instance)

	for _frame in range(maxi(1, frames)):
		await process_frame

	if out_path.begins_with("res://"):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_path.get_base_dir()))
	var image := root.get_texture().get_image()
	if image == null:
		printerr("shot: no framebuffer")
		quit(3)
		return
	var save_target := out_path
	if not save_target.begins_with("res://") and not save_target.is_absolute_path():
		save_target = "res://" + save_target
	var code := image.save_png(save_target)
	print("shot: saved %s (%s) code=%d" % [save_target, str(image.get_size()), code])
	quit(0 if code == OK else 4)


## Builds a representative game state so screenshots are not always an empty board.
func _prepare(scenario: String) -> void:
	var session: QGSession = root.get_node_or_null("Session")
	if session == null:
		return
	if scenario == "empty":
		session.start_local(9)
		return

	session.start_local(9)
	var game: QGGame = session.game
	if game == null:
		return
	var n := game.board_size
	var play := [
		[QGTypes.BLACK, 4, 4], [QGTypes.WHITE, 2, 2], [QGTypes.BLACK, 6, 2],
		[QGTypes.WHITE, 3, 6], [QGTypes.BLACK, 6, 6], [QGTypes.WHITE, 2, 5],
		[QGTypes.BLACK, 5, 4], [QGTypes.WHITE, 1, 3], [QGTypes.BLACK, 7, 4],
		[QGTypes.WHITE, 3, 3], [QGTypes.BLACK, 6, 0], [QGTypes.WHITE, 2, 7],
	]
	for move in play:
		game.apply_move(0, int(move[1]) * n + int(move[2]), int(move[0]))

	if scenario == "midgame":
		session.state_changed.emit()
		return

	# A quantum split, so the shot shows multiple universes with weights.
	game.apply_quantum(0, 3 * n + 1, 6 * n + 4, game.turn_of(0))
	game.apply_move(1, 1 * n + 1, game.turn_of(1))
	game.apply_move(1, 5 * n + 7, game.turn_of(1))
	game.apply_quantum(1, 2 * n + 1, 7 * n + 7, game.turn_of(1))
	game.apply_move(0, 7 * n + 1, game.turn_of(0))

	if scenario == "result":
		game.resign(QGTypes.WHITE)
	session.state_changed.emit()
