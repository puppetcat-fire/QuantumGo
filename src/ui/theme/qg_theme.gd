## The shared Theme for Quantum Go.
##
## Built in code so there is exactly one place that owns fonts, colours, corner
## radii and paddings. Screens never pick a raw font or size: they ask for a
## theme *variation* (`TitleLabel`, `PrimaryButton`, `CardPanel`, ...) or use
## `QGUIKit`, which does the picking for them.
##
## The font always comes from `QGPalette.font()`: the engine's built-in font has
## no Chinese glyphs, so a missed font assignment shows up as tofu boxes.
##
## `generate_theme.gd` saves a preview copy of this theme to
## `src/ui/theme/qg_theme.tres` for editor use. This builder stays authoritative;
## regenerate the .tres instead of hand-editing it.
class_name QGTheme
extends RefCounted

# Type scale. Keep headings few and the body honest.
const FONT_XL := 46
const FONT_TITLE := 32
const FONT_H2 := 22
const FONT_H3 := 17
const FONT_BODY := 15
const FONT_SMALL := 13
const FONT_TINY := 11

# Metrics.
const BUTTON_HEIGHT := 44
const INPUT_HEIGHT := 42
const CARD_RADIUS := 18
const CONTROL_RADIUS := 10
const PILL_RADIUS := 999

const HAIRLINE := 0.07

static var _bold: Font = null
static var _spaced: Font = null
static var _number: Font = null
static var _textures: Dictionary = {}


# --------------------------------------------------------------------------
# Fonts
# --------------------------------------------------------------------------

## Emboldened UI font derived from the shared CJK font. Used by headings and
## primary buttons, never inline `SystemFont` - the bundled font is the promise
## that Chinese renders on a fresh Windows install.
static func bold() -> Font:
	if _bold == null:
		_bold = _variation(QGPalette.font(), 0.45)
	return _bold


## Letterspaced regular font for the small uppercase kickers above titles.
## Font spacing is a Font API, so guard it in case a platform lacks it.
static func spaced() -> Font:
	if _spaced == null:
		var variation := _variation(QGPalette.font(), 0.0)
		if variation.has_method("set_spacing"):
			variation.set_spacing(TextServer.SPACING_GLYPH, 3)
		_spaced = variation
	return _spaced


static func number() -> Font:
	if _number == null:
		_number = QGPalette.number_font()
	return _number


static func _variation(base: Font, embolden: float) -> FontVariation:
	var variation := FontVariation.new()
	variation.base_font = base
	variation.variation_embolden = embolden
	return variation


# --------------------------------------------------------------------------
# Reusable primitives
# --------------------------------------------------------------------------

static func box(bg: Color, radius: int, border: int = 0, border_color: Color = Color(0, 0, 0, 0),
		pad: Vector4 = Vector4.ZERO) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(radius)
	style.set_border_width_all(border)
	style.border_color = border_color
	style.content_margin_left = pad.x
	style.content_margin_top = pad.y
	style.content_margin_right = pad.z
	style.content_margin_bottom = pad.w
	style.anti_aliasing = true
	return style


static func hairline(alpha: float = HAIRLINE) -> Color:
	return Color(QGPalette.TEXT, alpha)


## A filled, anti-aliased circle as a texture. Used for status dots, slider
## grabbers and other small round things that have no other asset source.
static func circle_texture(color: Color, diameter: int) -> ImageTexture:
	var key := "%s@%d" % [color.to_html(), diameter]
	if _textures.has(key):
		return _textures[key]
	var image := Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var centre := Vector2(diameter * 0.5, diameter * 0.5)
	var radius := diameter * 0.5 - 1.0
	for y in diameter:
		for x in diameter:
			var distance := Vector2(x + 0.5, y + 0.5).distance_to(centre)
			if distance <= radius:
				image.set_pixel(x, y, color)
			elif distance <= radius + 1.0:
				image.set_pixel(x, y, Color(color.r, color.g, color.b, color.a * (radius + 1.0 - distance)))
	var texture := ImageTexture.create_from_image(image)
	_textures[key] = texture
	return texture


# --------------------------------------------------------------------------
# Theme
# --------------------------------------------------------------------------

static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font = QGPalette.font()
	theme.default_font_size = FONT_BODY

	_build_labels(theme)
	_build_buttons(theme)
	_build_panels(theme)
	_build_inputs(theme)
	_build_sliders(theme)
	_build_scrollbars(theme)
	_build_misc(theme)
	return theme


static func _build_labels(theme: Theme) -> void:
	_label(theme, "Label", QGPalette.font(), FONT_BODY, QGPalette.TEXT)
	_label(theme, "HeroLabel", bold(), FONT_XL, QGPalette.TEXT)
	_label(theme, "TitleLabel", bold(), FONT_TITLE, QGPalette.TEXT)
	_label(theme, "H2Label", bold(), FONT_H2, QGPalette.TEXT)
	_label(theme, "H3Label", bold(), FONT_H3, QGPalette.TEXT)
	_label(theme, "KickerLabel", spaced(), FONT_TINY, QGPalette.ACCENT)
	_label(theme, "BodyLabel", QGPalette.font(), FONT_BODY, QGPalette.TEXT)
	_label(theme, "MutedLabel", QGPalette.font(), FONT_SMALL + 1, QGPalette.TEXT_MUTED)
	_label(theme, "DimLabel", QGPalette.font(), FONT_SMALL, QGPalette.TEXT_DIM)
	_label(theme, "ValueLabel", bold(), 28, QGPalette.TEXT)
	_label(theme, "MonoLabel", number(), FONT_SMALL, QGPalette.TEXT_MUTED)


static func _label(theme: Theme, type_name: String, font: Font, size: int, color: Color) -> void:
	if type_name != "Label":
		theme.set_type_variation(type_name, "Label")
	theme.set_font("font", type_name, font)
	theme.set_font_size("font_size", type_name, size)
	theme.set_color("font_color", type_name, color)
	theme.set_color("font_shadow_color", type_name, Color(0, 0, 0, 0))


static func _build_buttons(theme: Theme) -> void:
	# Secondary button: the workhorse. Quiet until you touch it.
	var normal := box(QGPalette.BG_PANEL, CONTROL_RADIUS, 1, hairline(), Vector4(22, 10, 22, 10))
	var hover := box(QGPalette.BG_HOVER, CONTROL_RADIUS, 1, Color(QGPalette.TEXT, 0.12), Vector4(22, 10, 22, 10))
	var pressed := box(QGPalette.BG_PANEL_LIGHT, CONTROL_RADIUS, 1, Color(QGPalette.ACCENT, 0.35), Vector4(22, 10, 22, 10))
	var focus := box(Color(0, 0, 0, 0), CONTROL_RADIUS, 2, Color(QGPalette.ACCENT, 0.55))
	var disabled := box(Color(QGPalette.BG_PANEL, 0.5), CONTROL_RADIUS, 1, hairline(0.04), Vector4(22, 10, 22, 10))
	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("focus", "Button", focus)
	theme.set_stylebox("disabled", "Button", disabled)
	theme.set_color("font_color", "Button", QGPalette.TEXT)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", QGPalette.ACCENT)
	theme.set_color("font_focus_color", "Button", QGPalette.TEXT)
	theme.set_color("font_disabled_color", "Button", QGPalette.TEXT_DIM)
	theme.set_font("font", "Button", QGPalette.font())
	theme.set_font_size("font_size", "Button", FONT_BODY)

	# Primary button: one per screen. Accent fill, dark text, soft glow.
	theme.set_type_variation("PrimaryButton", "Button")
	theme.set_stylebox("normal", "PrimaryButton", _glow_box(QGPalette.ACCENT, 0.22))
	theme.set_stylebox("hover", "PrimaryButton", _glow_box(QGPalette.ACCENT.lerp(Color.WHITE, 0.18), 0.28))
	theme.set_stylebox("pressed", "PrimaryButton", _glow_box(QGPalette.ACCENT_DARK, 0.18))
	theme.set_stylebox("focus", "PrimaryButton", focus)
	theme.set_stylebox("disabled", "PrimaryButton", box(Color(QGPalette.BG_PANEL_LIGHT, 0.7), CONTROL_RADIUS, 1, hairline(0.04), Vector4(22, 10, 22, 10)))
	theme.set_font("font", "PrimaryButton", bold())
	theme.set_color("font_color", "PrimaryButton", QGPalette.BG_DEEP)
	theme.set_color("font_hover_color", "PrimaryButton", QGPalette.BG_DEEP)
	theme.set_color("font_pressed_color", "PrimaryButton", QGPalette.BG_DEEP)
	theme.set_color("font_focus_color", "PrimaryButton", QGPalette.BG_DEEP)
	theme.set_color("font_disabled_color", "PrimaryButton", QGPalette.TEXT_DIM)

	# Ghost button: borders only, for back / cancel / tertiary actions.
	theme.set_type_variation("GhostButton", "Button")
	theme.set_stylebox("normal", "GhostButton", box(Color(0, 0, 0, 0), CONTROL_RADIUS, 1, hairline(0.1), Vector4(20, 9, 20, 9)))
	theme.set_stylebox("hover", "GhostButton", box(Color(QGPalette.TEXT, 0.05), CONTROL_RADIUS, 1, Color(QGPalette.TEXT, 0.16), Vector4(20, 9, 20, 9)))
	theme.set_stylebox("pressed", "GhostButton", box(Color(QGPalette.TEXT, 0.02), CONTROL_RADIUS, 1, Color(QGPalette.ACCENT, 0.3), Vector4(20, 9, 20, 9)))
	theme.set_stylebox("focus", "GhostButton", focus)
	theme.set_stylebox("disabled", "GhostButton", box(Color(0, 0, 0, 0), CONTROL_RADIUS, 1, hairline(0.04), Vector4(20, 9, 20, 9)))
	theme.set_color("font_color", "GhostButton", QGPalette.TEXT_MUTED)
	theme.set_color("font_hover_color", "GhostButton", QGPalette.TEXT)
	theme.set_color("font_pressed_color", "GhostButton", QGPalette.ACCENT)
	theme.set_color("font_focus_color", "GhostButton", QGPalette.TEXT)
	theme.set_color("font_disabled_color", "GhostButton", QGPalette.TEXT_DIM)

	# Danger button: leave a room, resign, delete.
	theme.set_type_variation("DangerButton", "Button")
	theme.set_stylebox("normal", "DangerButton", box(Color(0, 0, 0, 0), CONTROL_RADIUS, 1, Color(QGPalette.DANGER, 0.35), Vector4(20, 9, 20, 9)))
	theme.set_stylebox("hover", "DangerButton", box(Color(QGPalette.DANGER, 0.14), CONTROL_RADIUS, 1, Color(QGPalette.DANGER, 0.6), Vector4(20, 9, 20, 9)))
	theme.set_stylebox("pressed", "DangerButton", box(Color(QGPalette.DANGER, 0.22), CONTROL_RADIUS, 1, Color(QGPalette.DANGER, 0.8), Vector4(20, 9, 20, 9)))
	theme.set_stylebox("focus", "DangerButton", focus)
	theme.set_stylebox("disabled", "DangerButton", box(Color(0, 0, 0, 0), CONTROL_RADIUS, 1, hairline(0.04), Vector4(20, 9, 20, 9)))
	theme.set_color("font_color", "DangerButton", QGPalette.DANGER)
	theme.set_color("font_hover_color", "DangerButton", Color.WHITE)
	theme.set_color("font_pressed_color", "DangerButton", Color.WHITE)
	theme.set_color("font_focus_color", "DangerButton", QGPalette.DANGER)
	theme.set_color("font_disabled_color", "DangerButton", QGPalette.TEXT_DIM)

	# Segmented control cell (board size, tabs): quiet until selected.
	theme.set_type_variation("SegmentButton", "Button")
	theme.set_stylebox("normal", "SegmentButton", box(Color(QGPalette.BG_DEEP, 0.6), CONTROL_RADIUS, 1, hairline(0.08), Vector4(16, 8, 16, 8)))
	theme.set_stylebox("hover", "SegmentButton", box(Color(QGPalette.TEXT, 0.05), CONTROL_RADIUS, 1, Color(QGPalette.TEXT, 0.16), Vector4(16, 8, 16, 8)))
	theme.set_stylebox("pressed", "SegmentButton", box(Color(QGPalette.ACCENT, 0.16), CONTROL_RADIUS, 1, Color(QGPalette.ACCENT, 0.55), Vector4(16, 8, 16, 8)))
	theme.set_stylebox("focus", "SegmentButton", box(Color(0, 0, 0, 0), CONTROL_RADIUS, 1, Color(QGPalette.ACCENT, 0.3)))
	theme.set_stylebox("disabled", "SegmentButton", box(Color(QGPalette.BG_DEEP, 0.3), CONTROL_RADIUS, 1, hairline(0.04), Vector4(16, 8, 16, 8)))
	theme.set_color("font_color", "SegmentButton", QGPalette.TEXT_MUTED)
	theme.set_color("font_hover_color", "SegmentButton", QGPalette.TEXT)
	theme.set_color("font_pressed_color", "SegmentButton", QGPalette.ACCENT)
	theme.set_color("font_focus_color", "SegmentButton", QGPalette.TEXT)
	theme.set_color("font_disabled_color", "SegmentButton", QGPalette.TEXT_DIM)


static func _glow_box(color: Color, glow: float) -> StyleBoxFlat:
	var style := box(color, CONTROL_RADIUS, 0, Color(0, 0, 0, 0), Vector4(22, 10, 22, 10))
	style.shadow_color = Color(QGPalette.ACCENT, glow)
	style.shadow_size = 9
	style.shadow_offset = Vector2(0, 3)
	return style


static func _build_panels(theme: Theme) -> void:
	theme.set_stylebox("panel", "Panel", box(QGPalette.BG_PANEL, CARD_RADIUS, 1, hairline(0.05), Vector4(26, 24, 26, 24)))
	theme.set_stylebox("panel", "PanelContainer", box(QGPalette.BG_PANEL, CARD_RADIUS, 1, hairline(0.05), Vector4(26, 24, 26, 24)))

	# A card: the main content surface.
	theme.set_type_variation("CardPanel", "PanelContainer")
	var card := box(QGPalette.BG_PANEL, CARD_RADIUS, 1, hairline(0.06), Vector4(26, 24, 26, 26))
	card.shadow_color = Color(QGPalette.BG_DEEP, 0.55)
	card.shadow_size = 22
	card.shadow_offset = Vector2(0, 10)
	theme.set_stylebox("panel", "CardPanel", card)

	# A well inside a card: connection info, lists, notes.
	theme.set_type_variation("InsetPanel", "PanelContainer")
	theme.set_stylebox("panel", "InsetPanel", box(QGPalette.BG_DEEP, CONTROL_RADIUS + 2, 1, hairline(0.05), Vector4(18, 14, 18, 14)))

	# Compact well: one-line facts (players in a room, key/value rows).
	theme.set_type_variation("StatPanel", "PanelContainer")
	theme.set_stylebox("panel", "StatPanel", box(QGPalette.BG_DEEP, CONTROL_RADIUS + 2, 1, hairline(0.05), Vector4(14, 8, 14, 8)))

	# A card that wants attention (waiting room, active row).
	theme.set_type_variation("AccentPanel", "PanelContainer")
	var accent := box(QGPalette.BG_PANEL, CARD_RADIUS, 1, Color(QGPalette.ACCENT, 0.35), Vector4(26, 24, 26, 26))
	accent.shadow_color = Color(QGPalette.ACCENT, 0.1)
	accent.shadow_size = 24
	theme.set_stylebox("panel", "AccentPanel", accent)

	# Table rows.
	theme.set_type_variation("RowPanel", "PanelContainer")
	theme.set_stylebox("panel", "RowPanel", box(Color(0, 0, 0, 0), CONTROL_RADIUS, 0, Color(0, 0, 0, 0), Vector4(12, 8, 12, 8)))
	theme.set_type_variation("RowPanelAlt", "PanelContainer")
	theme.set_stylebox("panel", "RowPanelAlt", box(Color(QGPalette.BG_PANEL_LIGHT, 0.3), CONTROL_RADIUS, 0, Color(0, 0, 0, 0), Vector4(12, 8, 12, 8)))
	theme.set_type_variation("RowPanelHot", "PanelContainer")
	theme.set_stylebox("panel", "RowPanelHot", box(Color(QGPalette.ACCENT, 0.08), CONTROL_RADIUS, 1, Color(QGPalette.ACCENT, 0.22), Vector4(12, 8, 12, 8)))

	# Pill / chip: the smallest labelled unit.
	theme.set_type_variation("Chip", "PanelContainer")
	theme.set_stylebox("panel", "Chip", box(Color(QGPalette.BG_PANEL_LIGHT, 0.9), PILL_RADIUS, 1, hairline(0.06), Vector4(10, 3, 10, 3)))

	# Toast: a floating confirmation/error line at the bottom of the shell.
	theme.set_type_variation("ToastPanel", "PanelContainer")
	var toast := box(QGPalette.BG_PANEL_LIGHT, 12, 1, Color(QGPalette.ACCENT, 0.3), Vector4(18, 10, 18, 10))
	toast.shadow_color = Color(QGPalette.BG_DEEP, 0.7)
	toast.shadow_size = 18
	toast.shadow_offset = Vector2(0, 6)
	theme.set_stylebox("panel", "ToastPanel", toast)


static func _build_inputs(theme: Theme) -> void:
	theme.set_stylebox("normal", "LineEdit", box(QGPalette.BG_DEEP, CONTROL_RADIUS, 1, hairline(0.1), Vector4(14, 9, 14, 9)))
	theme.set_stylebox("focus", "LineEdit", box(QGPalette.BG_DEEP, CONTROL_RADIUS, 1, Color(QGPalette.ACCENT, 0.7), Vector4(14, 9, 14, 9)))
	theme.set_stylebox("read_only", "LineEdit", box(Color(QGPalette.BG_DEEP, 0.5), CONTROL_RADIUS, 1, hairline(0.04), Vector4(14, 9, 14, 9)))
	theme.set_color("font_color", "LineEdit", QGPalette.TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", QGPalette.TEXT_DIM)
	theme.set_color("font_selected_color", "LineEdit", Color.WHITE)
	theme.set_color("font_uneditable_color", "LineEdit", QGPalette.TEXT_DIM)
	theme.set_color("caret_color", "LineEdit", QGPalette.ACCENT)
	theme.set_color("selection_color", "LineEdit", Color(QGPalette.ACCENT, 0.3))
	theme.set_color("clear_button_color", "LineEdit", QGPalette.TEXT_DIM)
	theme.set_color("clear_button_color_pressed", "LineEdit", QGPalette.ACCENT)
	theme.set_font("font", "LineEdit", QGPalette.font())
	theme.set_font_size("font_size", "LineEdit", FONT_BODY)
	theme.set_constant("caret_width", "LineEdit", 2)


static func _build_sliders(theme: Theme) -> void:
	var track := box(QGPalette.BG_DEEP, 3, 1, hairline(0.08))
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var fill := box(QGPalette.ACCENT_DARK, 3)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	var fill_hot := box(QGPalette.ACCENT, 3)
	fill_hot.content_margin_top = 3
	fill_hot.content_margin_bottom = 3
	theme.set_stylebox("slider", "HSlider", track)
	theme.set_stylebox("grabber_area", "HSlider", fill)
	theme.set_stylebox("grabber_area_highlight", "HSlider", fill_hot)
	theme.set_icon("grabber", "HSlider", circle_texture(QGPalette.TEXT, 18))
	theme.set_icon("grabber_highlight", "HSlider", circle_texture(QGPalette.ACCENT, 20))


static func _build_scrollbars(theme: Theme) -> void:
	var track := box(Color(QGPalette.BG_DEEP, 0.4), 4)
	track.content_margin_left = 5
	track.content_margin_right = 5
	var grabber := box(Color(QGPalette.TEXT, 0.14), 4)
	grabber.content_margin_left = 5
	grabber.content_margin_right = 5
	var grabber_hot := box(Color(QGPalette.TEXT, 0.26), 4)
	grabber_hot.content_margin_left = 5
	grabber_hot.content_margin_right = 5
	for type_name in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", type_name, track)
		theme.set_stylebox("grabber", type_name, grabber)
		theme.set_stylebox("grabber_highlight", type_name, grabber_hot)
		theme.set_stylebox("grabber_pressed", type_name, grabber_hot)


static func _build_misc(theme: Theme) -> void:
	theme.set_stylebox("panel", "PopupPanel", box(QGPalette.BG_PANEL, CONTROL_RADIUS, 1, hairline(0.1), Vector4(8, 8, 8, 8)))
	theme.set_font("font", "PopupMenu", QGPalette.font())
	theme.set_font_size("font_size", "PopupMenu", FONT_BODY)
	theme.set_stylebox("panel", "PopupMenu", box(QGPalette.BG_PANEL, CONTROL_RADIUS, 1, hairline(0.1), Vector4(8, 8, 8, 8)))
	theme.set_stylebox("hover", "PopupMenu", box(Color(QGPalette.ACCENT, 0.16), 6, 0, Color(0, 0, 0, 0), Vector4(8, 6, 8, 6)))
	theme.set_stylebox("separator", "PopupMenu", box(hairline(0.08), 0, 0, Color(0, 0, 0, 0), Vector4(0, 3, 0, 3)))
	theme.set_color("font_color", "PopupMenu", QGPalette.TEXT)
	theme.set_color("font_hover_color", "PopupMenu", QGPalette.ACCENT)
	theme.set_color("font_disabled_color", "PopupMenu", QGPalette.TEXT_DIM)

	# Tooltips, if a screen adds one later.
	theme.set_stylebox("panel", "TooltipPanel", box(QGPalette.BG_PANEL_LIGHT, 8, 1, hairline(0.12), Vector4(12, 8, 12, 8)))
	theme.set_color("font_color", "TooltipLabel", QGPalette.TEXT)
	theme.set_font("font", "TooltipLabel", QGPalette.font())
	theme.set_font_size("font_size", "TooltipLabel", FONT_SMALL)

	# Rich text is not used by the shell yet, but keep it readable if a screen
	# reaches for it instead of stacking labels.
	theme.set_font("normal_font", "RichTextLabel", QGPalette.font())
	theme.set_font_size("normal_font_size", "RichTextLabel", FONT_BODY)
	theme.set_color("default_color", "RichTextLabel", QGPalette.TEXT)
	theme.set_font("bold_font", "RichTextLabel", bold())
