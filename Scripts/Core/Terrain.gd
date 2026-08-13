extends RefCounted

const CG := preload("res://Scripts/Core/CG.gd")

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
static func line_is_blocked(features: Array, a: Vector2, b: Vector2) -> bool:
	for f in features:
		if not f.blocks_sight():
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
