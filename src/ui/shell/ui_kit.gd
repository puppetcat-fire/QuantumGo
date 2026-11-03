## Small factory for the shell's widgets.
##
## Every screen composes itself out of these calls so spacing, type and colour
## stay uniform without a scene file per screen. Nothing here knows about the
## game; it only knows about `QGPalette`, `QGTheme` and Godot containers.
class_name QGUIKit
extends RefCounted

# Spacing ladder. Use the nearest step instead of inventing a number.
const GAP_XS := 4
const GAP_SM := 8
const GAP := 14
const GAP_LG := 22
const GAP_XL := 32
const GAP_XXL := 48

const PAGE_MARGIN_X := 72
const PAGE_MARGIN_TOP := 40
const PAGE_MARGIN_BOTTOM := 40


# --------------------------------------------------------------------------
# Text
# --------------------------------------------------------------------------

static func label(text: String, variation: String = "BodyLabel", wrap: bool = false) -> Label:
	var node := Label.new()
	node.text = text
	node.theme_type_variation = variation
	if wrap:
		node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		node.add_theme_constant_override("line_spacing", 6)
	return node


static func hero(text: String) -> Label:
	return label(text, "HeroLabel")


static func title(text: String) -> Label:
	return label(text, "TitleLabel")


static func h2(text: String) -> Label:
	return label(text, "H2Label")


static func h3(text: String) -> Label:
	return label(text, "H3Label")


static func kicker(text: String) -> Label:
	return label(text, "KickerLabel")


static func body(text: String, wrap: bool = true) -> Label:
	return label(text, "BodyLabel", wrap)


## Secondary prose: the default for explanatory copy.
static func muted(text: String, wrap: bool = true) -> Label:
	return label(text, "MutedLabel", wrap)


static func dim(text: String, wrap: bool = false) -> Label:
	return label(text, "DimLabel", wrap)


## A heading with the small accent bar the shell uses for section starts.
static func section_heading(text: String) -> HBoxContainer:
	var row := hbox(GAP)
	var bar := ColorRect.new()
	bar.color = QGPalette.ACCENT
	bar.custom_minimum_size = Vector2(3, 18)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	row.add_child(h3(text))
	return row


# --------------------------------------------------------------------------
# Containers
# --------------------------------------------------------------------------

static func vbox(separation: int = GAP) -> VBoxContainer:
	var node := VBoxContainer.new()
	node.add_theme_constant_override("separation", separation)
	return node


static func hbox(separation: int = GAP) -> HBoxContainer:
	var node := HBoxContainer.new()
	node.add_theme_constant_override("separation", separation)
	return node


static func spacer_h(height: int) -> Control:
	var node := Control.new()
	node.custom_minimum_size = Vector2(0, height)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


static func spacer_w(width: int) -> Control:
	var node := Control.new()
	node.custom_minimum_size = Vector2(width, 0)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


## Anchors a control to every edge of its parent. Call after `add_child`.
static func full_rect(control: Control) -> Control:
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return control


static func margins(left: int, top: int, right: int, bottom: int) -> MarginContainer:
	var node := MarginContainer.new()
	node.add_theme_constant_override("margin_left", left)
	node.add_theme_constant_override("margin_top", top)
	node.add_theme_constant_override("margin_right", right)
	node.add_theme_constant_override("margin_bottom", bottom)
	return node


static func page_margins() -> MarginContainer:
	return margins(PAGE_MARGIN_X, PAGE_MARGIN_TOP, PAGE_MARGIN_X, PAGE_MARGIN_BOTTOM)


static func card(inset: bool = false) -> PanelContainer:
	var node := PanelContainer.new()
	node.theme_type_variation = &"InsetPanel" if inset else &"CardPanel"
	return node


static func chip(text: String, color: Color = QGPalette.TEXT_MUTED) -> PanelContainer:
	var node := PanelContainer.new()
	node.theme_type_variation = &"Chip"
	node.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var text_node := label(text, "DimLabel")
	text_node.add_theme_color_override("font_color", color)
	node.add_child(text_node)
	return node


static func status_dot(color: Color, diameter: int = 8) -> TextureRect:
	var node := TextureRect.new()
	node.texture = QGTheme.circle_texture(color, diameter)
	node.custom_minimum_size = Vector2(diameter, diameter)
	node.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	node.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return node


static func divider(alpha: float = 0.06) -> ColorRect:
	var node := ColorRect.new()
	node.color = Color(QGPalette.TEXT, alpha)
	node.custom_minimum_size = Vector2(0, 1)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


static func vertical_divider(height: int = 0, alpha: float = 0.06) -> ColorRect:
	var node := ColorRect.new()
	node.color = Color(QGPalette.TEXT, alpha)
	node.custom_minimum_size = Vector2(1, height)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


## A scroll area that always fits its width (no horizontal scrolling) and only
## shows the vertical bar when the content is taller than the viewport.
static func scroll(inner: Control, separation: int = 0) -> ScrollContainer:
	var node := ScrollContainer.new()
	node.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	node.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	node.follow_focus = true
	node.add_theme_constant_override("separation", separation)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.add_child(inner)
	return node


# --------------------------------------------------------------------------
# Interactives
# --------------------------------------------------------------------------

static func button(text: String, variation: String = "", width: int = 0, height: int = QGTheme.BUTTON_HEIGHT) -> Button:
	var node := Button.new()
	node.text = text
	node.custom_minimum_size = Vector2(width, height)
	node.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if not variation.is_empty():
		node.theme_type_variation = variation
	node.pressed.connect(_on_button_pressed)
	return node


## Every shell button clicks the same way. The match screen has its own kit and
## plays its own sounds; this covers the menus only.
static func _on_button_pressed() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var sfx := tree.root.get_node_or_null("Sfx")
	if sfx != null and sfx.has_method("play_click"):
		sfx.call("play_click")


static func line_edit(placeholder: String, text: String = "", min_width: int = 0) -> LineEdit:
	var node := LineEdit.new()
	node.placeholder_text = placeholder
	node.text = text
	node.custom_minimum_size = Vector2(min_width, QGTheme.INPUT_HEIGHT)
	node.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return node


## A labelled row: description on the left, control on the right.
static func setting_row(title_text: String, hint_text: String, control: Control) -> HBoxContainer:
	var row := hbox(GAP_LG)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var text_block := vbox(GAP_XS)
	text_block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_block.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_block.add_child(label(title_text, "BodyLabel"))
	if not hint_text.is_empty():
		text_block.add_child(dim(hint_text, true))
	row.add_child(text_block)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(control)
	return row


## Form row used inside cards: a quiet caption above the control.
static func field(caption: String, control: Control) -> VBoxContainer:
	var column := vbox(GAP_SM)
	column.add_child(dim(caption))
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(control)
	return column
