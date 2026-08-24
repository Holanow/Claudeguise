extends RefCounted
class_name ShieldWall


## The cover a SHIELDING unit puts in front of itself, drawn rather than baked
## because its extent and orientation are a function of live state: the
## shielder's facing, and whether the status is up this tick.

## How thick the plate draws, and how far its middle bows ahead of its ends.
## World units, and neither is the frontage: only `half_width` is.
const DEPTH := 24.0
const BOW := 12.0

## The frontage is divided into this many panels, each bowing forward on its
## own, so the plate reads as a row of shields rather than as one long blade --
## which is what a stranger could not identify in issue 332.
const PANELS := 5
const PANEL_BOW := 5.0

## The arm that ties the plate to the body holding it. It starts at the
## shielder's own centre, under the drawn body, so no gap can open between the
## two however much larger than world scale that body is drawn.
const HAFT_HALF := 3.5

## The plate draws under every unit, so a pawn sheltering behind it is never
## repainted and the fill can carry more weight than it could when it sat on
## top of the crowd.
const FILL_ALPHA := 0.22
const OUTLINE_WIDTH := 2.0

## The edge that stops shots, drawn heavier than the rest so the plate has a
## front rather than being a symmetric bar.
const LIP_WIDTH := 6.0
const SEAM_WIDTH := 2.0
const SEAM_ALPHA := 0.75

## The plate says what it is, because three strangers in a row could not name
## it: the same SHIELDING badge the shielder's own status row carries, stamped
## once per panel, and the ability's name in front of the lip.
const BADGE_SIZE := 26.0
const LABEL := "Directional Block"
const LABEL_FONT_SIZE := 16
const LABEL_STANDOFF := 8.0
const LABEL_PAD := Vector2(5.0, 3.0)

## Half the frontage the simulation protects, in world units, read from the
## same constant `CombatSim._find_shielder` measures a shot against rather than
## copied: a drawn width that can drift teaches the player a false place to
## stand.
static func half_width() -> float:
	return CombatSim.SHIELD_WIDTH * 0.5

static func _rot(facing: Vector2) -> Transform2D:
	var angle := facing.angle() if facing.length_squared() > 0.0001 else 0.0
	return Transform2D(angle, Vector2.ZERO)

static func _to_world(rot: Transform2D, local: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in local:
		out.append(rot * p)
	return out

## How far forward the front edge sits at `t`, where t runs -1 to 1 across the
## frontage. `extra` is the panel's own bulge, applied at panel middles only.
static func _front(standoff: float, t: float, extra: float) -> float:
	return standoff + DEPTH + BOW * (1.0 - t * t) + extra

## The front edge in local space, right end to left end: a scallop per panel.
## `PANELS` is odd, so the deepest point of the deepest panel is at t = 0 and
## the plate still bows forward at its middle.
static func _front_edge(half: float, standoff: float) -> Array:
	var out := []
	for i in range(PANELS, 0, -1):
		var hi := -1.0 + 2.0 * float(i) / float(PANELS)
		var lo := -1.0 + 2.0 * float(i - 1) / float(PANELS)
		var mid := (hi + lo) * 0.5
		out.append(Vector2(_front(standoff, hi, 0.0), hi * half))
		out.append(Vector2(_front(standoff, mid, PANEL_BOW), mid * half))
	out.append(Vector2(_front(standoff, -1.0, 0.0), -half))
	return out

## The plate in the shielder's local space, +X along `facing`. The back edge is
## flat and spans exactly `half_width * 2`; the front edge bows forward, which
## is the only thing that says which way it stops shots.
static func wall_points(facing: Vector2, half: float, standoff: float) -> PackedVector2Array:
	var local := [Vector2(standoff, -half), Vector2(standoff, half)]
	local.append_array(_front_edge(half, standoff))
	return _to_world(_rot(facing), local)

## Just the front edge of the plate, end to end.
static func lip_points(facing: Vector2, half: float, standoff: float) -> PackedVector2Array:
	return _to_world(_rot(facing), _front_edge(half, standoff))

## One two-point line per join between panels, back edge to front edge. These
## are what stop the band reading as a single blade.
static func seam_points(facing: Vector2, half: float, standoff: float) -> Array:
	var rot := _rot(facing)
	var out := []
	for i in range(1, PANELS):
		var t := -1.0 + 2.0 * float(i) / float(PANELS)
		out.append(_to_world(rot, [
			Vector2(standoff, t * half),
			Vector2(_front(standoff, t, 0.0), t * half),
		]))
	return out

## The centre of each panel, in the shielder's local space: half way through
## that panel's own depth, on the line through the middle of its frontage.
static func panel_centers(facing: Vector2, half: float, standoff: float) -> PackedVector2Array:
	var out := []
	for i in PANELS:
		var t := -1.0 + (2.0 * float(i) + 1.0) / float(PANELS)
		out.append(Vector2((standoff + _front(standoff, t, PANEL_BOW)) * 0.5, t * half))
	return _to_world(_rot(facing), out)

## The chip carrying the name, in the shielder's local space. It is drawn
## upright while the plate turns, so it is pushed along `facing` until no
## corner of it is behind the lip -- centring it on a point in front of the lip
## still laid half the chip over the badges at an eastward facing.
static func label_chip(facing: Vector2, standoff: float) -> Rect2:
	var f := facing.normalized()
	var size := ThemeDB.fallback_font.get_string_size(LABEL, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE) + LABEL_PAD * 2.0
	var anchor := f * (_front(standoff, 0.0, PANEL_BOW) + LABEL_STANDOFF)
	var chip := Rect2(anchor - size * 0.5, size)
	var behind := 0.0
	for corner in [chip.position, chip.position + Vector2(chip.size.x, 0.0),
			chip.position + Vector2(0.0, chip.size.y), chip.end]:
		behind = maxf(behind, (anchor - corner).dot(f))
	chip.position += f * behind
	return chip

static func haft_points(facing: Vector2, standoff: float) -> PackedVector2Array:
	var front := standoff + DEPTH * 0.6
	return _to_world(_rot(facing), [
		Vector2(0.0, -HAFT_HALF),
		Vector2(0.0, HAFT_HALF),
		Vector2(front, HAFT_HALF * 0.55),
		Vector2(front, -HAFT_HALF * 0.55),
	])

## The two things the simulation needs before a shielder blocks anything: the
## status is up, and it has a facing to block along.
static func is_up(u: CombatUnit) -> bool:
	return u != null and u.alive and u.has_status(CG.Status.SHIELDING) and u.facing != Vector2.ZERO

static func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var out := points.duplicate()
	out.append(points[0])
	return out

## Every stroke and fill is trimmed to `room`, the play area in the shielder's
## own local space. Cover drawn outside the room shelters nobody -- nothing can
## stand there -- and a plate leaving the arena through the wall was half of
## what read as a rendering artifact.
static func _fill_clipped(canvas: CanvasItem, points: PackedVector2Array, room: PackedVector2Array, color: Color) -> void:
	for piece in Geometry2D.intersect_polygons(points, room):
		canvas.draw_colored_polygon(piece, color)

static func _line_clipped(canvas: CanvasItem, points: PackedVector2Array, room: PackedVector2Array, color: Color, width: float) -> void:
	for piece in Geometry2D.intersect_polyline_with_polygon(points, room):
		if piece.size() >= 2:
			canvas.draw_polyline(piece, color, width, true)

## Draws the plate for `u` at the canvas origin. `standoff` is how far clear of
## the drawn body its back edge sits; it does not change the frontage.
static func draw_for(canvas: CanvasItem, u: CombatUnit, standoff: float, room: PackedVector2Array) -> void:
	if not is_up(u):
		return
	var edge := Palette.team_color(u.team)
	var fill := edge
	fill.a = FILL_ALPHA
	var seam := edge
	seam.a = SEAM_ALPHA
	var half := half_width()
	var wall := wall_points(u.facing, half, standoff)

	_fill_clipped(canvas, haft_points(u.facing, standoff), room, edge)
	_fill_clipped(canvas, wall, room, fill)
	_line_clipped(canvas, _closed(wall), room, edge, OUTLINE_WIDTH)
	for line in seam_points(u.facing, half, standoff):
		_line_clipped(canvas, line, room, seam, SEAM_WIDTH)
	_line_clipped(canvas, lip_points(u.facing, half, standoff), room, edge, LIP_WIDTH)
	_draw_name(canvas, u.facing, half, standoff, room, edge)

## The badges and the name, both drawn upright whatever the shielder faces: a
## glyph rotated with the plate is a shape again rather than an icon.
static func _draw_name(canvas: CanvasItem, facing: Vector2, half: float, standoff: float, room: PackedVector2Array, edge: Color) -> void:
	var badge := Vector2(BADGE_SIZE, BADGE_SIZE)
	for center in panel_centers(facing, half, standoff):
		if Geometry2D.is_point_in_polygon(center, room):
			StatusIcons.draw_status(canvas, CG.Status.SHIELDING, Rect2(center - badge * 0.5, badge))

	var chip := label_chip(facing, standoff)
	if not Geometry2D.is_point_in_polygon(chip.get_center(), room):
		return
	canvas.draw_rect(chip, Color(Palette.BACKGROUND, 0.92))
	canvas.draw_rect(chip, edge, false, 1.0)
	var font := ThemeDB.fallback_font
	canvas.draw_string(font, chip.position + LABEL_PAD + Vector2(0.0, chip.size.y - LABEL_PAD.y - font.get_descent(LABEL_FONT_SIZE)),
		LABEL, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, edge)

## Every shielder on the field, drawn from the arena rather than from each
## unit's own node: `UnitView`s are siblings, so a plate drawn inside one of
## them repaints whichever units happen to come earlier in the child order --
## the units it exists to shelter (issue 332).
## Issue 511: `at_by_id` is where each body is drawn this frame, so the plate
## rides the interpolated body instead of the tick position it left behind. An
## id with no entry falls back to the simulated position.
static func draw_all(canvas: CanvasItem, units: Array, standoff_scale: float,
		at_by_id: Dictionary = {}) -> void:
	for candidate in units:
		var u: CombatUnit = candidate
		if not is_up(u):
			continue
		var at: Vector2 = at_by_id.get(u.id, u.position)
		canvas.draw_set_transform(at, 0.0, Vector2.ONE)
		draw_for(canvas, u, u.radius * standoff_scale, room_for(at))
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## The play area in the local space of a shielder standing at `position`.
static func room_for(position: Vector2) -> PackedVector2Array:
	var hw := CG.ARENA_HALF_WIDTH
	var hh := CG.ARENA_HALF_HEIGHT
	return PackedVector2Array([
		Vector2(-hw, -hh) - position, Vector2(hw, -hh) - position,
		Vector2(hw, hh) - position, Vector2(-hw, hh) - position,
	])
