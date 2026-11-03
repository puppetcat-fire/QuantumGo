## Regenerates `res://src/ui/theme/qg_theme.tres` from the code builder.
##
## The builder in `qg_theme.gd` is the single source of truth: the shell builds
## its theme at runtime, so the game never depends on this file. The .tres exists
## so the Theme can be dropped into a scene in the editor and inspected there.
##
## Run after touching qg_theme.gd:
##   godot --headless --path <project> --script res://src/ui/theme/generate_theme.gd
extends SceneTree

const THEME_BUILDER := "res://src/ui/theme/qg_theme.gd"
const THEME_PATH := "res://src/ui/theme/qg_theme.tres"


func _initialize() -> void:
	var builder: GDScript = load(THEME_BUILDER)
	if builder == null:
		printerr("generate_theme: cannot load ", THEME_BUILDER)
		quit(1)
		return
	var theme := builder.call("build") as Theme
	if theme == null:
		printerr("generate_theme: builder did not return a Theme")
		quit(1)
		return
	var error := ResourceSaver.save(theme, THEME_PATH)
	if error != OK:
		printerr("generate_theme: save failed: ", error_string(error))
		quit(1)
		return
	print("generate_theme: saved ", THEME_PATH)
	quit(0)
