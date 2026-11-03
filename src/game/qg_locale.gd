## 语言与翻译。
##
## 中文是源码里的原文（所有界面文案直接用中文写），英文放在
## `translations/en.json`：一个 `{中文: English}` 的字典。
##
## Godot 会自动翻译控件的文本属性（Label.text / Button.text / LineEdit 的
## placeholder 等），所以静态文案不需要在代码里写 `tr()`。只有运行时拼接出来的
## 句子（`"宇宙 %d · 权重 %d%%"` 这种）需要显式调用 `L.trf()`。
extends Node

const EN_PATH := "res://translations/en.json"

## "auto" | "zh" | "en"
var language: String = "auto"

var _en: Translation = null
var _zh: Translation = null
## Set when QG_LANG forced a language for screenshots/tests: the saved player
## preference must not overwrite it on the next idle frame.
var _forced: bool = false


func _ready() -> void:
	_load_translations()
	# Development / test hook: lets the screenshot harness render the English UI
	# without touching the player's saved settings.
	var override := OS.get_environment("QG_LANG")
	if override == "zh" or override == "en":
		language = override
		_forced = true
	apply_language()
	# Other autoloads may not exist yet at this point, so pick up the saved
	# preference on the next idle frame.
	call_deferred("_apply_saved_language")


func _apply_saved_language() -> void:
	if _forced:
		return
	var settings := get_node_or_null("/root/Settings")
	if settings == null:
		return
	var saved := String(settings.get("language"))
	if saved == language:
		return
	language = saved
	apply_language()


func _load_translations() -> void:
	if not FileAccess.file_exists(EN_PATH):
		return
	var file := FileAccess.open(EN_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("translations/en.json is not a dictionary")
		return
	var translation := Translation.new()
	translation.locale = "en"
	# Godot's lookup chain is zh_CN -> zh -> en -> fallback. Without a Chinese
	# entry, a `tr()` in a Chinese session would land on the English pack, so the
	# source strings are also registered as an identity pack for Chinese.
	var chinese := Translation.new()
	chinese.locale = "zh"
	var count := 0
	for key in parsed.keys():
		var source := String(key)
		var target := String(parsed[key])
		if source.is_empty() or target.is_empty():
			continue
		translation.add_message(source, target)
		chinese.add_message(source, source)
		count += 1
	TranslationServer.add_translation(translation)
	TranslationServer.add_translation(chinese)
	_en = translation
	_zh = chinese
	print("locale: loaded %d English strings" % count)


## Hand the translation resources back to the engine before shutdown: keeping
## them alive in an autoload shows up as "resources still in use at exit", which
## the headless test runners treat as an error.
func _exit_tree() -> void:
	if _en != null:
		TranslationServer.remove_translation(_en)
		_en = null
	if _zh != null:
		TranslationServer.remove_translation(_zh)
		_zh = null
	QGPalette.clear_cache()


## Resolves "auto" against the operating system locale.
func resolved_language() -> String:
	if language == "zh" or language == "en":
		return language
	var os_locale := OS.get_locale().to_lower()
	if os_locale.begins_with("zh"):
		return "zh"
	return "en"


func apply_language() -> void:
	var resolved := resolved_language()
	# Source strings are Chinese, so a Chinese user needs no translation at all.
	TranslationServer.set_locale("zh_CN" if resolved == "zh" else "en")


func set_language(value: String) -> void:
	language = value
	# An explicit switch wins over the saved preference read on the next idle
	# frame (which may not have happened yet during tests and tooling).
	_forced = true
	apply_language()


func is_english() -> bool:
	return resolved_language() == "en"


## Translate a template before formatting it. Use this for every string that goes
## through `%` formatting, because the formatter runs after translation.
func trf(template: String) -> String:
	return tr(template)


## True when the English pack has an entry for this exact source string.
## `Translation.get_message` returns an empty string for unknown keys, so "not
## the source" alone is not enough to tell a real entry from a missing one.
func has_translation(source: String) -> bool:
	if _en == null:
		return false
	var translated := _en.get_message(source)
	return not translated.is_empty() and translated != source


## Number of English strings loaded. Zero means the pack failed to load.
func translation_count() -> int:
	return 0 if _en == null else _en.get_message_count()


## Board size in the form the language expects: "9 路" in Chinese, "9x9" in
## English. Kept out of the format templates because Go players read the size as
## a single unit, not as a number followed by a noun.
func board_text(size: int) -> String:
	if is_english():
		return "%dx%d" % [size, size]
	return "%d 路" % size
