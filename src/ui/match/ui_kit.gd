## Shared visual toolkit for the match screen.
##
## Everything here reads colours from QGPalette and builds controls with the
## bundled CJK font, so the match screen and its widgets look like one product.
class_name QGMatchUIKit
extends RefCounted

const FONT_SIZE_SMALL := 12
const FONT_SIZE_BODY := 14

static var _ui_font: Font = null
static var _bold_font: Font = null


## Regular UI font (bundled Noto Sans CJK, SystemFont only as a fallback).
static func font() -> Font:
	if _ui_font == null:
		_ui_font = QGPalette.font()
	return _ui_font


## Faux-bold variant of the UI font. The bundled font ships one weight only, so
## titles use a FontVariation with a small embolden instead of a second file.
static func bold_font() -> Font:
	if _bold_font == null:
		var variation := FontVariation.new()
		variation.base_font = font()
		variation.variation_embolden = 0.55
		_bold_font = variation
	return _bold_font


## Rounded flat box. `pad_x`/`pad_y` become the content margins, which is how
## PanelContainers get their padding.
static func flat_box(
	bg: Color,
	radius: int = 8,
	border: Color = Color(0, 0, 0, 0),
	border_width: int = 0,
	pad_x: float = 0.0,
	pad_y: float = 0.0
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(radius)
	if border_width > 0:
		style.border_color = border
		style.set_border_width_all(border_width)
	style.content_margin_left = pad_x
	style.content_margin_right = pad_x
	style.content_margin_top = pad_y
	style.content_margin_bottom = pad_y
	return style


## Standard panel look: dark card with a hairline border.
static func panel_style(
	pad_x: float = 0.0,
	pad_y: float = 0.0,
	border: Color = QGPalette.BG_PANEL_LIGHT,
	border_width: int = 1
) -> StyleBoxFlat:
	return flat_box(QGPalette.BG_PANEL, 10, border, border_width, pad_x, pad_y)


## Circle style box used for turn / colour dots.
static func stone_dot_style(colour: int, diameter: float = 14.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = QGPalette.stone_color(colour) if colour != QGTypes.EMPTY else QGPalette.TEXT_DIM
	if colour == QGTypes.BLACK:
		# Pure #16181d on the dark card is invisible; lift it to the stone rim grey.
		style.bg_color = QGPalette.STONE_BLACK_EDGE
	style.set_corner_radius_all(int(diameter * 0.5) + 2)
	if colour == QGTypes.BLACK:
		# A black stone on a dark card is invisible; use the stone rim grey as the
		# body and a near-black rim so it still reads as a stone at 12 px.
		style.bg_color = QGPalette.STONE_BLACK_EDGE
		style.border_color = QGPalette.STONE_BLACK
	elif colour == QGTypes.WHITE:
		style.bg_color = QGPalette.stone_color(colour)
		style.border_color = QGPalette.STONE_WHITE_EDGE
	else:
		style.bg_color = QGPalette.TEXT_DIM
		style.border_color = QGPalette.TEXT_DIM
	style.set_border_width_all(1)
	return style


static func make_label(
	text: String,
	size: int = FONT_SIZE_BODY,
	colour: Color = QGPalette.TEXT,
	is_bold: bool = false
) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", bold_font() if is_bold else font())
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## Button variants:
##   "ghost"  — dark chip, the default
##   "toggle" — ghost that lights up accent when pressed
##   "accent" — primary action
##   "danger" — destructive action
static func make_button(text: String, variant: String = "ghost", min_width: float = 0.0) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(min_width, 34)
	button.add_theme_font_override("font", font())
	button.add_theme_font_size_override("font_size", FONT_SIZE_BODY)
	style_button(button, variant)
	return button


static func style_button(button: Button, variant: String) -> void:
	var normal_bg := QGPalette.BG_PANEL_LIGHT
	var hover_bg := QGPalette.BG_HOVER
	var pressed_bg := QGPalette.ACCENT_DARK
	var normal_border := QGPalette.BG_HOVER
	var pressed_border := QGPalette.ACCENT
	var normal_text := QGPalette.TEXT
	var pressed_text := QGPalette.TEXT

	match variant:
		"toggle":
			pass
		"accent":
			normal_bg = QGPalette.ACCENT_DARK
			hover_bg = QGPalette.ACCENT
			pressed_bg = QGPalette.ACCENT_DARK.darkened(0.12)
			normal_border = QGPalette.ACCENT
			pressed_border = QGPalette.ACCENT
		"danger":
			normal_bg = QGPalette.DANGER.darkened(0.35)
			hover_bg = QGPalette.DANGER
			pressed_bg = QGPalette.DANGER.darkened(0.15)
			normal_border = QGPalette.DANGER
			pressed_border = QGPalette.DANGER
		_:
			pass

	button.add_theme_stylebox_override("normal", flat_box(normal_bg, 8, normal_border, 1, 14, 0))
	button.add_theme_stylebox_override("hover", flat_box(hover_bg, 8, normal_border, 1, 14, 0))
	button.add_theme_stylebox_override("pressed", flat_box(pressed_bg, 8, pressed_border, 1, 14, 0))
	button.add_theme_stylebox_override("hover_pressed", flat_box(pressed_bg.lightened(0.08), 8, pressed_border, 1, 14, 0))
	button.add_theme_stylebox_override("disabled", flat_box(QGPalette.BG_PANEL, 8, QGPalette.BG_PANEL_LIGHT, 1, 14, 0))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", normal_text)
	button.add_theme_color_override("font_hover_color", QGPalette.TEXT)
	button.add_theme_color_override("font_pressed_color", pressed_text)
	button.add_theme_color_override("font_hover_pressed_color", pressed_text)
	button.add_theme_color_override("font_disabled_color", QGPalette.TEXT_DIM)


## Human readable text for a QGTypes.ERR_* reason (or a session-only reason).
static func reason_text(reason: String) -> String:
	match reason:
		QGTypes.ERR_OCCUPIED:
			return "该点已有棋子"
		QGTypes.ERR_KO:
			return "打劫：此处暂时不能落子"
		QGTypes.ERR_SUICIDE:
			return "自杀手不合法"
		QGTypes.ERR_NOT_YOUR_TURN:
			return "还没轮到你"
		QGTypes.ERR_SEALED:
			return "该宇宙已经封印"
		QGTypes.ERR_QUANTUM_EXHAUSTED:
			return "不能再分裂：宇宙已达上限或权重太低"
		QGTypes.ERR_GAME_OVER:
			return "对局已经结束"
		QGTypes.ERR_BAD_POINTS:
			return "选点无效"
		QGTypes.ERR_OUT_OF_RANGE:
			return "选点无效"
		"undo_local_only":
			return "联机对局不能悔棋"
		"nothing_to_undo":
			return "没有可悔的棋"
		_:
			return reason if not reason.is_empty() else "操作失败"


## Weighted score in 目. The engine stores weight × area as an integer, so the
## display value is `value / 100` (a weight of 50% halves the area count).
static func format_units(value: int) -> String:
	return "%.1f" % (float(value) / 100.0)


## "D4"-style human name for a board index.
static func point_name(index: int, board_size: int) -> String:
	if index < 0 or board_size <= 0:
		return "—"
	@warning_ignore("integer_division")
	var row: int = index / board_size
	var col: int = index % board_size
	var letters := "ABCDEFGHJKLMNOPQRST"
	if col >= letters.length():
		return "—"
	return "%s%d" % [letters[col], board_size - row]


static func mode_text(mode: int) -> String:
	match mode:
		QGSession.Mode.HOST:
			return "房主 · 在线"
		QGSession.Mode.CLIENT:
			return "客户端 · 在线"
		_:
			return "本地双人"
