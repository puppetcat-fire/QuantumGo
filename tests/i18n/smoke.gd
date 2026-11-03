## Localization smoke test: the same screens must come out Chinese and English,
## and switching language must not leave a screen half-translated.
##
##   godot --path <project> --script res://tests/i18n/smoke.gd
extends SceneTree

const MENU_EN := ["Local 2P", "Tutorial", "Online Match", "Leaderboard", "Rules", "Settings", "Quit"]
const MENU_ZH := ["单机双人", "新手引导", "联机对战", "排行榜", "规则", "设置", "退出游戏"]

var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var locale := root.get_node_or_null("L")
	_check(locale != null, "L autoload exists")
	if locale == null:
		_finish()
		return
	_check(int(locale.call("translation_count")) > 300, "English pack is loaded (%d strings)" % int(locale.call("translation_count")))

	print("-- English")
	locale.call("set_language", "en")
	var en_shell := await _boot_shell()
	var en_buttons := _collect_buttons(en_shell)
	for text in MENU_EN:
		_check(en_buttons.has(text), "English menu has '%s'" % text)
	_check(not en_buttons.has("单机双人"), "English menu has no leftover Chinese buttons")
	_check(_collect_labels(en_shell).size() > 0, "English menu renders labels")
	en_shell.queue_free()
	await process_frame

	print("-- Chinese")
	locale.call("set_language", "zh")
	var zh_shell := await _boot_shell()
	var zh_buttons := _collect_buttons(zh_shell)
	for text in MENU_ZH:
		_check(zh_buttons.has(text), "Chinese menu has '%s'" % text)
	zh_shell.queue_free()
	await process_frame

	print("-- dynamic strings")
	locale.call("set_language", "en")
	_check(String(locale.call("board_text", 9)) == "9x9", "English board size reads 9x9")
	locale.call("set_language", "zh")
	_check(String(locale.call("board_text", 9)) == "9 路", "Chinese board size reads 9 路")

	print("-- replay vocabulary")
	for source in ["复盘", "回看这一局", "◀ 上一步", "下一步 ▶", "没有可复盘的对局"]:
		_check(bool(locale.call("has_translation", source)), "English pack covers '%s'" % source)
	_check(not bool(locale.call("has_translation", "这条字符串不存在")), "missing strings are reported as untranslated")

	_finish()


func _boot_shell() -> Node:
	var packed: PackedScene = load("res://src/ui/shell/main.tscn")
	var shell := packed.instantiate()
	root.add_child(shell)
	for _index in range(3):
		await process_frame
	shell.call("show_screen", "menu")
	await process_frame
	return shell


## Text as the player will see it: Godot auto-translates control text at draw
## time, so the raw `text` property stays Chinese even in English mode.
func _visible_text(node: Node, raw: String) -> String:
	if node is Node and node.has_method("atr"):
		return String(node.call("atr", raw))
	return raw


func _collect_buttons(node: Node) -> Array[String]:
	var out: Array[String] = []
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is Button:
			out.append(_visible_text(current, String((current as Button).text)))
		for child in current.get_children():
			stack.append(child)
	return out


func _collect_labels(node: Node) -> Array[String]:
	var out: Array[String] = []
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is Label:
			out.append(_visible_text(current, String((current as Label).text)))
		for child in current.get_children():
			stack.append(child)
	return out


func _check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("   PASS %s" % message)
	else:
		failures += 1
		print("   FAIL %s" % message)


func _finish() -> void:
	print("")
	if failures == 0:
		print("I18N PASS (%d checks)" % checks)
		quit(0)
	else:
		print("I18N FAIL (%d of %d checks)" % [failures, checks])
		quit(1)
