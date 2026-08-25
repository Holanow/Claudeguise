extends RefCounted
class_name Terrain


## What a room contains besides its combatants: walls, hazards, chokepoints.

## Axis-aligned only, in world units, in the same space as CombatUnit.position.
enum Kind {
	WALL,    ## blocks movement and blocks line of sight
	PILLAR,  ## blocks line of sight, does not block movement
	HAZARD,  ## passable, damages a unit standing in it each tick
	PIT,     ## blocks movement, does not block line of sight
	WATER,   ## passable, harmless, and puts out burning ground it touches
}

class Feature extends RefCounted:
	var kind: Kind = Kind.WALL
	var rect: Rect2 = Rect2()

	## HAZARD only. Damage per tick to a unit whose centre is inside `rect`.
	## The number is teal's; the mechanism is wren's.
	var damage_per_tick: int = 0
	var damage_type: CG.DamageType = CG.DamageType.PHYSICAL

	var applies_status: CG.Status = CG.Status.SHIELD
	var applies_status_enabled: bool = false
	var status_duration_ticks: int = 0

	## How hard the applied status hits, for the statuses whose whole damage rate
	## is a multiple of a magnitude the applying hit normally supplies. A hazard
	## has no hit, so it declares one here or its status ticks for nothing.
	var status_magnitude: float = 0.0

	func blocks_movement() -> bool:
		return kind == Kind.WALL or kind == Kind.PIT

	func blocks_sight() -> bool:
		return kind == Kind.WALL or kind == Kind.PILLAR

	## Issue 554: the painted region, as disjoint rectangles. **Empty means the
	## feature is exactly `rect`**, which is every authored feature and every
	## hazard; only water fills it. `rect` stays the bounding box either way, so
	## code that only wants a cheap reject does not care which kind it has.
	var parts: Array[Rect2] = []

	## The ground this feature actually covers.
	func regions() -> Array[Rect2]:
		return parts if not parts.is_empty() else [rect]

	func contains_point(p: Vector2) -> bool:
		if parts.is_empty():
			return rect.has_point(p)
		for r in parts:
			if r.has_point(p):
				return true
		return false

static func make(kind: Kind, rect: Rect2) -> Feature:
	var f := Feature.new()
	f.kind = kind
	f.rect = rect
	return f

## Issue 492: a pool of water. It does nothing on its own, which is the whole
## of its definition -- no damage, no status, no movement cost.
static func pool(rect: Rect2) -> Feature:
	return make(Kind.WATER, rect)

## Issue 554, the player's own words: *"the pools just fuse into one, think
## painting the floor"*. Stamps `stamp` onto `f`'s painted region and returns
## whether any new ground got wet.
##
## The stored parts are kept **disjoint**: the stamp is cut by what is already
## painted, so no ground is stored twice, a stamp entirely inside the region is
## discarded at the door, and the region can never wet ground no cast painted.
## That last property is why this is not a union of bounding boxes.
static func paint(f: Feature, stamp: Rect2) -> bool:
	var remaining: Array[Rect2] = [stamp]
	for existing in f.regions():
		var next: Array[Rect2] = []
		for r in remaining:
			next.append_array(subtract(r, existing))
		remaining = next
		if remaining.is_empty():
			return false
	if f.parts.is_empty():
		f.parts = [f.rect]
	for r in remaining:
		f.parts.append(r)
		f.rect = f.rect.merge(r)
	return true

## Ground that is on fire, which is the only thing a pool reacts to.
static func is_burning(f) -> bool:
	return f.kind == Kind.HAZARD and f.damage_type == CG.DamageType.FIRE

## Areas below this in either dimension are dropped rather than kept. Issue 492:
## a subtraction that leaves slivers fills `terrain` with features nothing can
## see and everything walks.
const MIN_FEATURE_SIZE := 0.5

## `a` with `b` cut out of it, as zero to four axis-aligned parts. The order is
## fixed -- above, below, left, right -- because two runs of the same fight must
## produce the same terrain array, not merely the same covered area.
static func subtract(a: Rect2, b: Rect2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var overlap := a.intersection(b)
	if overlap.size.x <= 0.0 or overlap.size.y <= 0.0:
		if _keep(a):
			out.append(a)
		return out
	var strips: Array[Rect2] = [
		Rect2(a.position.x, a.position.y, a.size.x, overlap.position.y - a.position.y),
		Rect2(a.position.x, overlap.end.y, a.size.x, a.end.y - overlap.end.y),
		Rect2(a.position.x, overlap.position.y, overlap.position.x - a.position.x, overlap.size.y),
		Rect2(overlap.end.x, overlap.position.y, a.end.x - overlap.end.x, overlap.size.y),
	]
	for r in strips:
		if _keep(r):
			out.append(r)
	return out

static func _keep(r: Rect2) -> bool:
	return r.size.x >= MIN_FEATURE_SIZE and r.size.y >= MIN_FEATURE_SIZE

static func hazard(rect: Rect2, damage_per_tick: int, damage_type: CG.DamageType) -> Feature:
	var f := make(Kind.HAZARD, rect)
	f.damage_per_tick = damage_per_tick
	f.damage_type = damage_type
	return f

## True when the straight line from `a` to `b` crosses anything opaque. The one
## piece of geometry all three sessions would otherwise write separately.
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
