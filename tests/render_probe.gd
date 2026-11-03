## Throwaway probe: can this machine render a frame and save it?
## Run without --headless: godot --path . --script res://tests/render_probe.gd
extends SceneTree


func _initialize() -> void:
	_run()


func _run() -> void:
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var rect := ColorRect.new()
	rect.color = Color(0.09, 0.11, 0.16)
	rect.size = Vector2(640, 360)
	layer.add_child(rect)
	var label := Label.new()
	label.text = "render probe OK"
	label.position = Vector2(40, 40)
	label.add_theme_font_size_override("font_size", 32)
	layer.add_child(label)

	await process_frame
	await process_frame
	var image := root.get_texture().get_image()
	if image == null:
		print("PROBE fail: no image")
		quit(1)
		return
	var path := "res://tmp/render_probe.png"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tmp"))
	var code := image.save_png(path)
	print("PROBE save_png -> %d, size=%s, path=%s" % [code, str(image.get_size()), ProjectSettings.globalize_path(path)])
	quit(0 if code == OK else 1)
