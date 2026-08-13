extends RefCounted

const CG := preload("res://Scripts/Core/CG.gd")
const Palette := preload("res://Scripts/Core/Palette.gd")

## Placeholder art, as polygons in code.
##
## MANAGER-OWNED (`Scripts/Art/**`). pike calls `draw_unit` from `UnitView` and
## does not need to edit this; ask for a shape and I add it.
##
## Why polygons and not image files: Godot imports `.svg` and `.png` through the
## editor, and the editor does not run on this machine — `--import`,
## `--editor --quit` and the windowed editor all hang with no output, on the
## Steam build and the official one alike. Anything needing an import step is
## therefore unavailable to us. Points in an array need no import, no `.import`
## sidecar and no `.godot/imported/` directory, so this works from a fresh
## worktree with nothing set up.
##
## It is also the honest kind of placeholder. Nobody will mistake these for
## final art, and each class is recognisable at a glance from across the arena,
## which is the only thing the slice actually needs from art: telling four
## pawns and six enemies apart while they move.
##
## Coordinates are in a unit square from -1 to 1, with -Y up. `draw_unit` scales
## by the unit's radius, so a shape drawn here is the right size everywhere.

## One drawable shape: a polygon and how to colour it.
##
## `tint` picks the colour at draw time rather than baking one in, so the same
## silhouette reads as a player pawn or an enemy without a second copy.
enum Tint {
	TEAM,      ## the unit's team colour
	TEAM_DARK, ## the team colour, darkened: shadow and underside
	ACCENT,    ## the class's damage-type colour: weapons, magic, glow
	OUTLINE,   ## the arena edge colour: keeps a shape readable on any ground
}

## Two things these were redrawn for after looking at them rendered, and both
## are worth keeping if you add a shape:
##
##   - **Silhouette over detail.** At the size a pawn actually occupies, colour
##     and interior shapes vanish and only the outline survives. So the
##     classes differ in outline first: the Warrior is a wide arc, the Priest a
##     narrow spire, the Siege Master a low wedge, the Abomination lopsided.
##     Squint at the preview; if two are the same blob, the difference is
##     decoration.
##   - **Axis-aligned edges read as boxes.** The first pass was all horizontal
##     and vertical edges and looked exactly like the squares it was meant to
##     replace. Almost every edge here is on a diagonal now.
const _PARTS := {
	# --- classes -----------------------------------------------------------
	# Warrior: the widest player outline. Heavy pauldrons sloping outward, a
	# kite shield past the left edge, a blade past the right.
	&"warrior": [
		{"tint": Tint.ACCENT, "poly": [[-0.66, -0.62], [-0.98, -0.34], [-0.94, 0.32], [-0.7, 0.72], [-0.5, 0.28], [-0.5, -0.44]]},
		{"tint": Tint.ACCENT, "poly": [[0.56, 0.44], [0.66, -0.72], [0.74, -0.96], [0.82, -0.72], [0.88, 0.44], [0.72, 0.56]]},
		{"tint": Tint.ACCENT, "poly": [[0.5, 0.4], [0.94, 0.4], [0.9, 0.56], [0.54, 0.56]]},
		{"tint": Tint.TEAM_DARK, "poly": [[-0.62, 1.0], [-0.44, 0.34], [0.44, 0.34], [0.62, 1.0], [0.3, 0.94], [0.16, 0.52], [-0.16, 0.52], [-0.3, 0.94]]},
		{"tint": Tint.TEAM, "poly": [[-0.78, -0.3], [-0.52, -0.66], [-0.24, -0.78], [0.24, -0.78], [0.52, -0.66], [0.78, -0.3], [0.5, 0.4], [-0.5, 0.4]]},
		{"tint": Tint.TEAM, "poly": [[-0.24, -0.8], [-0.16, -1.0], [0.16, -1.0], [0.24, -0.8]]},
	],
	# Priest: the narrowest and tallest outline, a spire. Pointed hood, robe
	# flaring to a wide hem, halo floating clear of the head.
	&"priest": [
		{"tint": Tint.ACCENT, "poly": [[-0.44, -0.9], [0.0, -1.0], [0.44, -0.9], [0.0, -0.8]]},
		{"tint": Tint.ACCENT, "poly": [[0.34, -0.5], [0.46, -0.56], [0.6, 0.86], [0.44, 0.9]]},
		{"tint": Tint.TEAM_DARK, "poly": [[-0.72, 1.0], [-0.34, 0.1], [0.34, 0.1], [0.72, 1.0], [0.0, 0.9]]},
		{"tint": Tint.TEAM, "poly": [[0.0, -0.74], [0.3, -0.2], [0.44, 0.62], [-0.44, 0.62], [-0.3, -0.2]]},
		{"tint": Tint.TEAM, "poly": [[0.0, -0.78], [0.2, -0.48], [0.0, -0.34], [-0.2, -0.48]]},
	],
	# Geysermancer: bottom-heavy with three jets of unequal height. The only
	# outline here that is taller than it is wide at the top and the reverse at
	# the bottom.
	&"geysermancer": [
		{"tint": Tint.ACCENT, "poly": [[-0.78, 0.2], [-0.62, -0.34], [-0.5, -0.62], [-0.42, -0.3], [-0.34, 0.2]]},
		{"tint": Tint.ACCENT, "poly": [[-0.12, -0.6], [0.0, -1.0], [0.12, -0.6], [0.0, -0.46]]},
		{"tint": Tint.ACCENT, "poly": [[0.34, 0.2], [0.44, -0.42], [0.56, -0.76], [0.66, -0.28], [0.78, 0.2]]},
		{"tint": Tint.TEAM_DARK, "poly": [[-0.86, 1.0], [-0.56, 0.24], [0.56, 0.24], [0.86, 1.0], [0.0, 0.86]]},
		{"tint": Tint.TEAM, "poly": [[-0.5, 0.3], [-0.36, -0.28], [0.0, -0.5], [0.36, -0.28], [0.5, 0.3]]},
		{"tint": Tint.TEAM, "poly": [[-0.18, -0.44], [0.0, -0.7], [0.18, -0.44], [0.0, -0.3]]},
	],
	# Siege Master: a low wedge on a wheel, with a long arm slung over the top.
	# The one player shape that is wider than it is tall.
	&"siege_master": [
		{"tint": Tint.ACCENT, "poly": [[-0.3, -0.5], [0.72, -0.98], [0.9, -0.72], [-0.1, -0.24]]},
		{"tint": Tint.ACCENT, "poly": [[0.66, -1.0], [0.98, -0.86], [0.86, -0.6], [0.58, -0.76]]},
		{"tint": Tint.TEAM_DARK, "poly": [[-0.96, 1.0], [-0.78, 0.5], [0.78, 0.5], [0.96, 1.0], [0.0, 0.9]]},
		{"tint": Tint.TEAM, "poly": [[-0.82, 0.56], [-0.66, -0.16], [-0.2, -0.44], [0.44, -0.4], [0.72, -0.04], [0.8, 0.56]]},
		{"tint": Tint.TEAM, "poly": [[-0.5, -0.42], [-0.36, -0.68], [-0.08, -0.68], [0.02, -0.42]]},
		{"tint": Tint.ACCENT, "poly": [[-0.86, 0.42], [-0.5, 0.42], [-0.44, 0.98], [-0.92, 0.98]]},
	],
	# Abomination: no symmetry anywhere. One oversized claw on the right, a
	# hunched mass leaning left, spines along the back.
	&"abomination": [
		{"tint": Tint.ACCENT, "poly": [[0.36, -0.22], [0.78, -0.34], [1.0, 0.1], [0.86, 0.62], [0.52, 0.44], [0.3, 0.14]]},
		{"tint": Tint.ACCENT, "poly": [[0.58, -0.3], [0.72, -0.66], [0.8, -0.28]]},
		{"tint": Tint.ACCENT, "poly": [[-0.56, -0.62], [-0.44, -0.98], [-0.3, -0.6]]},
		{"tint": Tint.ACCENT, "poly": [[-0.78, -0.3], [-0.98, -0.06], [-0.82, 0.34], [-0.62, 0.06]]},
		{"tint": Tint.TEAM_DARK, "poly": [[-0.9, 1.0], [-0.62, 0.22], [0.46, 0.14], [0.82, 1.0], [0.0, 0.86]]},
		{"tint": Tint.TEAM, "poly": [[-0.72, 0.3], [-0.66, -0.3], [-0.4, -0.66], [0.06, -0.82], [0.36, -0.5], [0.44, 0.02], [0.24, 0.4], [-0.4, 0.44]]},
		{"tint": Tint.TEAM, "poly": [[-0.34, -0.7], [-0.42, -0.94], [-0.06, -0.98], [0.04, -0.8]]},
	],

	# --- enemies -----------------------------------------------------------
	# Rat: a low horizontal profile, nose down at the front, tail curling off
	# the back. Nothing else here is this long and this flat.
	&"rat": [
		{"tint": Tint.ACCENT, "poly": [[-0.62, 0.1], [-0.86, -0.14], [-1.0, -0.5], [-0.86, -0.44], [-0.74, -0.14], [-0.54, 0.02]]},
		{"tint": Tint.TEAM_DARK, "poly": [[-0.74, 1.0], [-0.5, 0.42], [0.66, 0.42], [0.92, 1.0], [0.1, 0.9]]},
		{"tint": Tint.TEAM, "poly": [[-0.66, 0.46], [-0.5, -0.1], [-0.1, -0.4], [0.34, -0.42], [0.66, -0.2], [0.74, 0.46]]},
		{"tint": Tint.TEAM, "poly": [[0.42, -0.36], [0.64, -0.62], [0.94, -0.5], [0.98, -0.16], [0.72, -0.1]]},
		{"tint": Tint.ACCENT, "poly": [[0.5, -0.56], [0.56, -0.92], [0.76, -0.6]]},
		{"tint": Tint.ACCENT, "poly": [[0.86, -0.42], [1.0, -0.32], [0.88, -0.24]]},
	],
	# Grub: one soft segmented arc, no limbs and no weapon. The only shape here
	# with no straight vertical edge at all.
	&"grub": [
		{"tint": Tint.TEAM_DARK, "poly": [[-0.84, 1.0], [-0.92, 0.52], [0.92, 0.52], [0.84, 1.0], [0.0, 0.9]]},
		{"tint": Tint.TEAM, "poly": [[-0.9, 0.58], [-0.72, 0.0], [-0.4, -0.34], [0.0, -0.46], [0.4, -0.34], [0.72, 0.0], [0.9, 0.58]]},
		{"tint": Tint.TEAM_DARK, "poly": [[-0.5, -0.24], [-0.34, -0.5], [-0.16, -0.36], [-0.3, -0.14]]},
		{"tint": Tint.TEAM_DARK, "poly": [[0.16, -0.36], [0.34, -0.5], [0.5, -0.24], [0.3, -0.14]]},
		{"tint": Tint.ACCENT, "poly": [[-0.26, -0.44], [-0.16, -0.6], [-0.06, -0.44], [-0.16, -0.32]]},
		{"tint": Tint.ACCENT, "poly": [[0.06, -0.44], [0.16, -0.6], [0.26, -0.44], [0.16, -0.32]]},
	],
	# Brute: the largest outline of all, hunched forward, tiny head set low
	# between the shoulders, club head heavier than the arm holding it.
	&"brute": [
		{"tint": Tint.ACCENT, "poly": [[0.44, -0.36], [0.66, -0.98], [0.98, -0.86], [0.9, -0.28], [0.6, -0.14]]},
		{"tint": Tint.ACCENT, "poly": [[0.34, 0.28], [0.5, -0.28], [0.68, -0.22], [0.52, 0.34]]},
		{"tint": Tint.TEAM_DARK, "poly": [[-1.0, 1.0], [-0.74, 0.34], [0.74, 0.34], [1.0, 1.0], [0.0, 0.88]]},
		{"tint": Tint.TEAM, "poly": [[-0.94, 0.4], [-0.88, -0.3], [-0.56, -0.68], [0.2, -0.72], [0.66, -0.4], [0.76, 0.4]]},
		{"tint": Tint.TEAM_DARK, "poly": [[-0.2, -0.62], [-0.24, -0.88], [0.14, -0.9], [0.2, -0.64]]},
		{"tint": Tint.ACCENT, "poly": [[-0.16, -0.8], [-0.06, -0.86], [-0.02, -0.74]]},
		{"tint": Tint.ACCENT, "poly": [[0.02, -0.82], [0.12, -0.86], [0.14, -0.72]]},
	],
}

## Every shape id this file knows, sorted. Sorted because anything iterating
## content has to be deterministic, and a Dictionary's order is not something to
## rely on.
static func shape_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for k in _PARTS.keys():
		ids.append(k)
	ids.sort()
	return ids

static func has_shape(id: StringName) -> bool:
	return _PARTS.has(id)

## Draws one unit's silhouette centred on the origin of `canvas`, sized so it
## fits a circle of `radius`.
##
## `shape_id` falls back to a plain marker rather than drawing nothing, because
## an invisible unit is a far worse failure than an ugly one: a fight where a
## combatant cannot be seen looks like a simulation bug and is not.
static func draw_unit(
	canvas: CanvasItem,
	shape_id: StringName,
	radius: float,
	team: CG.Team,
	accent: CG.DamageType,
	facing_left: bool = false
) -> void:
	for part in build_parts(shape_id, radius, team, accent, facing_left):
		var points: PackedVector2Array = part["points"]
		if part["filled"]:
			canvas.draw_colored_polygon(points, part["fill"])
		# A darker edge. Without it the accent shapes bleed into the body at the
		# sizes these actually get drawn at.
		var closed := points.duplicate()
		closed.append(points[0])
		canvas.draw_polyline(closed, part["outline"], part["outline_width"], true)

## Every polygon of a shape, resolved to world-space points and final colours.
##
## Split out from `draw_unit` so it can be tested. Godot refuses `draw_*` calls
## outside `_draw()`, so a test that calls `draw_unit` directly logs a wall of
## errors and asserts nothing — which is exactly what the first version of the
## test for this file did, and it "passed". Geometry and colour are the parts
## that can be wrong silently; the drawing itself is four engine calls.
static func build_parts(
	shape_id: StringName,
	radius: float,
	team: CG.Team,
	accent: CG.DamageType,
	facing_left: bool = false
) -> Array[Dictionary]:
	var team_color := Palette.team_color(team)
	var colors := {
		Tint.TEAM: team_color,
		Tint.TEAM_DARK: team_color.darkened(0.45),
		Tint.ACCENT: Palette.damage_color(accent),
		Tint.OUTLINE: Palette.ARENA_EDGE,
	}

	var parts: Array = _PARTS.get(shape_id, [])
	if parts.is_empty():
		return _unknown_parts(radius, team_color)

	var flip := -1.0 if facing_left else 1.0
	var out: Array[Dictionary] = []
	for part in parts:
		var points := PackedVector2Array()
		for p in part["poly"]:
			points.append(Vector2(float(p[0]) * flip, float(p[1])) * radius)
		out.append({
			"points": points,
			"fill": colors[part["tint"]],
			"outline": colors[Tint.OUTLINE],
			"outline_width": 1.0,
			"filled": true,
		})
	return out

## The fallback. Deliberately unlike every real shape: a hollow diamond reads
## instantly as "this one has no art yet" rather than as a new enemy type.
static func _unknown_parts(radius: float, team_color: Color) -> Array[Dictionary]:
	return [{
		"points": PackedVector2Array([
			Vector2(0.0, -radius), Vector2(radius, 0.0),
			Vector2(0.0, radius), Vector2(-radius, 0.0),
		]),
		"fill": team_color,
		"outline": team_color,
		"outline_width": 2.0,
		"filled": false,
	}]
