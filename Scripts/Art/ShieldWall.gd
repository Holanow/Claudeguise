extends RefCounted
class_name ShieldWall


## The cover a SHIELDING unit puts in front of itself, drawn rather than baked
## because its extent and orientation are a function of live state: the
## shielder's facing, and whether the status is up this tick.

## How thick the plate draws, and how far its middle bows ahead of its ends.
## World units, and neither is the frontage: only `half_width` is.
const DEPTH := 9.0
const BOW := 7.0

## Alpha low enough that a pawn sheltering behind the plate still reads through
## it.
const FILL_ALPHA := 0.34
const OUTLINE_WIDTH := 2.0

## The half-frontage the simulation actually protects, in world units.
## `CombatSim._find_shielder` blocks a shot whose closest approach to the
## shielder's centre is within `SHIELD_WIDTH`, so the covered band is
## `SHIELD_WIDTH` either side of that centre and this is read from the same
## constant rather than copied.
static func half_width() -> float:
	return CombatSim.SHIELD_WIDTH

## The plate in the shielder's local space, +X along `facing`. The back edge is
## flat and spans exactly `half_width * 2`; the front edge bows forward, which
## is the only thing that says which way it stops shots.
static func wall_points(facing: Vector2, half: float, standoff: float) -> PackedVector2Array:
	var angle := facing.angle() if facing.length_squared() > 0.0001 else 0.0
	var rot := Transform2D(angle, Vector2.ZERO)
	var front := standoff + DEPTH
	var local := [
		Vector2(standoff, -half),
		Vector2(standoff, half),
		Vector2(front, half * 0.92),
		Vector2(front + BOW, 0.0),
		Vector2(front, -half * 0.92),
	]
	var out := PackedVector2Array()
	for p in local:
		out.append(rot * p)
	return out

## The two things the simulation needs before a shielder blocks anything: the
## status is up, and it has a facing to block along.
static func is_up(u: CombatUnit) -> bool:
	return u != null and u.alive and u.has_status(CG.Status.SHIELDING) and u.facing != Vector2.ZERO

## Draws the plate for `u` at the canvas origin. `standoff` is how far clear of
## the drawn body its back edge sits; it does not change the frontage.
static func draw_for(canvas: CanvasItem, u: CombatUnit, standoff: float) -> void:
	if not is_up(u):
		return
	var fill := Palette.team_color(u.team)
	fill.a = FILL_ALPHA
	UIArt.draw_outlined_polygon(canvas, wall_points(u.facing, half_width(), standoff),
		fill, Palette.team_color(u.team), OUTLINE_WIDTH)
