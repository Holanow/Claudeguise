extends RefCounted
class_name Terrain


## What a room contains besides its combatants: walls, hazards, chokepoints.
##
## MANAGER-OWNED SHAPE. Frozen like the rest of Scripts/Core. The simulation
## side is wren's, the placement is teal's, the drawing is pike's, and this file
## is the one thing all three agree on.
##
## Why it exists at all: every fight so far has been two clusters walking into
## each other across an empty rectangle, and no fight has ever been close.
## Terrain is the cheapest thing that makes position matter — a wall means a
## ranged unit can be denied line of sight, a chokepoint means four attackers
## cannot all reach one target, a hazard means the shortest path is not always
## the right one. Balance changes which side of a landslide you are on. Terrain
## changes whether the fight is a landslide.
##
## Deliberately not a tile grid. The simulation is continuous 2D, and a grid
## here would either force the movement code onto tiles or leave two
## representations of the same space to disagree with each other.

## Axis-aligned only, in world units, in the same space as CombatUnit.position.
## Rectangles rather than polygons because every consumer stays simple: the
## simulation's blocking test, the plan interpreter's line-of-sight check and
## pike's draw call are each a few lines against a Rect2 and each would be a
## research project against arbitrary polygons. If a room needs a diagonal, it
## gets one out of several rectangles.
enum Kind {
	WALL,    ## blocks movement and blocks line of sight
	PILLAR,  ## blocks line of sight, does not block movement
	HAZARD,  ## passable, damages a unit standing in it each tick
	PIT,     ## blocks movement, does not block line of sight
}

class Feature extends RefCounted:
	var kind: Kind = Kind.WALL
	var rect: Rect2 = Rect2()

	## HAZARD only. Damage per tick to a unit whose centre is inside `rect`.
	## The number is teal's; the mechanism is wren's.
	var damage_per_tick: int = 0
	var damage_type: CG.DamageType = CG.DamageType.PHYSICAL

	## A status applied to a unit standing in this feature. The player's tar
	## pit: terrain that slows rather than hurts.
	##
	## `applies_status_enabled` rather than a sentinel, because `CG.Status.SHIELD`
	## is 0 and would make "no status" and "shield" the same value. `ActionDef`
	## already carries the pair for the same reason.
	##
	## Off for every feature that exists today, so nothing changes until content
	## sets it — and the rate feeds the shared rng, so an accidental default
	## would move every fight rather than only the afflicted ones.
	var applies_status: CG.Status = CG.Status.SHIELD
	var applies_status_enabled: bool = false
	var status_duration_ticks: int = 0

	func blocks_movement() -> bool:
		return kind == Kind.WALL or kind == Kind.PIT

	func blocks_sight() -> bool:
		return kind == Kind.WALL or kind == Kind.PILLAR

	func contains_point(p: Vector2) -> bool:
		return rect.has_point(p)

static func make(kind: Kind, rect: Rect2) -> Feature:
	var f := Feature.new()
	f.kind = kind
	f.rect = rect
	return f

static func hazard(rect: Rect2, damage_per_tick: int, damage_type: CG.DamageType) -> Feature:
	var f := make(Kind.HAZARD, rect)
	f.damage_per_tick = damage_per_tick
	f.damage_type = damage_type
	return f

## True when the straight line from `a` to `b` crosses anything opaque. The one
## piece of geometry all three sessions would otherwise write separately, so it
## lives here and is written once.
##
## Uses Rect2.intersects_segment via Godot's own clipping rather than a
## hand-rolled line-box test, because a hand-rolled one is exactly the kind of
## code that is subtly wrong for a year.
## **A feature standing between two points cannot also be standing between two
## points inside it.** Issue 255, and rook granted this file for exactly this
## one change.
##
## Measured, not supposed. `Tools/StallProbe.gd` found `floor1_cover` reaching
## the 3600-tick cap once in 2,000 fights, seed 364, with **three units on the
## same point inside the same pillar, sight BLOCKED between them at distance
## 0.0**. Nothing could resolve a shot, moving toward a target you are standing
## on covers no ground, and the fight ran forever. A PILLAR blocks sight and not
## movement (`blocks_movement` is `WALL or PIT`), so walking into one is legal
## and units do it.
##
## **The clause is as narrow as three failing tests could make it, and I widened
## it twice before the evidence narrowed it back. Both of those attempts are
## recorded here because each one names a real rule this must not break.**
##
## First attempt, *either* endpoint inside. Too broad, and three tests I did not
## write said so:
##
##   - `test_content_rooms.gd`, twice -- a unit inside a pillar became visible to
##     and from the whole room, so standing *in* cover beat standing behind it.
##     Fights diverging with pillars in fell to 23 of 50 and shots denied to 890.
##   - `test_combat_projectiles.gd` -- a shot that had flown into a wall exempted
##     that wall and carried on through it.
##
## Second attempt, *both* endpoints inside any sight-blocker. The room tests came
## back, the projectile one did not: its fixture drops a wall over the target's
## own position, so the shot and the target end up inside the same rect and the
## hit lands. **I moved that fixture's wall instead, which was a guess, and it
## failed for an unrelated reason -- a wall the shot has already flown past
## cannot block a line drawn from where the shot is now. Reverted; that test is
## untouched.**
##
## So: **a feature the units can be standing in**, containing **both** endpoints.
## `blocks_movement()` is the difference. A WALL or a PIT cannot hold a unit --
## `CombatSim._sweep` refuses to land in one and `Tools/StallProbe.gd` reports 0
## of 14 spawns inside a blocking rect -- so exempting one could only ever change
## a state the simulation cannot produce, while breaking a check that guards a
## real one. A PILLAR is the shape a unit really can stand in, and that is the
## whole of the defect.
##
## It reads `contains_point`, the same `rect.has_point` that `_segment_hits_rect`
## uses for its own endpoint test directly below -- so the two agree on what
## "inside" means by construction, rather than by two authors remembering to.
static func line_is_blocked(features: Array, a: Vector2, b: Vector2) -> bool:
	for f in features:
		if not f.blocks_sight():
			continue
		if not f.blocks_movement() and f.contains_point(a) and f.contains_point(b):
			continue
		if _segment_hits_rect(f.rect, a, b):
			return true
	return false

## True when a circle of `radius` centred at `p` overlaps anything solid.
## Takes the radius because a unit is not a point to the movement code, even
## though it is one to the targeting code.
static func point_is_blocked(features: Array, p: Vector2, radius: float) -> bool:
	for f in features:
		if not f.blocks_movement():
			continue
		if f.rect.grow(radius).has_point(p):
			return true
	return false

static func hazards_at(features: Array, p: Vector2) -> Array:
	var out: Array = []
	for f in features:
		if f.kind == Kind.HAZARD and f.contains_point(p):
			out.append(f)
	return out

## Liang-Barsky segment/rectangle clip, and nothing else.
##
## The first version of this had a bounding-box early-out in front of it, on the
## theory that most walls are nowhere near most lines. It was wrong for exactly
## the case the game is full of: a horizontal segment has zero height, so
## `Rect2(a, b - a)` had zero area and the check rejected every axis-aligned
## line of sight before the real test ran. Both "a wall between two points
## blocks sight" tests failed and nothing else did.
##
## The early-out was an optimisation for a cost nobody had measured, in front of
## a function that is already a dozen arithmetic operations. It is gone.
static func _segment_hits_rect(rect: Rect2, a: Vector2, b: Vector2) -> bool:
	if rect.has_point(a) or rect.has_point(b):
		return true
	return _liang_barsky(rect, a, b)

static func _liang_barsky(rect: Rect2, a: Vector2, b: Vector2) -> bool:
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	var p := [-d.x, d.x, -d.y, d.y]
	var q := [
		a.x - rect.position.x,
		rect.position.x + rect.size.x - a.x,
		a.y - rect.position.y,
		rect.position.y + rect.size.y - a.y,
	]
	for i in 4:
		if is_zero_approx(p[i]):
			if q[i] < 0.0:
				return false
			continue
		var t: float = q[i] / p[i]
		if p[i] < 0.0:
			t0 = maxf(t0, t)
		else:
			t1 = minf(t1, t)
		if t0 > t1:
			return false
	return true
