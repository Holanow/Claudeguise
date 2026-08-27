extends RefCounted
class_name PartAnimation


## Issue 583. How a PART moves, and which motion an ACTION asks it for.
##
## The player: "you would animate the hands and then those animations would
## generalize to everything with hands". So motion is keyed by part, not by
## unit: a recipe naming `hands` inherits all of this, and a recipe that names
## no animated part has no animation and needs no case for that.

## Which motion is playing. `IDLE` is the resting bob; the other three are the
## player's shared set, chosen by the action rather than by the creature.
enum Kind { IDLE, MELEE, RANGED, CAST }

## The parts that move, and how far each throws its motion as a share of the
## drawn radius. A part absent from here is drawn where it was baked.
## `hand_wide`/`hand_wide_off` reach further because they start further out.
##
## Issue 584: a weapon shares its wielding hand's factor rather than getting
## one of its own, so `HandMain` and `Weapon` travel through exactly the same
## arc and never drift apart -- the flapping the brief exists to avoid.
const PARTS := {
	&"hand": 1.0, &"hand_off": 1.0,
	&"hand_wide": 1.15, &"hand_wide_off": 1.15,
	&"sword": 1.15, &"bow": 1.15, &"sickle": 1.15,
	&"staff": 1.0, &"orb": 1.0,
}

static func animates(part: StringName) -> bool:
	return PARTS.has(part)

## World units. An action reaching no further than this is a swing rather than
## a shot: every melee action in the game sits at 40-55 and the shortest ranged
## one at 140, so the gap is wide and this sits in the middle of it.
const MELEE_RANGE_THRESHOLD := 60.0

## Which of the three shared motions an action asks for, derived from what
## `ActionDef` already declares so a new action animates the day it is written.
##
## Cast is last and is also the fallback. A test for "the pawn is MAGICAL or the
## action costs Mana" is not written because no input can fail it: an action that
## is neither a short-range swing nor a projectile is already a cast.
static func kind_for(action: ActionDef) -> Kind:
	if action == null:
		return Kind.IDLE
	if action.projectile_speed <= 0.0 \
			and action.range_units > 0.0 \
			and action.range_units <= MELEE_RANGE_THRESHOLD:
		return Kind.MELEE
	if action.projectile_speed > 0.0:
		return Kind.RANGED
	return Kind.CAST

## Seconds for one idle bob. Slow enough to read as breathing rather than as a
## vibration at the 20-60 screen pixels a body is actually drawn at.
const IDLE_SECONDS := 1.9

## The bob's amplitude, as a share of the drawn radius.
const IDLE_BOB := 0.17

## How far a melee thrust carries the hands forward, and how far back it winds
## first. Both as a share of the drawn radius.
const MELEE_REACH := 0.55
const MELEE_WIND_BACK := 0.20

## Where in the wind-up the thrust starts. Before this the hands are drawing
## back; after it they travel, arriving exactly as the blow lands.
const MELEE_RELEASE := 0.62

## How far a ranged draw pulls the hands back and up.
const RANGED_DRAW := 0.45
const RANGED_LIFT := 0.18

## How high a cast raises the hands, and how wide the circle they trace while
## it builds.
const CAST_LIFT := 0.50
const CAST_ORBIT := 0.12

## Turns of that circle over one cast, so a long cast winds more than a short
## one rather than moving more slowly through the same arc.
const CAST_TURNS := 1.5

## The slash: wind back, then swing through. In degrees because that is how
## the player specified it; converted once at load rather than at every call.
const MELEE_WIND_DEGREES := -40.0
const MELEE_SWING_DEGREES := 75.0

## The off-hand's motion is the main hand's own, scaled down -- one arm swings,
## the other counterbalances, rather than both doing the same thing.
const OFF_HAND_SHARE := 0.35

## The resting bob, in local draw pixels. `phase` keeps a row of goblins out of
## step; `seconds` is view time and stops dead while `ViewClock.frozen`, because
## its only source is the delta `BattleView._render` spends.
static func idle_offset(seconds: float, phase: float, radius: float) -> Vector2:
	return Vector2(0.0, -sin(seconds * TAU / IDLE_SECONDS + phase) * IDLE_BOB * radius)

## The pose at `progress` through a wind-up, in local draw pixels, with +x
## forward. `progress` is 0.0 at the moment the unit commits and 1.0 at the
## moment the effect lands, so the SAME definition covers a 6-tick Stab and a
## 45-tick Engine Bolt: one snaps, one creeps, and the creep is the telegraph.
static func action_offset(kind: Kind, progress: float, radius: float) -> Vector2:
	var p := clampf(progress, 0.0, 1.0)
	match kind:
		Kind.MELEE:
			return _melee(p) * radius
		Kind.RANGED:
			return _ranged(p) * radius
		Kind.CAST:
			return _cast(p) * radius
	return Vector2.ZERO

## Draw back, then throw. Quadratic on the way out so the hands accelerate into
## the blow instead of sliding to it, without hiding the whole throw in the last
## two frames the way a cubic did.
static func _melee(p: float) -> Vector2:
	if p < MELEE_RELEASE:
		var w := p / MELEE_RELEASE
		return Vector2(-MELEE_WIND_BACK * w * w, 0.0)
	var t := (p - MELEE_RELEASE) / (1.0 - MELEE_RELEASE)
	var eased := t * t
	return Vector2(-MELEE_WIND_BACK + (MELEE_REACH + MELEE_WIND_BACK) * eased, 0.0)

## The angle at `progress` through a wind-up, in radians, driven off the SAME
## `progress` `action_offset` uses -- a separately-timed rotation drifts from
## the thrust and reads as a weapon flapping near a hand. Only `MELEE` turns;
## a draw and a cast hold the weapon steady.
static func action_angle(kind: Kind, progress: float) -> float:
	if kind != Kind.MELEE:
		return 0.0
	return _melee_angle(clampf(progress, 0.0, 1.0))

## Same shape as `_melee`'s translation: wind back quadratically, release, then
## swing through quadratically, so the angle and the thrust arrive together.
static func _melee_angle(p: float) -> float:
	var wind := deg_to_rad(MELEE_WIND_DEGREES)
	var swing := deg_to_rad(MELEE_SWING_DEGREES)
	if p < MELEE_RELEASE:
		var w := p / MELEE_RELEASE
		return wind * w * w
	var t := (p - MELEE_RELEASE) / (1.0 - MELEE_RELEASE)
	var eased := t * t
	return wind + (swing - wind) * eased

## The off-hand's own quieter echo of the main hand's motion: a fraction of the
## same offset, and a small opposing turn rather than the same one.
static func off_hand_offset(kind: Kind, progress: float, radius: float) -> Vector2:
	return action_offset(kind, progress, radius) * OFF_HAND_SHARE

static func off_hand_angle(kind: Kind, progress: float) -> float:
	return -action_angle(kind, progress) * OFF_HAND_SHARE

## A draw held to the loose: back and up, easing out, so a long draw sits at
## full tension rather than crawling through it.
static func _ranged(p: float) -> Vector2:
	var eased := 1.0 - (1.0 - p) * (1.0 - p)
	return Vector2(-RANGED_DRAW * eased, -RANGED_LIFT * eased)

## Raised, and circling while the spell builds. The circle is what makes a
## 45-tick cast read as work being done rather than as a frozen pose.
static func _cast(p: float) -> Vector2:
	var lift := -CAST_LIFT * (1.0 - (1.0 - p) * (1.0 - p))
	var a := p * TAU * CAST_TURNS
	return Vector2(sin(a) * CAST_ORBIT * p, lift + cos(a) * CAST_ORBIT * p)

## A unit's own place in the idle cycle, from its id. Deterministic and free of
## `state.rng`, which a view must never touch.
static func phase_for(unit_id: int) -> float:
	return fposmod(float(unit_id) * 2.399963, TAU)
