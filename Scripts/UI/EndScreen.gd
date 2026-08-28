extends VBoxContainer
class_name EndScreen


## Issue 552: the post-fight roster. One card per party pawn with its portrait,
## what it dealt and what it took, sortable, and the whole log beside it.
##
## A component inside `BattleView`'s end banner rather than a screen of its own,
## because the banner already solves issue 343: its dim is a sibling at the
## front of Hud's child order, and it takes no input itself.

## Every number here is derived from `CombatState.events` and the simulation was
## not touched to produce any of it. `Scripts/UI` is outside the sim
## fingerprint's source set, which is what makes that structural rather than a
## promise.

const GlossaryIconScript := preload("res://Scripts/UI/GlossaryIcon.gd")

const SortBy := {DEALT = 0, TAKEN = 1, HEALED = 2}

## Four cards and their separators have to fit the roster's share of the width
## without scrolling: a four-pawn party is the normal case, and a roster you
## have to drag to see all of is not a roster.
const CARD_WIDTH := 148.0
const PORTRAIT_SIZE := 56.0

## Wide enough for a four-pawn party laid out side by side. The banner's column
## is centred and sizes to content, so without a floor here the roster gets
## whatever is left over -- which was two and a bit cards behind a scrollbar.
## Each card is `CARD_WIDTH` plus the panel's own content margin on both sides.
const CARD_SLOT := CARD_WIDTH + 2.0 * Palette.SPACE_S
const ROSTER_MIN_WIDTH := 4.0 * CARD_SLOT + 3.0 * Palette.SPACE_M

## Issue 591: a caption and one line, and it is a FLOOR rather than the height.
## The log was a fixed 104 px slab until the Healed row and a three-line casualty
## list together pushed Restart 21 px off the bottom of a 720 px window. It is
## the one part of this card that scrolls, so it is the part that gives way: it
## is the only child here that expands, and it takes whatever the rest of the
## card leaves.
const LOG_MIN_HEIGHT := 44.0

## Named so a probe and a test can find the controls without matching on caption.
const SORT_DEALT_NAME := "SortByDealt"
const SORT_TAKEN_NAME := "SortByTaken"
const SORT_HEALED_NAME := "SortByHealed"

## The column each sort reads, so a fourth number cannot be added to the card
## and left unsortable, which is what "is healing a third sort" was asking.
const SORT_KEYS := {SortBy.DEALT: "dealt", SortBy.TAKEN: "taken", SortBy.HEALED: "healed"}
const ROSTER_NAME := "Roster"
const LOG_SCROLL_NAME := "FullLogScroll"

var _sort: int = SortBy.DEALT
var _rows: Array[Dictionary] = []
var _roster: HBoxContainer = null
var _log_side: Control = null
var _log_label: RichTextLabel = null
var _sort_buttons: Dictionary = {}

# ---------------------------------------------------------------------------
# The tally. Static, so it is testable without a viewport.

## Unit id -> the id of the party pawn that owns it, for every summoned unit.
## `SUMMONED` carries the caster as `source_id` and the new unit as `target_id`,
## so the whole ownership tree is in the stream. Resolved transitively, because
## nothing stops a summon summoning.
static func summoner_of(state: CombatState) -> Dictionary:
	var direct := {}
	for e in state.events:
		if e.kind == CG.EventKind.SUMMONED:
			direct[e.target_id] = e.source_id
	var out := {}
	for id in direct:
		var owner: int = direct[id]
		var guard := 0
		while direct.has(owner) and guard < 16:
			owner = direct[owner]
			guard += 1
		out[id] = owner
	return out

## One row per party pawn: what it dealt, what it took, what it healed, what its
## summons dealt on its behalf, and when it died.
##
## **Dealt never credits `source_id` -1**, which is terrain and belongs to
## nobody. **Taken counts everything**, terrain included, because a pawn that
## burned to death took that damage whoever lit the fire. **`amount` is what
## landed after the remaining-health clamp**, so overkill is not credited and
## the columns reconcile. **Healed follows the same rule and overhealing is
## uncredited**, because `_apply_heal` emits the health the bar moved.
static func tally(state: CombatState) -> Array[Dictionary]:
	var owner := summoner_of(state)
	var rows: Array[Dictionary] = []
	var index := {}
	for u in state.units:
		if u.team != CG.Team.PLAYER or u.pawn == null:
			continue
		index[u.id] = rows.size()
		rows.append({
			"unit_id": u.id,
			"pawn": u.pawn,
			"name": u.display_name,
			"dealt": 0,
			"taken": 0,
			"healed": 0,
			"by_summons": 0,
			"alive": u.alive,
			"died_tick": -1,
		})

	for e in state.events:
		if e.kind == CG.EventKind.DEATH:
			if index.has(e.target_id):
				rows[index[e.target_id]]["died_tick"] = e.tick
			continue
		if e.kind == CG.EventKind.HEAL:
			if e.amount > 0:
				var healer := e.source_id
				if owner.has(healer):
					healer = owner[healer]
				if index.has(healer):
					rows[index[healer]]["healed"] += e.amount
			continue
		if e.kind != CG.EventKind.DAMAGE or e.amount <= 0:
			continue
		if index.has(e.target_id):
			rows[index[e.target_id]]["taken"] += e.amount
		var credit := e.source_id
		var through_summon := false
		if owner.has(credit):
			credit = owner[credit]
			through_summon = true
		if index.has(credit):
			rows[index[credit]]["dealt"] += e.amount
			if through_summon:
				rows[index[credit]]["by_summons"] += e.amount
	return rows

## `rows` ordered by one column, highest first, ties broken by the party's own
## order so the list never shuffles under a player reading it.
static func sorted_rows(rows: Array[Dictionary], sort_by: int) -> Array[Dictionary]:
	var key: String = SORT_KEYS.get(sort_by, "dealt")
	var out := rows.duplicate()
	out.sort_custom(func(a, b):
		if int(a[key]) != int(b[key]):
			return int(a[key]) > int(b[key])
		return int(a["unit_id"]) < int(b["unit_id"]))
	return out

## Every log line the fight produced, in order, through the same formatter the
## running log uses -- so the What-to-show toggles apply here too and "the whole
## log" means every line the player's own settings produce.
static func log_lines(state: CombatState, view: CombatLogView) -> Array[String]:
	var out: Array[String] = []
	for e in state.events:
		var line := view.line_for_event(state, e)
		if line != "":
			out.append(line)
	return out

# ---------------------------------------------------------------------------

static func create() -> EndScreen:
	var screen := EndScreen.new()
	screen._build()
	return screen

## Issue 343: one full-screen node that took input killed Pause, Restart, the
## toolbar and the log all at once. Nothing structural here accepts a mouse
## event; only the buttons and the log's scroll do.
func _build() -> void:
	name = "EndScreen"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", int(Palette.SPACE_S))

	## The log sits UNDER the roster rather than beside it. Side by side the
	## card was 1092 wide and centred, which ran it under the team panel and the
	## running log in the right-hand 280 px. Stacked, the whole card is
	## `ROSTER_MIN_WIDTH` and clears both.
	add_child(_build_roster_side())
	add_child(_build_log_side())

## The sort controls sit ABOVE the roster and outside its scroll, deliberately:
## #520 is a control that took no input because it was 11 px under a
## `ScrollContainer`'s clip, and a sort you have to scroll to reach is the same
## defect waiting to happen.
func _build_roster_side() -> Control:
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.custom_minimum_size = Vector2(ROSTER_MIN_WIDTH, 0.0)
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.add_theme_constant_override("separation", int(Palette.SPACE_S))

	var sorts := HBoxContainer.new()
	sorts.add_theme_constant_override("separation", int(Palette.SPACE_S))
	sorts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.add_child(sorts)

	var caption := Label.new()
	caption.text = "Sort by"
	caption.add_theme_color_override("font_color", Palette.TEXT_DIM)
	caption.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sorts.add_child(caption)

	_sort_buttons[SortBy.DEALT] = _sort_button("Damage dealt", SORT_DEALT_NAME, SortBy.DEALT, sorts)
	_sort_buttons[SortBy.TAKEN] = _sort_button("Damage taken", SORT_TAKEN_NAME, SortBy.TAKEN, sorts)
	_sort_buttons[SortBy.HEALED] = _sort_button("Damage healed", SORT_HEALED_NAME, SortBy.HEALED, sorts)

	## The floor goes on the scroll itself, not on the column above it: a
	## minimum set on the parent is a request the parent may satisfy by other
	## means, and it did -- the scroll came out 628 wide against a 720 ask.
	## Vertical scrolling is OFF and the height comes from the cards. A fixed 200
	## was 2 px under the card it held, which raised a vertical bar that drew over
	## the last card -- and the edge check above could not see it, because the bar
	## is inside the scroll's own rect.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(ROSTER_MIN_WIDTH, 0.0)
	scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(scroll)

	_roster = HBoxContainer.new()
	_roster.name = ROSTER_NAME
	_roster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_roster.add_theme_constant_override("separation", int(Palette.SPACE_M))
	## Sized to its cards, not to the scroll. On EXPAND_FILL the box reports the
	## viewport's width whatever it holds, which made the probe's "does the
	## roster fit" check unable to fail.
	_roster.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	scroll.add_child(_roster)
	return side

func _sort_button(caption: String, node_name: String, sort_by: int, into: Node) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = caption
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(0.0, Palette.TOUCH_TARGET_MIN)
	b.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
	b.pressed.connect(func(): set_sort(sort_by))
	into.add_child(b)
	return b

func _build_log_side() -> Control:
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.custom_minimum_size = Vector2(ROSTER_MIN_WIDTH, LOG_MIN_HEIGHT)
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.add_theme_constant_override("separation", int(Palette.SPACE_S))
	_log_side = side

	var caption := Label.new()
	caption.text = "The whole fight"
	caption.add_theme_color_override("font_color", Palette.TEXT_DIM)
	caption.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.add_child(caption)

	var scroll := ScrollContainer.new()
	scroll.name = LOG_SCROLL_NAME
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(scroll)

	## A RichTextLabel with BBCode on, because `line_for_event` returns BBCode --
	## a plain Label prints "[color=9a94aaff]The fight begins.[/color]" at the
	## player, which is what the first screenshot of this screen showed.
	_log_label = RichTextLabel.new()
	_log_label.bbcode_enabled = true
	_log_label.fit_content = true
	_log_label.scroll_active = false
	_log_label.add_theme_color_override("default_color", Palette.TEXT)
	_log_label.add_theme_font_size_override("normal_font_size", Palette.FONT_SIZE_SMALL)
	_log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	## A `RichTextLabel` defaults to taking the mouse, and it is the one node in
	## the banner big enough for that to cover the toolbar under it.
	_log_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(_log_label)
	return side

## Issue 737, the player's ruling: a balance number nobody but a designer can
## see is the pawn-behaviour rule aimed at numbers instead of decisions. Same
## `DamageLedger.build` the headless `Tools/DamageLedgerReport.gd` calls, so
## the screen and the sweep can never disagree about what a fight did. One
## line, prepended into the existing log's own scroll (`open()` below) rather
## than a new fixed section -- issue 591 already spent this card's vertical
## budget once, and a second fixed slab pushed Restart under the log again.
static func _top_two(l: DamageLedger.Ledger, team: int) -> String:
	var rows := DamageLedger.top_sources(l, team, 2)
	if rows.is_empty():
		return "nothing"
	var parts: Array[String] = []
	for row in rows:
		parts.append("%s (%d)" % [row.name, row.total])
	return ", ".join(parts)

## The three questions the player asked for: what my pawns did, what hurt me,
## and whether my armour is doing anything. `top_sources` mixes ability casts
## and DoT ticks, highest total first, so the busiest cause wins regardless of
## which of the two damage paths it travelled.
static func ledger_text(state: CombatState) -> String:
	var l := DamageLedger.build(state)
	var m := DamageLedger.mitigation_summary(l, CG.Team.PLAYER)
	var armor := "no direct hits landed on you"
	if not m.is_empty() and m.before > 0:
		armor = "stopped %d%%" % int(round(100.0 * (m.before - m.after) / m.before))
	return "Dealt most: %s.  Hurt you most: %s.  Your armour %s." % \
		[_top_two(l, CG.Team.PLAYER), _top_two(l, CG.Team.ENEMY), armor]

# ---------------------------------------------------------------------------

## Fills the roster and the log from a finished fight. The ledger line goes
## in as the log's own first entries, bold so it reads as a summary rather
## than another line of the fight.
func open(state: CombatState, log_view: CombatLogView) -> void:
	_rows = tally(state)
	var lines: Array[String] = ["[b]%s[/b]" % ledger_text(state), ""]
	lines.append_array(log_lines(state, log_view))
	_log_label.text = "\n".join(lines)
	_refresh()

func set_sort(sort_by: int) -> void:
	_sort = sort_by
	_refresh()

func sort_by() -> int:
	return _sort

## The rows as they are drawn right now, so a test can read the order the screen
## is actually showing rather than re-deriving it.
func shown_rows() -> Array[Dictionary]:
	return sorted_rows(_rows, _sort)

func _refresh() -> void:
	for key in _sort_buttons:
		var b: Button = _sort_buttons[key]
		b.button_pressed = key == _sort
		b.add_theme_color_override("font_color", Palette.TEXT if key == _sort else Palette.TEXT_DIM)
	for child in _roster.get_children():
		child.queue_free()
		_roster.remove_child(child)
	for row in shown_rows():
		_roster.add_child(_card(row))

func _card(row: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Palette.HP_BACK
	style.border_color = Palette.TEAM_PLAYER if bool(row["alive"]) else Palette.TEAM_ENEMY
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(Palette.SPACE_S)
	panel.add_theme_stylebox_override("panel", style)

	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(CARD_WIDTH, 0.0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", int(Palette.SPACE_XS))
	panel.add_child(column)

	column.add_child(_portrait(row))

	var name_label := Label.new()
	name_label.text = String(row["name"])
	name_label.add_theme_color_override("font_color", Palette.TEXT)
	name_label.add_theme_font_size_override("font_size", Palette.FONT_SIZE_BODY)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(name_label)

	column.add_child(_stat("Dealt", _dealt_text(row), Palette.HP_FULL))
	column.add_child(_stat("Taken", str(int(row["taken"])), Palette.HP_LOW))
	## Printed on every card, including the nine tenths of them that read 0. A
	## row that appears only when it is non-zero makes two cards different
	## heights, and the card the player is comparing against is the one missing
	## the line.
	column.add_child(_stat("Healed", str(int(row["healed"])), Palette.TEAM_PLAYER))
	column.add_child(_stat("", _fate_text(row), Palette.TEXT_DIM))
	return panel

## The portrait is a baked PNG. A class with no file gets the black square the
## project asks for rather than a drawn stand-in.
##
## Issue 591: it is also the card's mouseover. A class glyph the player cannot
## ask about is the half of #590's rule this screen was missing, and the
## sentence comes from `Glossary` and the pawn's gear rather than from a blurb
## written beside it.
func _portrait(row: Dictionary) -> Control:
	var pawn: PawnData = row["pawn"]
	var shape: StringName = pawn.pawn_class.id if pawn.pawn_class != null else &""
	var box := Portrait.new()
	box.shape = shape
	box.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	if not bool(row["alive"]):
		box.modulate = Color(1.0, 1.0, 1.0, 0.45)
	return _hoverable(box, row)

## One pawn's body at portrait size. Drawn through `Silhouettes.draw_unit` rather
## than shown as a texture, because a unit is a stack of part sprites and there is
## no one composed image of it to hand a `TextureRect`.
class Portrait extends Control:
	var shape: StringName = &""

	func _draw() -> void:
		var radius := minf(size.x, size.y) * 0.5
		Silhouettes.draw_unit(self, shape, radius, CG.Team.PLAYER,
			CG.DamageType.PHYSICAL, false, size * 0.5)

## The class in words and what this pawn was wearing when it fought, derived
## both times: `Glossary` owns the first and `EquipPanel.item_effect_text` owns
## the second, so a new item or a new tag is described here without anyone
## touching this file.
static func portrait_hover_text(pawn: PawnData) -> String:
	var lines: Array[String] = []
	if pawn.pawn_class != null:
		var cls := pawn.pawn_class
		lines.append(Glossary.class_tags_text(cls.role_primary, cls.style, cls.method))
	var worn: Array = pawn.equipment()
	if worn.is_empty():
		lines.append("Wore nothing.")
	else:
		for item in worn:
			lines.append("%s: %s" % [item.display_name, EquipPanel.item_effect_text(item)])
	return "

".join(lines)

func _hoverable(node: Control, row: Dictionary) -> Control:
	node.set_script(GlossaryIconScript)
	node._ready()
	node.pin_title = String(row["name"])
	node.tooltip_text = portrait_hover_text(row["pawn"])
	return node

func _stat(caption: String, value: String, color: Color) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var left := Label.new()
	left.text = caption
	left.add_theme_color_override("font_color", Palette.TEXT_DIM)
	left.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(left)
	var right := Label.new()
	right.text = value
	right.add_theme_color_override("font_color", color)
	right.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(right)
	return row

## A summoner's own total, with its summons' share named rather than absorbed
## silently -- a Siege Master reading zero would be wrong, and reading its
## engines' output without saying so would be wrong differently.
static func _dealt_text(row: Dictionary) -> String:
	var by_summons := int(row["by_summons"])
	if by_summons <= 0:
		return str(int(row["dealt"]))
	return "%d (%d by summons)" % [int(row["dealt"]), by_summons]

static func _fate_text(row: Dictionary) -> String:
	if bool(row["alive"]):
		return "Survived"
	if int(row["died_tick"]) < 0:
		return "Died"
	return "Died at %.1fs" % (float(int(row["died_tick"])) / float(CG.TICKS_PER_SECOND))
