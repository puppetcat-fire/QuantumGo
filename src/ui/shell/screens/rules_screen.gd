## 规则: the whole variant on one page, readable in about two minutes.
##
## Written for a player who knows Go but has never seen a branching board. The
## diagram on the right is the same one the menu uses, so the picture they saw
## before their first game is the one that explains it here.
class_name QGRulesScreen
extends "res://src/ui/shell/screen.gd"

const Diagram := preload("res://src/ui/shell/widgets/quantum_diagram.gd")

const SECTIONS := [
	{
		"title": "目标",
		"body": [
			"围棋的目标没有变：围出比对手更多的地。变的是棋盘本身——量子围棋同时存在多个「宇宙」，每个宇宙都有自己的棋盘和行棋顺序。结算时按权重把所有宇宙的目数加起来比较。",
		],
	},
	{
		"title": "普通落子",
		"body": [
			"和围棋一样：黑先，双方轮流在一个交叉点落子，一块棋的气被提光就整块拿走。禁着点与劫争的规则不变，但它们只作用在你落子所在的那个宇宙里。",
		],
	},
	{
		"title": "量子落子",
		"body": [
			"一次量子落子同时点两个空点。正在下的那个宇宙当场退役，裂成两个平级的宇宙：一个拿着 A 点上的子，一个拿着 B 点上的子，权重各一半，两边都继续正常行棋。",
			"换句话说：你没有放弃任何一处，代价是两边的棋都只算一半。",
			"为了不让棋盘碎成一堆小数点，有两条硬限制：一局最多同时存在 6 个宇宙；权重低于 8% 的宇宙不能再分裂（再分下去只剩 4%，不值得看）。碰到限制时，「量子步」按钮会变灰。",
		],
	},
	{
		"title": "虚子与坍缩",
		"body": [
			"每次分裂，两颗新落下的子里恰好一颗是「虚子」——它可能根本不存在；另一颗一定为实。哪边是哪边，双方都看不到。",
			"虚子会沿分支继承：一个宇宙被分出去时带着虚子，它以后分裂出的宇宙都继续带着。所以一个深度 3 的分支身上可能挂着 0 到 3 颗虚子。",
			"虚子被提、或者虚子所在的那块棋参与提子时，它就被观测了：判定为空——携带它的那个宇宙连同下面的所有分支一起消失，权重交给同一次分裂里真实的那一半。",
			"坍缩是宇宙消失的唯一方式。也正因为如此，提掉一颗虚子，往往比吃掉几颗普通棋子更值钱。",
		],
	},
	{
		"title": "权重",
		"body": [
			"每个存活宇宙的权重就是它在最终结果里的票数，所有权重之和恒为 100%。一局最多 6 个宇宙，权重低于 8% 的宇宙不能再分裂。",
			"连续两次虚着会封印一个宇宙：里面不能再落子，但它的权重保留到结算。宇宙只剩一个、权重回到 100% 时，棋局又变回普通围棋。",
		],
	},
	{
		"title": "计分",
		"body": [
			"所有宇宙都被封印后进入结算：先点掉各宇宙里的死子、双方确认，再对每个宇宙单独数地，乘以权重相加，得到双方的「加权目数」，数字大的获胜。",
			"对局结束后可以逐步复盘，那时候才看得到当时哪些子是虚的，以及它们各自对应的实子。",
		],
	},
	{
		"title": "虚着与认输",
		"body": [
			"在一个宇宙里连续两次虚着，这个宇宙就被封印；所有存活宇宙都被封印后，对局结束并结算。认输立刻结束整局，和围棋一致。",
		],
	},
	{
		"title": "上手三步",
		"body": [
			"① 先用普通落子占角、连片，把一边的棋走扎实。",
			"② 在双方都有价值的位置做一次量子落子，让对手没法同时守住两边。",
			"③ 盯着虚子：它可能根本不存在，谁能先把它提掉，对方的这一支就整个消失。",
		],
	},
]


func _ready() -> void:
	build_page("规则", "量子围棋怎么下",
		"这一页足够你下完第一盘；更细的计分示例见对局界面。")
	add_topbar_note("约 2 分钟读完")

	var columns := UI.hbox(UI.GAP_LG)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)

	columns.add_child(_build_text_card())

	var side := UI.vbox(UI.GAP)
	side.custom_minimum_size = Vector2(420, 0)
	# Scrollable so the right column can never be clipped if the window is short.
	# Kept at a fixed width: the reading column on the left should get the slack.
	var side_scroll := UI.scroll(side)
	side_scroll.custom_minimum_size = Vector2(420, 0)
	side_scroll.size_flags_horizontal = Control.SIZE_FILL
	columns.add_child(side_scroll)
	side.add_child(_build_diagram_card())
	side.add_child(_build_summary_card())
	side.add_child(_build_tip_card())


func _build_text_card() -> PanelContainer:
	var card := UI.card()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var column := UI.vbox(UI.GAP)
	card.add_child(column)
	column.add_child(UI.h2("从围棋出发"))
	column.add_child(UI.muted("普通落子和量子落子都基于同一套围棋规则。先读这里，再去看对局。", true))
	column.add_child(UI.divider())

	var sections := UI.vbox(UI.GAP_LG)
	for index in SECTIONS.size():
		if index > 0:
			sections.add_child(UI.divider())
		sections.add_child(_build_section(SECTIONS[index]))
	# Keep prose clear of the scrollbar.
	var padded := UI.margins(0, 0, 10, 0)
	padded.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	padded.add_child(sections)
	var scroll := UI.scroll(padded)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	return card


func _build_section(section: Dictionary) -> VBoxContainer:
	var column := UI.vbox(UI.GAP_SM)
	column.add_child(UI.section_heading(String(section.get("title", ""))))
	for paragraph in section.get("body", []):
		column.add_child(UI.body(String(paragraph)))
	column.add_child(UI.spacer_h(UI.GAP_XS))
	return column


func _build_diagram_card() -> PanelContainer:
	var card := UI.card()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := UI.vbox(UI.GAP_SM)
	card.add_child(column)
	var diagram := Diagram.new()
	diagram.custom_minimum_size = Vector2(360, 232)
	diagram.set_animated(false)
	column.add_child(diagram)
	var caption := UI.dim("左边是实子，右边是虚子：同一手棋，两个宇宙。", true)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(caption)
	return card


func _build_summary_card() -> PanelContainer:
	var card := UI.card()
	card.theme_type_variation = &"AccentPanel"
	var column := UI.vbox(UI.GAP_SM)
	card.add_child(column)
	column.add_child(UI.kicker("一句话记住"))
	var summary := UI.body("量子落子 = 一次棋，两个宇宙，各占一半。虚子被判空，那一支就整个消失。", true)
	summary.add_theme_font_size_override("font_size", 17)
	column.add_child(summary)
	column.add_child(UI.dim(tr("一局最多 6 个宇宙；权重低于 8% 不再分裂。")))
	return card


func _build_tip_card() -> PanelContainer:
	var card := UI.card(true)
	var column := UI.vbox(UI.GAP_XS)
	card.add_child(column)
	column.add_child(UI.dim("换算小提示"))
	column.add_child(UI.muted(tr("分数是加权目数：在 50% 的宇宙里多围 2 目，相当于全局多 1 目。"), true))
	return card
