extends Node2D
class_name UnitView


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

## Issue 82 / the first fresh-eyes playtest: **"a green bar is roughly 70px
## wide. The figure it belongs to is roughly 8px tall... often nearer to a
## different figure than its own."**
##
## `BAR_WIDTH * DISPLAY_SCALE` is 90 for every unit in the game, while a goblin
## is 33 across and a party pawn 66. A bar nearly three times the width of the
## body under it does not read as that body's health; it reads as a floating
## object that happens to be nearby, which is exactly what a reader with no
## prior knowledge reported. **Tying the bar to the body is what makes it
## legible as belonging to one**, and it matters more now that names default
## off and cannot disambiguate.
##
## Floored so a small unit's chrome stays usable -- the wind-up block below
## shares this width and has a fixed-size icon to fit inside it.
## Issue 190: was 44, and **44 was the whole defect for every enemy in the
## game.** Measured: a goblin's drawn body is 18.5px wide, so sizing the bar
## from the drawn shape changed nothing at all while this floor held -- it
## clamped straight back up to 44 and stayed 2.4x the creature. The floor
## existed so the wind-up block's fixed-size icon still fitted; that icon scales
## now instead, which is what lets this come down to "a bar is still a bar".
const MIN_BAR_WIDTH := 20.0

## Everything a unit wears -- bar width, the bar stack's anchor, the badge row
## -- measures from the **drawn** body, not from `CombatUnit.radius`.
##
## The radius is the collision footprint and the art fills a fraction of it,
## so sizing from it gave a goblin a 44px bar over 15px of body. The player's
## own pawns are the narrowest on the field (priest 0.50, warrior 0.54), and
## the vertical axis is worse: `siege_master` fills 0.33 of its box.
##
## Uses `Silhouettes.drawn_extent` / `fill_ratio`, sable's, so this cannot
## drift from the art. Deriving it from `build_parts` here measured the
## polygons instead, which ten shapes with real PNGs never render.
##
## Do NOT reach for the texture's `get_width()`: pixel art carries margin --
## `siege_master.png` is 24x14 with 20x8 opaque -- so that path fixes a third
## of the error while looking like it fixed all of it. `opaque_rect` scans.
##
## Cached per shape and team at a reference radius: PNG art is per-team, and
## both paths scale linearly with radius, so one measurement rescales.
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

## Issue 31: units read too small, worse now that sable's real art carries
## detail invisible at the old size (a real rendered fight: ten units in
## roughly the middle fifth of a 1280x720 arena, sprites about twenty
## pixels across). A view-only scale, deliberately not a change to
## `CombatUnit.radius`/`EnemyDef.radius` themselves: those read as "drawing
## only" in their own doc comments, and that comment is wrong -- checked
## rather than trusted, `CombatSim._move_toward` calls
## `Terrain.point_is_blocked(state.terrain, candidate, unit.radius)` for real
## movement collision. Changing the stored radius would be a balance change
## in a UI issue's clothes. Flagged to rook rather than corrected here since
## `CombatUnit.gd` is Core.
##
## Applied uniformly to everything drawn around a unit -- the body, its bars,
## its labels, its badges -- so a bigger silhouette does not leave suddenly-
## tiny text stranded next to it. `BattleView.gd` imports this same constant
## for the floating numbers and death markers that spawn at a unit's
## position, so the whole visual footprint of a unit grows together.
## 2.0 was tried first and measured against a real ten-enemy room
## (floor1_room1): bodies read well, but row spacing there is tuned for the
## old footprint (rows 100-140 world units apart) and doubling every bar and
## the name font on top of a doubled body pushed adjacent rows' chrome into
## each other -- worse than the problem this issue exists to fix. 1.5 still
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
## into CombatState -- the simulation's positions are wren's and this changes
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
			var angle := float(u.id) * 2.4
			push += Vector2(cos(angle), sin(angle)) * min_dist * _SEPARATION_STRENGTH
	return push.limit_length(u_radius * 1.5)

## Which way the body is drawn, from `CombatUnit.facing` -- the same quantity the
## simulation uses to decide whether the Warrior's guard stops a shot.
##
## Issue 256. This used to be `u.team == CG.Team.ENEMY`, so **every enemy was
## permanently mirrored and no unit was ever drawn facing where it was looking.**
## That is not a cosmetic gap: `_shot_is_blocked` reads `facing` to decide
## whether an attack gets through, so the game was deciding an outcome on a fact
## it then refused to draw, and a player watching the guard fail could not see
## why. `CombatSim` maintains `facing` from movement and from target commitment.
##
## **Zero means "no facing yet"**, per the field's own doc comment, and it is
## every unit before anything moves -- the whole first tick of every fight. The
## team guess is kept for exactly that case, where it is a fair starting pose
## rather than a lie: the party deploys on the left and looks right, the room is
## on the right and looks back.
##
## A facing with no horizontal component says nothing about which way to mirror,
## and falls back to the same team pose. **I wrote state into this view to hold
## the previous pose across that case, then measured it and deleted it:
## `Tools/FacingLoad.gd`, 99,285 living unit-ticks over three rooms and thirty
## fights, found it exactly 0 times.** A unit is committed to something beside it
## or walking toward it; landing on a facing of exactly zero x is possible and
## does not happen. Static, and no memory.
##
## **What the same measurement says about this change, because it is smaller than
## it sounds: the team rule was already right 98.1% of the time** -- 735 of
## 42,398 unit-ticks wrong on `floor1_room1`, 587 of 30,840 on `floor1_cover`, 20
## of 26,047 on `floor1_warden`. Units mostly do face the way their side started.
## The 1.7% is the whole of the turning, which is the part a player is trying to
## read, and it is the part the Warrior's guard is decided on.
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

	# Everything below the body is stacked here, in order, because these used to
	var body_bottom := drawn_bottom(_shape_id(u), u.team, radius)
	var below := _draw_wind_up(u, radius, body_bottom)
	below += _draw_status_badges(u, radius, body_bottom, below)
	_draw_status_tags(u, body_bottom, below)

	# Stacked bottom-up, closest to the unit first: resource, then hp, then the
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

	# Issue 82: name plates are a toggle now, defaulting off, and this is the
	if DisplayOptions.enabled(&"name_plates") and _label_visible(u):
		_draw_label_chip(u.display_name, y, Palette.TEXT, _label_font_size())

## Issue 187, and TWO independent cold readers reported it before it was filed:
## *"twenty floating dashes with insects underneath"*, and *"nothing tying a bar
## to a body"*. In a crowd one unit's bar sits directly over another's body.
##
## **The distance itself is not mine to close and I want that on the record
## rather than implied.** The bars are anchored to `CombatUnit.radius`, which is
## the unit's real footprint -- the same number the simulation collides with --
## so they sit just clear of the space a unit occupies, which is correct. What a
## reader compares them against is the **ink**, and the art does not fill its
## canvas: a ~66px footprint carrying ~14px of drawn pixels leaves a ~30px empty
## band that reads as the bar floating. sable has that half. Anchoring to a
## guess at the ink instead would collide with the art the moment they fix it.
##
## So this is the half that works either way: **a tether.** A thin line from the
## bar stack down to the body says which body, at any gap, and it keeps saying
## it when the gap closes. It is drawn in the unit's team colour so a bar, its
## tether and its body are one object in one colour, which is what "belongs to"
## has to look like when twenty of them overlap.
##
## Deliberately thin and low-alpha: it is a relationship, not a thing. A solid
## line would become the twenty-first mark on a screen two readers have now
## asked to have marks REMOVED from.
const TETHER_WIDTH := 1.0 * DISPLAY_SCALE
const TETHER_ALPHA := 0.55

func _draw_bar_tether(u: CombatUnit, stack_bottom: float) -> void:
	var color := Palette.team_color(u.team)
	color.a = TETHER_ALPHA
	# Stops at the body's centre rather than its edge: the ink is somewhere
	draw_line(Vector2(0.0, stack_bottom), Vector2.ZERO, color, TETHER_WIDTH)

## Issue 82, and the finding that forced it: **`Palette.HP_LOW` and
## `Palette.TEAM_ENEMY` are the same colour, `e0705f`.** So every unit's bar ran
## the same red-to-green ramp regardless of side, a hurt party pawn was drawn in
## the enemy's own colour, and a fresh reader reported the field as "green
## dashes" that never answered *am I ahead* -- the first question a spectator
## has.
##
## The fill is the unit's **team** colour, and damage is carried by the bar's
## length and by the fill darkening toward the trough. Team identity therefore
## survives at every health level, where before it was never present at all.
## Two channels, the same rule sable's badges follow.
##
## Not put in `Palette.hp_color`: that is `Scripts/Core`, rook's, and this needs
## no new shared function -- `team_color` and `HP_BACK` already exist.
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
	# Issue 190, three fixes to one mark. Both cold readers called this the most
	var shape := _shape_id(u)
	var half := drawn_half_width(shape, u.team, radius)
	# Issue 198, sable's prescription taken as written: an ARC at radius 8, not a
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
##
## This replaces the wind-up ring and the raw tick number that used to sit
## under it. The ring said "charging" and the number said "17", which is a
## quantity in a unit the player has never seen. Neither said what was coming.
##
## The substrate is untouched: `wind_up_elapsed_ticks` still reads
## `action_ticks_total` (PR #72), captured post-haste at the moment the wind-up
## starts, so a hasted unit reads 0 at its own start and full at its own end.
## This is a ratio, never an absolute tick count, which is why halving
## `CG.TICKS_PER_SECOND` to 15 moved nothing here -- checked rather than
## assumed, and `test_a_wind_up_bar_is_a_ratio_not_a_tick_count` holds it.
##
## The whole block is exactly as wide as the hp bar above it, icon included,
## so a unit's chrome stays one column instead of growing a wider row at the
## exact moment the arena is most crowded.
const WIND_UP_ICON_SIZE := 16.0 * DISPLAY_SCALE
const WIND_UP_TOP_GAP := 4.0 * DISPLAY_SCALE
const WIND_UP_ICON_GAP := 3.0 * DISPLAY_SCALE

## Takes a radius since issue 82: the whole block is still exactly as wide as
## the hp bar above it, but that width now depends on the body.
## The icon scales with the block it sits in. Fixed at `WIND_UP_ICON_SIZE` it
## was 24px inside what is now a 20px bar for a goblin -- wider than the whole
## block, which is why the bar could not shrink before.
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
## Issue 190: `radius` is still the footprint (it drives the width, which must
## match the hp bar exactly) while `top_offset` is where the drawn body ends, so
## the block sits under the creature rather than under its reservation.
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

## Clearance from whatever is above the row -- the body, or the wind-up bar
## when the unit is mid-action. Deliberately larger than the gap between
## badges: two badges of the same unit belong together and should read as one
## row, and the row belongs to the unit rather than to the thing above it.
const STATUS_BADGE_TOP_GAP := 6.0 * DISPLAY_SCALE

## A unit can in principle carry every status at once. **Two**, on the player's
## ruling in issue 208, and the reason is that the reservation was being paid
## for in width by every unit and earned by almost none.
##
## sable's `Tools/StatusLoad.gd`, 2,201,587 unit-ticks over real parties and
## every encounter at 20 seeds:
##
##   statuses at once      0     1     2     3     4     5     6     7
##   share            79.14 12.63  5.76  1.38  0.74  0.25  0.07  0.03  %
##   enemies at 5+                                          0     0     0
##
## **The row is empty 79.1% of the time, and of the ticks carrying anything,
## 88.2% carry one or two.** No enemy in two million unit-ticks ever carried
## five. Four slots were reserved always and earned on 1.0% of ticks, and the
## width was charged to every goblin -- exactly where the row is worst, at 2.7x
## the drawn body.
##
## **A cap of two hides something on 2.5% of unit-ticks** and #161's "+N" chip
## reports that truthfully. One would have hidden something on 8.2%, and the
## difference between those two is an overflow chip that is rare and one a
## player learns to distrust.
##
## Harmful first (see status_badges), so the two shown are the two a player most
## needs: what is being done *to* this unit.
const MAX_STATUS_BADGES := 2

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
##
## A silently truncated row is worse than a short one: the player reads four
## badges as "this unit has four statuses", which is a statement the game is
## making and it is false. `+2` is not as good as showing them, but it is true,
## and it tells the player there is something they are not being shown.
static func hidden_status_count(u: CombatUnit) -> int:
	var total := ordered_statuses(u).size()
	if total <= MAX_STATUS_BADGES:
		return 0
	return total - (MAX_STATUS_BADGES - 1)

## The floor, and issue 208 is entirely about this number.
##
## It was `7.0 * DISPLAY_SCALE`, and **every ordinary enemy in the game was
## pinned to it** -- goblin, goblin_archer, cultist, ghoul, rat and stalker all
## measured **8.7 px on screen at 1280x720**, and 4.7 px at 844x390. That is
## #190's downstream consequence: making the decoration fit the drawn body was
## right, and nobody measured what it did to the badges.
##
## `BADGE-LEGIBILITY.md` has been arguing about 17.4 px since February and
## nothing on the field has been drawn at 17.4 px for months. That same document
## already said *"at 9.4 px there is no badge design that works"*, and the
## DESKTOP size was below it.
##
## **sable rendered all thirteen glyphs at every rung and the set reads at 16 px**
## (`Screenshots/badge_legibility.png`), so the fix is the size and not the
## drawing -- which overturned the assignment they were given, and they said so
## rather than redrawing something that was never the problem.
##
## `13.0 * DISPLAY_SCALE` is 19.5 world units, which the arena's own fit puts at
## **~16 px at 1280x720**, expressed the same way as the ceiling two constants
## up so the two move together. The floor is now close to the ceiling on purpose:
## a badge is a fixed piece of iconography rather than a scaled decoration, and
## below 16 px there is no drawing that rescues it.
##
## AND DO NOT REACH FOR THE DISCRIMINATION METRIC TO APPROVE A SMALLER ONE. It
## runs backwards -- 24.0% at 4.7 px against 13.2% at 32 px -- because at small
## sizes it is measuring the plate rather than the glyph. sable found that and it
## is the sort of number that reads as permission.
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
