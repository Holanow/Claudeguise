extends PanelContainer
class_name UnitCard


## Issue 377: what the game already knows about one unit, reachable from the
## unit itself. It costs no screen space until a player clicks something.

const FOCUS_SET := "Focus fire"
const FOCUS_CLEAR := "Stop focusing"

signal closed
signal plans_requested

## Issue 588: the player asked for this enemy to be focused, or for the focus to
## be dropped. The view owns `CombatState`; this card only asks.
signal focus_toggled(unit_id: int)

## Wide enough for a status sentence at two or three lines, narrow enough that
## it is a panel beside the fight rather than a takeover of it.
const MAX_WIDTH := 320.0

## How tall the body may grow before it scrolls instead. A card long enough to
## reach the toolbar is the #343 failure -- a panel eating the controls -- put
## back by hand.
const MAX_BODY_HEIGHT := 380.0

## The floor under that, for a window too short to give the card its share:
## about four lines, which is enough to show that scrolling is the answer.
const MIN_BODY_HEIGHT := 160.0

## Issue 396. What the card's own chrome costs above and below the scrolling
## body: the title, the side line, the button row, three separations and the
## panel's top and bottom margins.
const CHROME_HEIGHT := 2.0 * Palette.SPACE_M + 3.0 * Palette.SPACE_XS + Palette.TOUCH_TARGET_MIN + 46.0

## How tall the body may grow, set by whoever knows how much screen is free
## below the toolbar. Left at MAX_BODY_HEIGHT until it is told otherwise.
var body_ceiling: float = MAX_BODY_HEIGHT

var unit_id: int = -1

var _title: Label = null
var _side: Label = null
var _body: Label = null
var _scroll: ScrollContainer = null
var _plans_button: Button = null
var _focus_button: Button = null

static func create() -> UnitCard:
	var card := UnitCard.new()
	card._build()
	return card

func _build() -> void:
	add_theme_stylebox_override("panel", _style())
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	custom_minimum_size = Vector2(MAX_WIDTH, 0.0)
	visible = false

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", int(Palette.SPACE_XS))
	add_child(column)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", Palette.FONT_SIZE_BODY)
	_title.add_theme_color_override("font_color", Palette.INK)
	column.add_child(_title)

	_side = Label.new()
	_side.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
	_side.add_theme_color_override("font_color", Palette.INK_DIM)
	column.add_child(_side)

	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(MAX_WIDTH - Palette.SPACE_M * 2.0, 0.0)
	_body.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
	_body.add_theme_color_override("font_color", Palette.INK)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.add_child(_body)
	## The body sits inside a ScrollContainer, which reserves the width of its
	## vertical scrollbar. Without this the card is that much wider than
	## MAX_WIDTH, which is meant to be the whole card.
	_body.custom_minimum_size.x -= _scroll.get_v_scroll_bar().get_combined_minimum_size().x
	column.add_child(_scroll)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", int(Palette.SPACE_S))
	column.add_child(buttons)

	_plans_button = Button.new()
	_plans_button.text = "Plans & Equipment"
	_plans_button.custom_minimum_size = Vector2(0.0, Palette.TOUCH_TARGET_MIN)
	_plans_button.pressed.connect(func(): plans_requested.emit())
	buttons.add_child(_plans_button)

	_focus_button = Button.new()
	_focus_button.custom_minimum_size = Vector2(0.0, Palette.TOUCH_TARGET_MIN)
	_focus_button.pressed.connect(func(): focus_toggled.emit(unit_id))
	buttons.add_child(_focus_button)

	var close_button := Button.new()
	close_button.text = "Close"
	close_button.custom_minimum_size = Vector2(0.0, Palette.TOUCH_TARGET_MIN)
	close_button.pressed.connect(close)
	buttons.add_child(close_button)

static func _style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(Palette.PAPER_LEAF, 0.94)
	style.border_color = Palette.INK_DIM
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_content_margin(side, Palette.SPACE_M)
	return style

func show_unit(state: CombatState, u: CombatUnit) -> void:
	unit_id = u.id
	visible = true
	_fill(state, u)

## Re-read at the tick the caller is on. A card showing a frozen answer while
## the fight moves is the stale-comment failure wearing a panel.
func refresh(state: CombatState) -> void:
	if not visible or state == null:
		return
	var u := state.unit(unit_id)
	if u == null or not u.alive:
		close()
		return
	_fill(state, u)

func _fill(state: CombatState, u: CombatUnit) -> void:
	_title.text = title_text(u)
	_side.text = side_text(u)
	_body.text = "\n".join(lines(state, u))
	_scroll.custom_minimum_size.y = body_height(_body.get_combined_minimum_size().y, body_ceiling,
		float(_body.get_line_height()))
	_plans_button.visible = u.pawn != null
	## Only an enemy can be focused, and the word says which way pressing it
	## goes rather than naming the state it is already in.
	_focus_button.visible = u.pawn == null and u.team == CG.Team.ENEMY
	_focus_button.text = FOCUS_CLEAR if state.player_focus_id == u.id else FOCUS_SET

## Issue 396: `Shielding (5.0s left): Stops an` was cut by the card's bottom
## edge, because the cap was a round number of pixels and landed in the middle
## of a glyph. Snapped down to a whole number of lines instead, so what the
## card shows is always a line the player can finish reading.
static func body_height(wanted: float, ceiling: float, line: float) -> float:
	if line <= 0.0:
		return minf(wanted, ceiling)
	return minf(wanted, maxf(floorf(ceiling / line), 1.0) * line)

func close() -> void:
	dismiss()
	closed.emit()

## Off the screen, but without the `closed` side effects: the caller is taking
## over what the card was holding rather than handing it back.
func dismiss() -> void:
	visible = false
	unit_id = -1

## ---------------------------------------------------------------------------
## What it says. Static and string-only, so every sentence below can be checked
## without a canvas.

static func title_text(u: CombatUnit) -> String:
	return "%s  ·  %d of %d hp" % [u.display_name, maxi(u.hp, 0), u.hp_max]

static func side_text(u: CombatUnit) -> String:
	if u.team != CG.Team.PLAYER:
		return "Enemy"
	return "Your party" if u.pawn != null else "Your summon"

static func _seconds(ticks: int) -> String:
	return "%.1fs" % (float(maxi(ticks, 0)) / float(CG.TICKS_PER_SECOND))

static func resource_name(kind: CG.ResourceKind) -> String:
	return String(CG.ResourceKind.keys()[kind]).capitalize()

## The resource in words, with both numbers and what running dry costs.
static func resource_line(u: CombatUnit) -> String:
	if u.resource_max <= 0:
		return "No resource: nothing it does costs one."
	var named := resource_name(u.resource_kind)
	var numbers := "%s %d of %d." % [named, u.resource, u.resource_max]
	if u.resource <= 0:
		return "%s It is out, so anything costing %s cannot fire." % [numbers, named.to_lower()]
	return numbers

static func doing_line(state: CombatState, u: CombatUnit) -> String:
	if u.has_status(CG.Status.STUN):
		return "Stunned: it cannot act at all until that wears off."
	if u.sustaining != &"":
		return "Holding %s open, paying its cost every tick." % action_name(u.sustaining)
	if u.current_action != &"" and u.action_ticks_left > 0:
		return "Winding up %s, %s to go." % [action_name(u.current_action), _seconds(u.action_ticks_left)]
	if u.recover_ticks_left > 0:
		return "Recovering from its last action, %s to go." % _seconds(u.recover_ticks_left)
	if u.resource_max > 0 and u.resource <= 0:
		return "Doing nothing: it cannot pay for anything it knows."
	return "Moving, or waiting for its next action to come up."

static func action_name(id: StringName) -> String:
	var action = ActionLibrary.get_action(id)
	return action.display_name if action != null and action.display_name != "" else String(id)

## The circled number over the Rat King and the Warden, in words.
static func focus_lines(state: CombatState, u: CombatUnit) -> Array[String]:
	var out: Array[String] = []
	var target := state.unit(u.focus_id) if u.focus_id >= 0 else null
	if u.focus_id == u.id:
		## Legitimate: `PlanInterpreter.action_target_id` aims a targets_self
		## action at the caster, and CombatSim writes that into focus_id.
		out.append("Acting on itself.")
	elif target != null and target.alive:
		out.append("Aiming at %s." % target.display_name)
	var incoming := UnitView.concentration_count(u, state.units)
	if incoming > 0:
		out.append("%d unit%s aiming at it." % [incoming, " is" if incoming == 1 else "s are"])
	return out

## Every status, not the two the badge row has space for.
static func status_lines(state: CombatState, u: CombatUnit) -> Array[String]:
	var out: Array[String] = []
	for s in UnitView.ordered_statuses(u):
		var parts: Array[String] = []
		var magnitude := Glossary.status_magnitude_text(s, int(u.status_magnitude.get(s, 0.0)))
		if magnitude != "":
			parts.append(magnitude)
		parts.append("%s left" % _seconds(int(u.statuses[s]) - state.tick))
		out.append("%s (%s): %s" % [Glossary.status_name(s), ", ".join(parts), Glossary.status_text(s)])
	return out

static func cooldown_lines(state: CombatState, u: CombatUnit) -> Array[String]:
	var out: Array[String] = []
	for entry in TeamStatusView.cooldowns_for(state, u):
		out.append("%s: %s until it can fire again." % [
			action_name(entry["action_id"]), _seconds(int(entry["ticks_left"]))])
	return out

static func lines(state: CombatState, u: CombatUnit) -> Array[String]:
	var out: Array[String] = [resource_line(u), doing_line(state, u)]
	out.append_array(focus_lines(state, u))
	out.append_array(status_lines(state, u))
	out.append_array(cooldown_lines(state, u))
	return out
