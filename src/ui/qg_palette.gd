## Shared visual language. Every UI scene reads colours from here so the game
## looks like one product instead of six.
##
## Read-only for UI code: adjust values here, never inline a colour elsewhere.
class_name QGPalette
extends RefCounted

const BG_DEEP := Color("#0b1020")
const BG_PANEL := Color("#141b2e")
const BG_PANEL_LIGHT := Color("#1d2740")
const BG_HOVER := Color("#26334f")

const TEXT := Color("#e6ecf5")
const TEXT_MUTED := Color("#8a97ad")
const TEXT_DIM := Color("#5b6884")

const ACCENT := Color("#4fd1c5")
const ACCENT_DARK := Color("#2b8f86")
const VIOLET := Color("#8b7cf6")
const VIOLET_DARK := Color("#5d51b8")

const DANGER := Color("#e5484d")
const SUCCESS := Color("#46a758")
const WARNING := Color("#f5a524")

const BOARD_WOOD := Color("#c9a06a")
const BOARD_WOOD_DARK := Color("#a8844f")
const BOARD_LINE := Color("#6d5232")

const STONE_BLACK := Color("#16181d")
const STONE_BLACK_EDGE := Color("#3c4250")
const STONE_WHITE := Color("#f4f6fa")
const STONE_WHITE_EDGE := Color("#c2c8d4")

const PHANTOM_TINT := Color("#8b7cf6")
const LAST_MOVE := Color("#f5a524")

## Bundled OFL font. Shipping the game with this file is what guarantees Chinese
## glyphs on a player's machine, including Windows installs without a CJK
## language pack. See assets/fonts/OFL.txt.
const BUNDLED_FONT_PATH := "res://assets/fonts/NotoSansCJKsc-Regular.otf"

static var _cached_font: Font = null


## UI font. Always returns a CJK-capable font: the engine's bundled font has no
## Chinese glyphs at all, so a missed call shows up as tofu boxes.
static func font() -> Font:
	if _cached_font != null:
		return _cached_font
	if ResourceLoader.exists(BUNDLED_FONT_PATH):
		var bundled: Font = load(BUNDLED_FONT_PATH)
		if bundled != null:
			_cached_font = bundled
			return _cached_font
	_cached_font = system_font()
	return _cached_font


## Fallback used only when the bundled font is missing (e.g. an asset-less checkout).
static func system_font() -> Font:
	var system_font_resource := SystemFont.new()
	system_font_resource.font_names = PackedStringArray([
		"Microsoft YaHei UI", "Microsoft YaHei", "PingFang SC",
		"Noto Sans CJK SC", "Source Han Sans SC", "SimHei", "sans-serif",
	])
	system_font_resource.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	return system_font_resource


## Font used for board coordinates and weights.
static func number_font() -> Font:
	var system_font_resource := SystemFont.new()
	system_font_resource.font_names = PackedStringArray([
		"Consolas", "Cascadia Mono", "DejaVu Sans Mono", "monospace",
	])
	system_font_resource.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	return system_font_resource


## Drops the cached font. Called on shutdown so the headless test runners do not
## report "resources still in use at exit" for a font nobody needs any more.
static func clear_cache() -> void:
	_cached_font = null


static func stone_color(colour: int) -> Color:
	if colour == QGTypes.BLACK:
		return STONE_BLACK
	if colour == QGTypes.WHITE:
		return STONE_WHITE
	return Color(0, 0, 0, 0)
