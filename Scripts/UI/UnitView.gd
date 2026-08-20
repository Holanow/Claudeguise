extends Node2D
class_name UnitView


## One combatant on screen: body, health bar, resource bar, name, tags, and the
## wind-up indicator that says an action is coming.

## Scaled for CombatUnit.radius's phone-legibility pass (12.0 -> 22.0) and
## Palette.FONT_SIZE_SMALL going 11 -> 16 alongside it.
const BAR_WIDTH := 60.0
const BAR_HEIGHT := 7.0
const BAR_GAP := 3.0

## The bar is tied to the drawn body, not to a fixed width. At
## `BAR_WIDTH * DISPLAY_SCALE` every unit got 90 while a goblin is 33 across,
## and a bar three times the width of its body reads as a floating object
## rather than as that body's health.
const MIN_BAR_WIDTH := 20.0

## Everything a unit wears -- bar width, the bar stack's anchor, the badge row
## -- measures from the **drawn** body, not from `CombatUnit.radius`.
static var _extents := {}
const _EXTENT_REFERENCE_RADIUS := 100.0

static func drawn_box(shape_id: StringName, team: CG.Team, radius: float) -> Rect2:
	var key := "%s|%d" % [shape_id, int(team)]
	if not _extents.has(key):
		_extents[key] = Silhouettes.drawn_extent(shape_id, _EXTENT_REFERENCE_RADIUS, team)
	var box: Rect2 = _extents[key]
	var scale := radius / _EXTENT_REFERENCE_RADIUS
	return Rect2(box.position * scale, box.size * scale)

## Half the drawn body's width in pixels. Falls back to the footprint when a
## shape measures empty, so an unknown id keeps the decoration it always had.
static func drawn_half_width(shape_id: StringName, team: CG.Team, radius: float) -> float:
	var box := drawn_box(shape_id, team, radius)
	return radius if box.size.x <= 0.0 else box.size.x * 0.5

## How far above centre the drawn body actually reaches. Read off the box's top
## edge rather than assumed symmetric: art that sits low in its canvas has a top
## edge nowhere near `-radius`, which is the `siege_master` case.
static func drawn_top(shape_id: StringName, team: CG.Team, radius: float) -> float:
	var box := drawn_box(shape_id, team, radius)
	return radius if box.size.y <= 0.0 else absf(box.position.y)

static func drawn_bottom(shape_id: StringName, team: CG.Team, radius: float) -> float:
	var box := drawn_box(shape_id, team, radius)
	return radius if box.size.y <= 0.0 else box.end.y

## Sized to the drawn body, floored so a bar stays a bar. The floor is small
## because the point of the issue is that a bar much wider than its creature
## reads as the main object.
static func bar_width(radius: float, shape_id: StringName = &"", team: CG.Team = CG.Team.PLAYER) -> float:
	var body := radius * 2.0 if shape_id == &"" else drawn_half_width(shape_id, team, radius) * 2.0
	return clampf(body, MIN_BAR_WIDTH, BAR_WIDTH * DISPLAY_SCALE)

## A view-only scale, deliberately not a change to `CombatUnit.radius`:
const DISPLAY_SCALE := 1.5

static func display_radius(u: CombatUnit) -> float:
	return u.radius * DISPLAY_SCALE

var unit_id: int = -1
var _state: CombatState = null

## `should_show_label`'s trigger, plus a hold: once true, stays true for
## LABEL_HOLD_TICKS more, so the name does not blink out the instant the
## trigger flickers. An attacker refocuses or finishes winding up several
## times a second, which is what made the name blink.
const LABEL_HOLD_TICKS := int(CG.TICKS_PER_SECOND * 1.5)
var _label_last_active_tick: int = -1000000000
## Also holds the name up when a unit's own hp or resource just changed --
## "some enemies never get names" was every unit that neither focuses nor
## winds up while a plan-driven pawn's default behaviour attacks it (a
## fodder unit standing in melee range gets hit without ever being the one
## "mid wind-up" itself). UnitView deliberately reads CombatUnit only, never
## CombatEvent (see file header), so this is read off the unit's own state
## rather than consuming the event stream BattleView already owns.
var _last_seen_hp: int = -1
var _last_seen_resource: int = -1

func bind(state: CombatState, id: int) -> void:
	unit_id = id
	sync(state)

func sync(state: CombatState) -> void:
	_state = state
	var u := _unit()
	if u == null:
		return
	if _last_seen_hp != -1 and (u.hp != _last_seen_hp or u.resource != _last_seen_resource):
		_label_last_active_tick = state.tick
	_last_seen_hp = u.hp
	_last_seen_resource = u.resource
	position = u.position + visual_offset(u, state.units)
	visible = u.alive
	queue_redraw()

## should_show_label's immediate trigger, plus a hold: once true, stays true
## for LABEL_HOLD_TICKS more so the name does not blink out the instant the
## trigger condition itself flickers.
func _label_visible(u: CombatUnit) -> bool:
	if should_show_label(u, _state.units):
		_label_last_active_tick = _state.tick
		return true
	return _state.tick - _label_last_active_tick <= LABEL_HOLD_TICKS

## The melee scrum: bodies standing close enough to occlude each other. A
## view-only nudge, never fed back into CombatState -- this changes nothing
## about range, targeting or movement, only where a body is drawn.
const _SEPARATION_PADDING := 1.3
const _SEPARATION_STRENGTH := 0.5

## Uses display_radius, not u.radius: the whole point of this nudge is to
## keep now-larger bodies from occluding each other, so it has to reason
## about the size actually drawn, not the smaller collision footprint the
## simulation moves around.
static func visual_offset(u: CombatUnit, units: Array) -> Vector2:
	var push := Vector2.ZERO
	var u_radius := display_radius(u)
	for other in units:
		if other.id == u.id or not other.alive:
			continue
		var delta: Vector2 = u.position - other.position
		var dist: float = delta.length()
		var min_dist: float = (u_radius + display_radius(other)) * _SEPARATION_PADDING
		if dist >= min_dist:
			continue
		if dist > 0.001:
			push += delta.normalized() * (min_dist - dist) * _SEPARATION_STRENGTH
		else:
			# Exactly coincident: distance has no direction to push along.
			var angle := float(u.id) * 2.4
			push += Vector2(cos(angle), sin(angle)) * min_dist * _SEPARATION_STRENGTH
	return push.limit_length(u_radius * 1.5)

## Which way the body is drawn, from `CombatUnit.facing` -- the same quantity
## `_shot_is_blocked` reads to decide whether the Warrior's guard stops a shot,
## so drawing anything else decides an outcome on a fact it refuses to show.
static func facing_left(u: CombatUnit) -> bool:
	if u.facing.x != 0.0:
		return u.facing.x < 0.0
	return u.team == CG.Team.ENEMY

func _unit() -> CombatUnit:
	if _state == null:
		return null
	return _state.unit(unit_id)

## Class id for a pawn, enemy id for an enemy. Silhouettes.draw_unit falls
## back to a hollow diamond for any id it does not know, so this is safe to
## call before teal's content registers real classes or enemies.
func _shape_id(u: CombatUnit) -> StringName:
	if u.pawn != null and u.pawn.pawn_class != null:
		return u.pawn.pawn_class.id
	return u.enemy_id

## The class's first damage type colours its accent shapes. Enemies have no
## class to read one from, so they fall back to physical until there is a
## reason to look one up on EnemyDef instead.
func _accent(u: CombatUnit) -> int:
	if u.pawn != null and u.pawn.pawn_class != null and not u.pawn.pawn_class.damage_types.is_empty():
		return u.pawn.pawn_class.damage_types[0]
	return CG.DamageType.PHYSICAL

func _draw() -> void:
	var u := _unit()
	if u == null:
		return

	var radius := display_radius(u)

	_draw_targeting_line(u)

	Silhouettes.draw_unit(self, _shape_id(u), radius, u.team, _accent(u), facing_left(u))

	_draw_concentration_badge(u, radius)

	var body_bottom := drawn_bottom(_shape_id(u), u.team, radius)
	var below := _draw_wind_up(u, radius, body_bottom)
	below += _draw_status_badges(u, radius, body_bottom, below)
	_draw_status_tags(u, body_bottom, below)

	var width := bar_width(radius, _shape_id(u), u.team)
	var bar_height := BAR_HEIGHT * DISPLAY_SCALE
	var bar_gap := BAR_GAP * DISPLAY_SCALE
	var y := -drawn_top(_shape_id(u), u.team, radius) - bar_gap
	var stack_bottom := y

	if u.resource_max > 0:
		y -= bar_height
		var res_pos := Vector2(-width * 0.5, y)
		var res_fraction := float(u.resource) / float(u.resource_max)
		draw_rect(Rect2(res_pos, Vector2(width, bar_height)), Palette.HP_BACK)
		draw_rect(Rect2(res_pos, Vector2(width * res_fraction, bar_height)), Palette.resource_color(u.resource_kind))
		y -= bar_gap

	y -= bar_height
	var hp_pos := Vector2(-width * 0.5, y)
	draw_rect(Rect2(hp_pos, Vector2(width, bar_height)), Palette.HP_BACK)
	draw_rect(Rect2(hp_pos, Vector2(width * u.hp_fraction(), bar_height)), hp_fill_color(u))
	_draw_bar_tether(u, stack_bottom)
	y -= bar_gap + _label_font_size() + _crowding_stagger(u)

	if DisplayOptions.enabled(&"name_plates") and _label_visible(u):
		_draw_label_chip(u.display_name, y, Palette.TEXT, _label_font_size())

## Issue 187, and TWO independent cold readers reported it before it was filed:
const TETHER_WIDTH := 1.0 * DISPLAY_SCALE
const TETHER_ALPHA := 0.55

func _draw_bar_tether(u: CombatUnit, stack_bottom: float) -> void:
	var color := Palette.team_color(u.team)
	color.a = TETHER_ALPHA
	draw_line(Vector2(0.0, stack_bottom), Vector2.ZERO, color, TETHER_WIDTH)

## Issue 82, and the finding that forced it: **`Palette.HP_LOW` and
## `Palette.TEAM_ENEMY` are the same colour, `e0705f`.** So every unit's bar ran
## the same red-to-green ramp regardless of side, a hurt party pawn was drawn in
## the enemy's own colour, and a fresh reader reported the field as "green
## dashes" that never answered *am I ahead* -- the first question a spectator
## has.
static func hp_fill_color(u: CombatUnit) -> Color:
	var team := Palette.team_color(u.team)
	# Floored well above zero so a nearly-dead unit is still legibly its own
	# side rather than fading into the trough it sits in.
	return Palette.HP_BACK.lerp(team, clampf(0.45 + u.hp_fraction() * 0.55, 0.0, 1.0))

## Palette.FONT_SIZE_SMALL is shared with screens that have nothing to do
## with the arena (InspectPanel's attribute chips, PartySelect), so it is
## not something this file can change -- scaled locally instead, the same
## reasoning DISPLAY_SCALE itself exists for.
static func _label_font_size() -> int:
	return int(round(Palette.FONT_SIZE_SMALL * DISPLAY_SCALE))

## Both world-space-ish quantities that grew a real bigger footprint needs to
## respect: a bigger body and taller bar/label stack means two units that
## used to read as merely "nearby" now have their chrome actually touch at
## the same world distance. Found by comparing a real before/after screenshot
## of floor1_room1, not by reasoning about it -- the first version of issue 31
## left these fixed and rows of enemies spaced for the old, smaller footprint
## overlapped their neighbours' labels.
const CROWD_RADIUS := 70.0 * DISPLAY_SCALE
const CROWD_STEP := 20.0 * DISPLAY_SCALE

## Extra headroom for this unit's name label when another unit is standing
## close enough for the two labels to land on the same spot -- found in
## Tools/preview/fight_sheet.png, where "abomination" and "Grunt" overlapped
## illegibly the moment two units clashed in melee, which is exactly the
## moment reading who is who matters most. Deterministic by id (lower id
## never moves, each higher id crowded into the same spot stacks one step
## higher) rather than by draw order, so two views of the same fight agree
## on where a label lands.
func _crowding_stagger(u: CombatUnit) -> float:
	if _state == null:
		return 0.0
	# CROWD_STEP already carries DISPLAY_SCALE -- do not multiply twice.
	return float(crowd_rank(u, _state.units)) * CROWD_STEP

## Issue 41: a dense room (floor1_room1, 10 enemies) piled every enemy's name
## into the top-middle of the screen at once, and no amount of vertical
## stagger reads as separate names once four labels share the same few rows
## -- see Screenshots/label_crowd_before_1280x720.png. Raising DISPLAY_SCALE
## further (2.0x, tried in issue 31) made it worse, not better: this is a
## count problem, not a spacing constant to retune again.
static func should_show_label(u: CombatUnit, units: Array) -> bool:
	if u.team == CG.Team.PLAYER:
		return true
	if concentration_count(u, units) > 0:
		return true
	return u.action_ticks_left > 0 and u.current_action != &""

## Split out for testing, same reasoning as status_tags: how many other
## living units with a lower id are within CROWD_RADIUS of this one.
static func crowd_rank(u: CombatUnit, units: Array) -> int:
	var rank := 0
	for other in units:
		if other.id == u.id or not other.alive:
			continue
		if other.id < u.id and u.position.distance_to(other.position) < CROWD_RADIUS:
			rank += 1
	return rank

## Who is this unit currently after. Answers "why is that side winning" by
## itself, before a single number changes: a target being focused by three
## units at once reads differently from one being ignored.
func _draw_targeting_line(u: CombatUnit) -> void:
	if u.focus_id < 0 or u.current_action == &"":
		return
	if _has_active_projectile(u):
		return
	var target := _state.unit(u.focus_id)
	if target == null or not target.alive:
		return
	var to_target := target.position - u.position
	draw_line(Vector2.ZERO, to_target, Color(Palette.BACKGROUND, 0.5), 4.5)
	draw_line(Vector2.ZERO, to_target, Palette.FOCUS_LINE, 2.5)

func _has_active_projectile(u: CombatUnit) -> bool:
	if _state == null:
		return false
	for p in _state.projectiles:
		if p.source_id == u.id and not p.resolved:
			return true
	return false

## How many other living units currently have this one as their focus --
## "is this unit under fire from more than one thing at once", which issue 15
## found was completely invisible: a scrum of three attackers on one pawn
## looked identical to three attackers merely standing near it. Split out for
## testing without a live canvas, same reasoning as status_tags.
static func concentration_count(u: CombatUnit, units: Array) -> int:
	var count := 0
	for other in units:
		if other.id == u.id or not other.alive:
			continue
		if other.focus_id == u.id:
			count += 1
	return count

const CONCENTRATION_THRESHOLD := 2

## Issue 198: 8, not 11, and drawn as an arc rather than a filled disc.
const CONCENTRATION_BADGE_RADIUS := 8.0 * DISPLAY_SCALE
const CONCENTRATION_BADGE_WIDTH := 2.0

## Only drawn once concentration is actually worth flagging (2+): a badge on
## every unit all the time would be noise, and the issue this answers is
## specifically "three attackers on one pawn read as nothing at all", not
## "who has a target".
func _draw_concentration_badge(u: CombatUnit, radius: float) -> void:
	if _state == null:
		return
	var count := concentration_count(u, _state.units)
	if count < CONCENTRATION_THRESHOLD:
		return
	var shape := _shape_id(u)
	var half := drawn_half_width(shape, u.team, radius)
	var badge_radius := clampf(half * 0.45, 5.0 * DISPLAY_SCALE, CONCENTRATION_BADGE_RADIUS)
	var badge_center := Vector2(half, -drawn_top(shape, u.team, radius) + badge_radius)
	draw_arc(badge_center, badge_radius, 0.0, TAU, 20, _concentration_color(u), CONCENTRATION_BADGE_WIDTH, true)
	var font := ThemeDB.fallback_font
	var text := str(count)
	var size := int(round(Palette.FONT_SIZE_SMALL * DISPLAY_SCALE * 0.8))
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	draw_string(font, badge_center - text_size * 0.5 + Vector2(0.0, text_size.y * 0.75),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Palette.TEXT)

## The team of whoever is focusing this unit. Read off the real focusers rather
## than assumed to be the opposite team, so a badge never claims a side that is
## not actually attacking.
func _concentration_color(u: CombatUnit) -> Color:
	for other in _state.units:
		if other.id != u.id and other.alive and other.focus_id == u.id:
			return Palette.team_color(other.team)
	return Palette.TEXT_DIM

## PLAYTEST-NOTES-2 item 3: "countdowns should be progress bars, with an icon
## at the end showing what is coming", and the note's own reading of it --
## "the icon is the better half: a ring says something is coming, an icon says
## what."
const WIND_UP_ICON_SIZE := 16.0 * DISPLAY_SCALE
const WIND_UP_TOP_GAP := 4.0 * DISPLAY_SCALE
const WIND_UP_ICON_GAP := 3.0 * DISPLAY_SCALE

## Takes a radius since issue 82: the whole block is still exactly as wide as
## the hp bar above it, but that width now depends on the body.
static func wind_up_icon_size(radius: float, shape_id: StringName = &"", team: CG.Team = CG.Team.PLAYER) -> float:
	return clampf(bar_width(radius, shape_id, team) * 0.34, 7.0 * DISPLAY_SCALE, WIND_UP_ICON_SIZE)

static func wind_up_bar_width(radius: float, shape_id: StringName = &"", team: CG.Team = CG.Team.PLAYER) -> float:
	return bar_width(radius, shape_id, team) - wind_up_icon_size(radius, shape_id, team) - WIND_UP_ICON_GAP

## How full the bar is, 0..1. Its own function so it can be checked without a
## canvas, same split as wind_up_elapsed_ticks. A total of 0 means the action
## has no wind-up at all and fires the tick it commits: full, not empty, since
## nothing is being waited for.
static func wind_up_fraction(u: CombatUnit) -> float:
	if u.action_ticks_total <= 0:
		return 1.0
	return clampf(float(wind_up_elapsed_ticks(u)) / float(u.action_ticks_total), 0.0, 1.0)

## The damage type the icon is coloured by. The *action's* own type, not
## `_accent(u)`'s class-level one, even though sable's own signature note
## offers `_accent` as the cheap answer. The point of the icon is that the
## player sees the thing coming and then sees the same thing land, and what
## lands is coloured by the action: `ArenaFloor._draw_projectile` (PR #71) and
## the floating number both already read `ActionDef.damage_type`. A Priest
## whose class accent is Divine also casts Physical actions, and the telegraph
## disagreeing with its own projectile is worse than one Registry lookup.
func _wind_up_damage_type(u: CombatUnit) -> int:
	var action = Registry.get_action(u.current_action)
	return action.damage_type if action != null else _accent(u)

## Returns how much vertical room it took, so whatever stacks under it can
## clear it. Zero when nothing is winding up.
func _draw_wind_up(u: CombatUnit, radius: float, top_offset: float) -> float:
	if u.action_ticks_left <= 0 or u.current_action == &"":
		return 0.0

	var shape := _shape_id(u)
	var width := wind_up_bar_width(radius, shape, u.team)
	var icon_size := wind_up_icon_size(radius, shape, u.team)
	var bar_height := BAR_HEIGHT * DISPLAY_SCALE
	var block_left := -bar_width(radius, shape, u.team) * 0.5
	var top := top_offset + WIND_UP_TOP_GAP
	var damage_type := _wind_up_damage_type(u)

	# Vertically centred on the icon, not on the bar: the icon is the taller of
	# the two and the pair has to read as one object.
	var bar_top := top + (icon_size - bar_height) * 0.5
	var bar_pos := Vector2(block_left, bar_top)
	draw_rect(Rect2(bar_pos, Vector2(width, bar_height)), Palette.HP_BACK)
	draw_rect(Rect2(bar_pos, Vector2(width * wind_up_fraction(u), bar_height)),
		Palette.damage_color(damage_type))

	ActionIcons.draw_action(self, u.current_action, damage_type,
		Rect2(Vector2(block_left + width + WIND_UP_ICON_GAP, top),
			Vector2(icon_size, icon_size)))
	return WIND_UP_TOP_GAP + icon_size

## PLAYTEST-NOTES-2 item 2: "no clear visual for who is afflicted with what."
const STATUS_BADGE_SIZE := 14.0 * DISPLAY_SCALE
const STATUS_BADGE_GAP := Palette.SPACE_XS * DISPLAY_SCALE

## Clearance from whatever is above the row -- the body, or the wind-up bar
## when the unit is mid-action. Deliberately larger than the gap between
## badges: two badges of the same unit belong together and should read as one
## row, and the row belongs to the unit rather than to the thing above it.
const STATUS_BADGE_TOP_GAP := 6.0 * DISPLAY_SCALE

## A unit can in principle carry every status at once. Two are shown.
const MAX_STATUS_BADGES := 2

## Which badges this unit gets, in draw order. Split out from the drawing for
## the same reason status_tags is: Godot refuses draw_* outside _draw(), so a
## test that can only call the drawing wrapper logs errors and asserts nothing.
static func status_badges(u: CombatUnit) -> Array:
	var all := ordered_statuses(u)
	if all.size() <= MAX_STATUS_BADGES:
		return all
	# One slot is given up to the "+N" chip, so the row still occupies at most
	# MAX_STATUS_BADGES slots and never grows wider than the unit.
	return all.slice(0, MAX_STATUS_BADGES - 1)

## Every status on the unit, in draw order, with nothing dropped. Split out so
## the overflow count is derived from the same ordering the drawn badges are --
## two independent orderings would let the "+N" disagree with what is shown.
static func ordered_statuses(u: CombatUnit) -> Array:
	var harmful: Array = []
	var beneficial: Array = []
	for s in CG.Status.values():
		if not u.has_status(s):
			continue
		if CG.is_harmful(s):
			harmful.append(s)
		else:
			beneficial.append(s)
	return harmful + beneficial

## Issue 161, sable's measurement: `MAX_STATUS_BADGES` is 4 and **a fifth status
## was dropped with nothing on screen saying so.** With bleed stacking and burn,
## five is reachable now.
static func hidden_status_count(u: CombatUnit) -> int:
	var total := ordered_statuses(u).size()
	if total <= MAX_STATUS_BADGES:
		return 0
	return total - (MAX_STATUS_BADGES - 1)

## The floor. Expressed the same way as the ceiling two constants up, so the
## two move together.
const STATUS_BADGE_MIN := 13.0 * DISPLAY_SCALE

## Issue 190: sable measured a row of four badges at 84px against a 27px goblin,
## 3.1x the unit. The row scales with the drawn body for the same reason the bar
## does -- and the gap scales with it, or three badges of 9px sit in 12px of air.
static func status_badge_size(shape_id: StringName, team: CG.Team, radius: float) -> float:
	return clampf(drawn_half_width(shape_id, team, radius) * 0.7, STATUS_BADGE_MIN, STATUS_BADGE_SIZE)

func _draw_status_badges(u: CombatUnit, radius: float, top_offset: float, below: float) -> float:
	var size := status_badge_size(_shape_id(u), u.team, radius)
	var gap := STATUS_BADGE_GAP * (size / STATUS_BADGE_SIZE)
	var badges := status_badges(u)
	var hidden := hidden_status_count(u)
	if badges.is_empty() and hidden == 0:
		return 0.0
	var slots := badges.size() + (1 if hidden > 0 else 0)
	var top := top_offset + below + STATUS_BADGE_TOP_GAP
	var width := StatusIcons.row_width(slots, size, gap)
	var rects := StatusIcons.layout_row(Vector2(-width * 0.5, top), slots, size, gap)
	for i in badges.size():
		StatusIcons.draw_status(self, badges[i], rects[i])
	if hidden > 0:
		_draw_overflow_chip(rects[slots - 1], hidden)
	return STATUS_BADGE_TOP_GAP + size

## Deliberately not a glyph. Every plate in `StatusIcons` means "this specific
## status is on this unit", and a plate meaning "there are more" would be the
## first one that is not a status -- exactly the ambiguity sable measured, where
## badges in a category already share ~84% of their pixels. Text cannot be
## mistaken for a status.
func _draw_overflow_chip(rect: Rect2, count: int) -> void:
	var font := ThemeDB.fallback_font
	var text := "+%d" % count
	var size := int(round(Palette.FONT_SIZE_SMALL * DISPLAY_SCALE))
	var measured := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var at := rect.get_center() + Vector2(-measured.x * 0.5, measured.y * 0.35)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Palette.TEXT_DIM)

## Out-of-resource looks identical to "idle" on the arena otherwise: the unit
## just doesn't do anything, and a viewer with no access to CombatUnit cannot
## tell a stalled decision from a disabled one. It is not a CG.Status, so it
## has no badge and stays text, drawn under whatever is already below the body.
func _draw_status_tags(u: CombatUnit, radius: float, below: float) -> void:
	var tags := status_tags(u)
	if tags.is_empty():
		return
	_draw_label_chip(" ".join(tags), radius + below + 14.0 * DISPLAY_SCALE, Palette.HP_LOW, _label_font_size())

## Renders text centred on its own width with a small backdrop chip behind
## it, rather than a fixed draw width that truncates. Found by rendering a
## real fight through six frames (Tools/ContactSheet.gd): "geysermancer"
func _draw_label_chip(text: String, baseline_y: float, color: Color, font_size: int) -> void:
	var font := ThemeDB.fallback_font
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pos := Vector2(-text_size.x * 0.5, baseline_y)
	var pad := Vector2(3.0, 2.0) * DISPLAY_SCALE
	var chip := Rect2(pos - Vector2(pad.x, text_size.y), text_size + pad * 2.0)
	draw_rect(chip, Color(Palette.BACKGROUND, 0.65))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

## Split out for testing, same reasoning as status_tags below: the part of
## the wind-up draw call that is pure arithmetic rather than a draw_* call.
static func wind_up_elapsed_ticks(u: CombatUnit) -> int:
	return u.action_ticks_total - u.action_ticks_left

## Split out from _draw_status_tags so it can be tested without a live canvas:
## Godot refuses draw_* calls outside _draw(), so a test that calls a drawing
## function directly logs errors and asserts nothing.
static func status_tags(u: CombatUnit) -> Array[String]:
	var tags: Array[String] = []
	if u.resource_max > 0 and u.resource <= 0:
		tags.append("OOM")
	return tags
