extends Node2D

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")
const Palette := preload("res://Scripts/Core/Palette.gd")
const Silhouettes := preload("res://Scripts/Art/Silhouettes.gd")
const AttackFX := preload("res://Scripts/Art/AttackFX.gd")
const StatusIcons := preload("res://Scripts/Art/StatusIcons.gd")

## One combatant on screen: body, health bar, resource bar, name, tags, and the
## wind-up indicator that says an action is coming.
##
## OWNER: pike.
##
## The wind-up indicator is not decoration. ActionDef.wind_up_ticks exists so a
## fight can be read rather than watched, and that only works if the screen
## shows it.
##
## Positions and bars read CombatUnit directly. Anything that *happened* (a
## death being announced, a number floating) comes from a CombatEvent instead,
## handled by BattleView and DamageFloater.

## Scaled for CombatUnit.radius's phone-legibility pass (12.0 -> 22.0) and
## Palette.FONT_SIZE_SMALL going 11 -> 16 alongside it.
const BAR_WIDTH := 60.0
const BAR_HEIGHT := 7.0
const BAR_GAP := 3.0

## Issue 31: units read too small, worse now that sable's real art carries
## detail invisible at the old size (a real rendered fight: ten units in
## roughly the middle fifth of a 1280x720 arena, sprites about twenty
## pixels across). A view-only scale, deliberately not a change to
## `CombatUnit.radius`/`EnemyDef.radius` themselves: those read as "drawing
## only" in their own doc comments, and that comment is wrong — checked
## rather than trusted, `CombatSim._move_toward` calls
## `Terrain.point_is_blocked(state.terrain, candidate, unit.radius)` for real
## movement collision. Changing the stored radius would be a balance change
## in a UI issue's clothes. Flagged to rook rather than corrected here since
## `CombatUnit.gd` is Core.
##
## Applied uniformly to everything drawn around a unit — the body, its bars,
## its labels, its badges — so a bigger silhouette does not leave suddenly-
## tiny text stranded next to it. `BattleView.gd` imports this same constant
## for the floating numbers and death markers that spawn at a unit's
## position, so the whole visual footprint of a unit grows together.
## 2.0 was tried first and measured against a real ten-enemy room
## (floor1_room1): bodies read well, but row spacing there is tuned for the
## old footprint (rows 100-140 world units apart) and doubling every bar and
## the name font on top of a doubled body pushed adjacent rows' chrome into
## each other — worse than the problem this issue exists to fix. 1.5 still
## roughly doubles the on-screen diameter after the arena's own ~0.5-0.95
## viewport scale (bigger than the raw multiplier suggests, since a bigger
## body also means a wider silhouette bounding box), while leaving enough
## headroom that CROWD_RADIUS (scaled below) can actually keep labels apart
## in a room this dense. Re-measure against a real launch before raising it
## again, not by eye against a single sprite.
const DISPLAY_SCALE := 1.5

static func display_radius(u: CombatUnit) -> float:
	return u.radius * DISPLAY_SCALE

var unit_id: int = -1
var _state: CombatState = null

## Issue 53 sweep / PLAYTEST-NOTES 20: the Goblin Archer's name flickered and
## some enemies never got one at all, both a direct consequence of
## should_show_label's trigger (focused, or mid wind-up) being a per-tick
## on/off condition with nothing to smooth it. An attacker refocuses or
## finishes winding up several times a second, so the label blinked in and
## out at the same rate. Kept as a per-instance tick, not folded into the
## static predicate: should_show_label stays a pure function other code
## (and tests) can call without a live fight, and the hysteresis is a
## rendering decision layered on top of it, the same split _draw_status_tags
## and _draw_targeting_line already use for read-only state.
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

## The melee scrum: several units standing close enough that bodies occlude
## each other, called out in issue 15 as "the most important square inch of
## the screen is the least legible one". A view-only nudge, never fed back
## into CombatState — the simulation's positions are wren's and this changes
## nothing about range, targeting or movement, only where a body is drawn.
## Each overlapping pair pushes apart along the line between them; capped so
## a crowded unit never reads somewhere misleadingly far from where it
## actually is.
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
			# Deterministic by id so two views of the same fight agree,
			# rather than depending on iteration order.
			var angle := float(u.id) * 2.4
			push += Vector2(cos(angle), sin(angle)) * min_dist * _SEPARATION_STRENGTH
	return push.limit_length(u_radius * 1.5)

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

	Silhouettes.draw_unit(self, _shape_id(u), radius, u.team, _accent(u), u.team == CG.Team.ENEMY)

	_draw_concentration_badge(u, radius)

	# Everything below the body is stacked here, in order, because they used to
	# be written independently and two of them landed on the same pixels: the
	# wind-up countdown number sits at radius + 4 + a text height, which is
	# exactly where a badge row goes. Caught on a real 3x capture of a real
	# fight (Screenshots/wren_badge_placement_zoom3x.png), not by reading the
	# code -- both draws are correct on their own.
	var below := _draw_status_badges(u, radius)

	if u.action_ticks_left > 0 and u.current_action != &"":
		# PR #69 (sable, Scripts/Art/AttackFX.gd), wiring's third and final
		# piece: a flat Palette.WIND_UP circle told a player "something is
		# charging" but not what kind or how soon. AttackFX.draw_wind_up
		# recolours the ring per damage type (_accent(u), the same class
		# accent Silhouettes.draw_unit already reads a few lines up -- one
		# colour per unit, body and telegraph agree) and sweeps it as a real
		# countdown. action_ticks_total (issue, PR #72) captures the
		# *post-haste* length, so this reads correctly for a hasted unit
		# too -- elapsed/total would have silently desynced against the
		# action's own base wind_up_ticks otherwise, for exactly the pawns
		# (Priest grants HASTE) where it would have mattered.
		AttackFX.draw_wind_up(self, Vector2.ZERO, radius + 4.0, _accent(u), wind_up_elapsed_ticks(u), u.action_ticks_total)
		var font := ThemeDB.fallback_font
		var ticks_text := str(u.action_ticks_left)
		var text_size := font.get_string_size(ticks_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _label_font_size())
		draw_string(font, Vector2(-text_size.x * 0.5, radius + below + 4.0 + text_size.y),
			ticks_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _label_font_size(), Palette.WIND_UP)
		below += 4.0 + text_size.y

	_draw_status_tags(u, radius, below)

	# Stacked bottom-up, closest to the unit first: resource, then hp, then the
	# name. draw_string's position is a baseline, not a top-left corner, so the
	# label sits an extra font-height above where the last bar was drawn.
	var bar_width := BAR_WIDTH * DISPLAY_SCALE
	var bar_height := BAR_HEIGHT * DISPLAY_SCALE
	var bar_gap := BAR_GAP * DISPLAY_SCALE
	var y := -radius - bar_gap

	if u.resource_max > 0:
		y -= bar_height
		var res_pos := Vector2(-bar_width * 0.5, y)
		var res_fraction := float(u.resource) / float(u.resource_max)
		draw_rect(Rect2(res_pos, Vector2(bar_width, bar_height)), Palette.HP_BACK)
		draw_rect(Rect2(res_pos, Vector2(bar_width * res_fraction, bar_height)), Palette.resource_color(u.resource_kind))
		y -= bar_gap

	y -= bar_height
	var hp_pos := Vector2(-bar_width * 0.5, y)
	draw_rect(Rect2(hp_pos, Vector2(bar_width, bar_height)), Palette.HP_BACK)
	draw_rect(Rect2(hp_pos, Vector2(bar_width * u.hp_fraction(), bar_height)), Palette.hp_color(u.hp_fraction()))
	y -= bar_gap + _label_font_size() + _crowding_stagger(u)

	if _label_visible(u):
		_draw_label_chip(u.display_name, y, Palette.TEXT, _label_font_size())

## Palette.FONT_SIZE_SMALL is shared with screens that have nothing to do
## with the arena (InspectPanel's attribute chips, PartySelect), so it is
## not something this file can change — scaled locally instead, the same
## reasoning DISPLAY_SCALE itself exists for.
static func _label_font_size() -> int:
	return int(round(Palette.FONT_SIZE_SMALL * DISPLAY_SCALE))

## Both world-space-ish quantities that grew a real bigger footprint needs to
## respect: a bigger body and taller bar/label stack means two units that
## used to read as merely "nearby" now have their chrome actually touch at
## the same world distance. Found by comparing a real before/after screenshot
## of floor1_room1, not by reasoning about it — the first version of issue 31
## left these fixed and rows of enemies spaced for the old, smaller footprint
## overlapped their neighbours' labels.
const CROWD_RADIUS := 70.0 * DISPLAY_SCALE
const CROWD_STEP := 20.0 * DISPLAY_SCALE

## Extra headroom for this unit's name label when another unit is standing
## close enough for the two labels to land on the same spot — found in
## Tools/preview/fight_sheet.png, where "abomination" and "Grunt" overlapped
## illegibly the moment two units clashed in melee, which is exactly the
## moment reading who is who matters most. Deterministic by id (lower id
## never moves, each higher id crowded into the same spot stacks one step
## higher) rather than by draw order, so two views of the same fight agree
## on where a label lands.
func _crowding_stagger(u: CombatUnit) -> float:
	if _state == null:
		return 0.0
	# CROWD_STEP already carries DISPLAY_SCALE — do not multiply twice.
	return float(crowd_rank(u, _state.units)) * CROWD_STEP

## Issue 41: a dense room (floor1_room1, 10 enemies) piled every enemy's name
## into the top-middle of the screen at once, and no amount of vertical
## stagger reads as separate names once four labels share the same few rows
## -- see Screenshots/label_crowd_before_1280x720.png. Raising DISPLAY_SCALE
## further (2.0x, tried in issue 31) made it worse, not better: this is a
## count problem, not a spacing constant to retune again.
##
## Design call, not a bug fix: the party is at most four pawns and the player
## has to track all of them for the whole fight, so they keep a permanent
## label. An enemy's identity only matters at the moment it is actually
## relevant -- something the party is currently focusing (concentration_count
## already answers "is anyone fighting this"), or something about to land a
## hit of its own (the wind-up ring is already drawn for exactly this). A
## goblin standing untouched at the back of a ten-unit room does not need its
## name floating the whole time; it gets one the instant it becomes either of
## those two things.
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
##
## Issue 15's finding: three units converging on one target looked identical
## to three units standing near each other, and the line itself was too faint
## to trace where several overlapped. A dark outline under the line gives it
## contrast against any background; both colours are existing Palette tokens
## at a different alpha, not new literals.
func _draw_targeting_line(u: CombatUnit) -> void:
	if u.focus_id < 0 or u.current_action == &"":
		return
	# Issue 18 gave ranged actions a real travelling shot
	# (CombatState.projectiles, drawn by ArenaFloor); PLAYTEST-NOTES 2: this
	# line used to be drawn for the whole action regardless, so a real shot
	# still read as an instant beam covering the same ground the projectile
	# was travelling. Once this unit has launched one, the shot itself is
	# the targeting read and the beam would just double it; keep drawing the
	## line during wind-up, before anything has launched, and for melee
	# actions (no projectile ever spawns for those).
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

## How many other living units currently have this one as their focus —
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
	var badge_center := Vector2(radius * 0.75, -radius * 0.75)
	draw_circle(badge_center, 11.0 * DISPLAY_SCALE, Palette.HP_LOW)
	var font := ThemeDB.fallback_font
	var text := str(count)
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _label_font_size())
	draw_string(font, badge_center - text_size * 0.5 + Vector2(0.0, text_size.y * 0.75),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, _label_font_size(), Palette.TEXT)

## PLAYTEST-NOTES-2 item 2: "no clear visual for who is afflicted with what."
## Statuses were legible only from the log, which scrolls, in a fight the same
## notes call too fast to read.
##
## Below the unit, not above it. The whole existing stack -- resource bar, hp
## bar, name label, and the crowding stagger that pushes names further up when
## units bunch -- grows *upward* from the body, so the band above a unit is the
## contested one and the band below it is empty. Issue #82 (five names in one
## label's worth of space, death floaters crossing the arena) is about that
## upward band specifically, so putting badges there would have added a
## thirteenth thing to the pile. Death floaters spawn at the unit's own
## position and rise, so they clear this band too.
const STATUS_BADGE_SIZE := 14.0 * DISPLAY_SCALE
const STATUS_BADGE_GAP := Palette.SPACE_XS * DISPLAY_SCALE

## Clearance from the body before the row starts. Not the same number as the
## gap between badges: AttackFX.draw_wind_up puts its ring at radius + 4.0 with
## a 3.0-wide stroke, so anything closer than radius + 5.5 lands on top of the
## countdown ring. Measured off that call rather than guessed -- the first
## version used the inter-badge gap for both and the row clipped the ring's
## bottom arc on every unit mid-wind-up, which is exactly when a player is
## looking at that unit.
const STATUS_BADGE_TOP_GAP := 6.0 * DISPLAY_SCALE

## A unit can in principle carry every status at once. Four is what fits in a
## row roughly as wide as the unit's own hp bar, which is the widest thing it
## already draws -- past that the row is wider than the unit and starts
## colliding with its neighbours' rows instead of its own chrome. Harmful
## first (see status_badges), so the four shown are the four a player most
## needs: what is being done *to* this unit.
const MAX_STATUS_BADGES := 4

## Which badges this unit gets, in draw order. Split out from the drawing for
## the same reason status_tags is: Godot refuses draw_* outside _draw(), so a
## test that can only call the drawing wrapper logs errors and asserts nothing.
##
## Harmful before beneficial, each group in CG.Status declaration order.
## CombatUnit.statuses is a Dictionary, so its own key order is insertion
## order -- the order statuses happened to land during a fight, which would
## make the same unit's badges reshuffle mid-fight for no reason a player
## could read. CG.is_harmful() is the only thing consulted for the split,
## the same single source of truth StatusIcons uses for the plate direction.
static func status_badges(u: CombatUnit) -> Array:
	var harmful: Array = []
	var beneficial: Array = []
	for s in CG.Status.values():
		if not u.has_status(s):
			continue
		if CG.is_harmful(s):
			harmful.append(s)
		else:
			beneficial.append(s)
	var all := harmful + beneficial
	return all.slice(0, MAX_STATUS_BADGES)

func _draw_status_badges(u: CombatUnit, radius: float) -> float:
	var badges := status_badges(u)
	if badges.is_empty():
		return 0.0
	var top := radius + STATUS_BADGE_TOP_GAP
	var width := StatusIcons.row_width(badges.size(), STATUS_BADGE_SIZE, STATUS_BADGE_GAP)
	var rects := StatusIcons.layout_row(Vector2(-width * 0.5, top), badges.size(), STATUS_BADGE_SIZE, STATUS_BADGE_GAP)
	for i in badges.size():
		StatusIcons.draw_status(self, badges[i], rects[i])
	return STATUS_BADGE_TOP_GAP + STATUS_BADGE_SIZE

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
## silently lost its last letter at the old fixed width, which reads like a
## data bug rather than a rendering limit, and neighbouring labels overlapped
## illegibly whenever units bunched together mid-fight. Full names never
## truncate now; the chip is what keeps an overlapping label readable rather
## than fixing the overlap itself, which needs real layout space this view
## does not have.
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
## action_ticks_total (issue, PR #72) is captured post-haste at the moment
## the wind-up starts, so this stays correct for a hasted unit -- deriving
## a denominator from the action's own base wind_up_ticks instead would
## have silently desynced against a HASTE-scaled action_ticks_left, for
## exactly the pawns (Priest grants HASTE) where it would have mattered.
static func wind_up_elapsed_ticks(u: CombatUnit) -> int:
	return u.action_ticks_total - u.action_ticks_left

## Split out from _draw_status_tags so it can be tested without a live
## canvas: Godot refuses draw_* calls outside _draw(), so a test that calls a
## drawing function directly logs errors and asserts nothing, which is
## exactly the trap Silhouettes.build_parts's own doc comment names.
##
## STUN used to be listed here as text as well. It is a CG.Status, so it now
## draws as a badge like every other status, and leaving the word next to its
## own badge would have been the same fact twice in the most crowded part of
## the screen. Its own test in Tests/test_ui_unit_view.gd moved to
## status_badges rather than being deleted -- disclosed in the PR.
static func status_tags(u: CombatUnit) -> Array[String]:
	var tags: Array[String] = []
	if u.resource_max > 0 and u.resource <= 0:
		tags.append("OOM")
	return tags
