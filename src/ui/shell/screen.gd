## Base class for every screen the shell routes to.
##
## The base owns the page frame: margins, the row with the back button, the
## kicker/title block and the `content` area. Screens only build their own body,
## which is what keeps all five pages aligned to the same grid.
##
## Screens never talk to each other: they call `shell.show_screen(id)`.
class_name QGShellScreen
extends Control

const UI := preload("res://src/ui/shell/ui_kit.gd")

## Typed loosely on purpose: the shell owns the screens, so a class-typed
## reference here would be a dependency cycle.
var shell = null
var content: VBoxContainer = null
var topbar: HBoxContainer = null
var page: VBoxContainer = null


func bind(shell_ref) -> void:
	shell = shell_ref


## Called every time the router shows this screen (including a re-show).
func on_show() -> void:
	pass


## Called when the router navigates away from this screen.
func on_hide() -> void:
	pass


func go(screen_id: String) -> void:
	if shell != null:
		shell.show_screen(screen_id)


## Builds the standard page frame and returns the empty `content` column.
## `subtitle` is a single quiet line under the title; keep it short.
func build_page(kicker_text: String, title_text: String, subtitle: String = "") -> VBoxContainer:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := UI.page_margins()
	add_child(margin)
	UI.full_rect(margin)

	page = UI.vbox(0)
	margin.add_child(page)

	topbar = UI.hbox(UI.GAP_SM)
	topbar.custom_minimum_size = Vector2(0, 34)
	page.add_child(topbar)
	var back := UI.button("←  返回", "GhostButton", 0, 34)
	back.add_theme_font_size_override("font_size", 13)
	back.pressed.connect(_on_back_pressed)
	topbar.add_child(back)

	page.add_child(UI.spacer_h(UI.GAP_LG))
	if not kicker_text.is_empty():
		page.add_child(UI.kicker(kicker_text))
		page.add_child(UI.spacer_h(UI.GAP_SM))
	page.add_child(UI.title(title_text))
	if not subtitle.is_empty():
		page.add_child(UI.spacer_h(UI.GAP_SM))
		var subtitle_label := UI.muted(subtitle, true)
		subtitle_label.add_theme_color_override("font_color", QGPalette.TEXT_MUTED)
		page.add_child(subtitle_label)

	page.add_child(UI.spacer_h(UI.GAP_XL))
	content = UI.vbox(UI.GAP_LG)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(content)
	return content


## Right side of the top bar: a quiet place for screen-level context.
func add_topbar_note(text: String) -> Label:
	var spring := Control.new()
	spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	topbar.add_child(spring)
	var note := UI.dim(text)
	topbar.add_child(note)
	return note


func _on_back_pressed() -> void:
	go("menu")
