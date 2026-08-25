extends RefCounted
class_name Silhouettes


## What one unit looks like: a PNG in `Assets/Units/`, and nothing else.

## Every shape id with art on disk, sorted. Sorted because anything iterating
## content has to be deterministic.
static func shape_ids() -> Array[StringName]:
	var seen := {}
	var dir := DirAccess.open(UnitArt.ART_DIR)
	if dir != null:
		for file in dir.get_files():
			if not file.ends_with(".png"):
				continue
			var id := file.get_basename()
			if id.ends_with(".player") or id.ends_with(".enemy"):
				id = id.get_basename()
			seen[StringName(id)] = true
	# Issue 566: a unit whose art is a recipe has no file to be found by the walk
	# above, and the payoff the recipe exists for is exactly the creature nobody
	# has drawn. Without this line every such unit is invisible to the art
	# preview and to `test_art.gd`.
	for id in UnitRecipes.recipe_ids():
		seen[id] = true
	var ids: Array[StringName] = []
	for k in seen.keys():
		ids.append(k)
	ids.sort()
	return ids

static func has_shape(id: StringName) -> bool:
	return UnitArt.has_art(id, CG.Team.PLAYER) or UnitArt.has_art(id, CG.Team.ENEMY)

## Draws one unit's art centred on `center`, sized to fit a circle of `radius`.
static func draw_unit(
	canvas: CanvasItem,
	shape_id: StringName,
	radius: float,
	team: CG.Team,
	_accent: CG.DamageType,
	facing_left: bool = false,
	center: Vector2 = Vector2.ZERO
) -> void:
	var tex := UnitArt.texture_for(shape_id, team)
	if tex == null:
		canvas.draw_rect(Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0), Color.BLACK)
		return
	UnitArt.draw(canvas, tex, radius, facing_left, center)

## The box `draw_unit` actually puts ink in, in the same local space it draws
## into. **This is the number issue #190 is about.**
##
## Everything a unit wears -- health bar, badge row, impact ring, name plate --
## used to be sized from the simulation's collision radius, which no drawing
## fills. A goblin was a 15px body wearing a 90px health bar. Decoration sizes
## from the drawing instead, and this is where the drawing's size comes from.
static func drawn_extent(
	shape_id: StringName,
	radius: float,
	team: CG.Team,
	_accent: CG.DamageType = CG.DamageType.PHYSICAL,
	center: Vector2 = Vector2.ZERO
) -> Rect2:
	var tex := UnitArt.texture_for(shape_id, team)
	if tex == null:
		return Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0)
	return UnitArt.opaque_rect(radius, tex, center)

## The top edge of the drawing, sampled into `columns` bins across the unit's
## footprint, in the same local space `draw_unit` draws into. `INF` for a bin
## with no ink in it.
static func top_profile(
	shape_id: StringName,
	radius: float,
	team: CG.Team,
	columns: int = 40,
	_accent: CG.DamageType = CG.DamageType.PHYSICAL
) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(columns)
	out.fill(INF)
	if columns <= 0 or radius <= 0.0:
		return out

	var tex := UnitArt.texture_for(shape_id, team)
	if tex == null:
		# The black square: a flat top edge across the whole footprint.
		out.fill(-radius)
		return out
	var size := Vector2(tex.get_width(), tex.get_height())
	if size.x <= 0.0 or size.y <= 0.0:
		return out
	var scale := (radius * 2.0) / maxf(size.x, size.y)
	var tops := UnitArt.column_tops(tex)
	# Walk bins rather than columns: a sprite narrower than the bin count would
	# otherwise leave gaps that look like holes in the silhouette.
	for i in columns:
		var lo_x := -radius + (float(i) / float(columns)) * radius * 2.0
		var hi_x := -radius + (float(i + 1) / float(columns)) * radius * 2.0
		var lo := int(floor((lo_x / scale) + size.x * 0.5))
		var hi := int(ceil((hi_x / scale) + size.x * 0.5)) - 1
		var best := INF
		for x in range(maxi(lo, 0), mini(hi, int(size.x) - 1) + 1):
			if tops[x] < best:
				best = tops[x]
		if best < INF:
			out[i] = (best - size.y * 0.5) * scale
	return out

## `drawn_extent` as a fraction of the footprint the game reserves for the unit,
## per axis. 1.0 means the drawing fills its nominal box on that axis.
static func fill_ratio(shape_id: StringName, team: CG.Team) -> Vector2:
	var tex := UnitArt.texture_for(shape_id, team)
	if tex == null:
		return Vector2.ONE
	return UnitArt.opaque_fraction(tex)
