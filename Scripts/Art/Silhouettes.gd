extends RefCounted
class_name Silhouettes


## What one unit looks like: the parts its recipe names, and nothing else.

## Every shape id with art, sorted. Sorted because anything iterating content has
## to be deterministic.
static func shape_ids() -> Array[StringName]:
	return UnitRecipes.recipe_ids()

static func has_shape(id: StringName) -> bool:
	return UnitArt.has_art(id, CG.Team.PLAYER) or UnitArt.has_art(id, CG.Team.ENEMY)

## Draws one unit's art centred on `center`, sized to fit a circle of `radius`.
## Immediate mode, for the screens and instruments that draw a unit once into a
## canvas they already own -- the arena builds a `UnitVisual` sprite tree instead,
## off the same `UnitArt.sprites_for` list, so the two cannot drift.
static func draw_unit(
	canvas: CanvasItem,
	shape_id: StringName,
	radius: float,
	team: CG.Team,
	_accent: CG.DamageType,
	facing_left: bool = false,
	center: Vector2 = Vector2.ZERO
) -> void:
	var sprites := UnitArt.sprites_for(shape_id, team)
	if sprites.is_empty():
		canvas.draw_rect(Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0), Color.BLACK)
		return
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for s in sprites:
		var tex: Texture2D = s["tex"]
		# A missing part is a black square, per the player's ruling: an obvious
		# defect beats a silent hole in a body.
		if tex == null:
			canvas.draw_rect(Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0), Color.BLACK)
			continue
		canvas.draw_texture_rect(tex, UnitArt.signed_rect(tex, radius, facing_left, center), false, s["color"])

## The box `draw_unit` actually puts ink in, in the same local space it draws
## into: **the union of the visible slot sprites.** This is the number issue #190
## is about.
##
## Everything a unit wears -- health bar, badge row, impact ring, name plate --
## used to be sized from the simulation's collision radius, which no drawing
## fills. A goblin was a 15px body wearing a 90px health bar.
static func drawn_extent(
	shape_id: StringName,
	radius: float,
	team: CG.Team,
	_accent: CG.DamageType = CG.DamageType.PHYSICAL,
	center: Vector2 = Vector2.ZERO
) -> Rect2:
	if UnitArt.sprites_for(shape_id, team).is_empty():
		return Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0)
	return UnitArt.body_rect(shape_id, team, radius, center)

## The top edge of the drawing, sampled into `columns` bins across the unit's
## footprint, in the same local space `draw_unit` draws into. `INF` for a bin with
## no ink in it.
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

	var n := UnitArt.canvas_size(shape_id, team)
	if n <= 0.0:
		# The black square: a flat top edge across the whole footprint.
		out.fill(-radius)
		return out
	var scale := (radius * 2.0) / n
	var tops := UnitArt.body_column_tops(shape_id, team)
	# Walk bins rather than columns: a sprite narrower than the bin count would
	# otherwise leave gaps that look like holes in the silhouette.
	for i in columns:
		var lo_x := -radius + (float(i) / float(columns)) * radius * 2.0
		var hi_x := -radius + (float(i + 1) / float(columns)) * radius * 2.0
		var lo := int(floor((lo_x / scale) + n * 0.5))
		var hi := int(ceil((hi_x / scale) + n * 0.5)) - 1
		var best := INF
		for x in range(maxi(lo, 0), mini(hi, int(n) - 1) + 1):
			if tops[x] < best:
				best = tops[x]
		if best < INF:
			out[i] = (best - n * 0.5) * scale
	return out

## `drawn_extent` as a fraction of the footprint the game reserves for the unit,
## per axis. 1.0 means the drawing fills its nominal box on that axis.
static func fill_ratio(shape_id: StringName, team: CG.Team) -> Vector2:
	if UnitArt.sprites_for(shape_id, team).is_empty():
		return Vector2.ONE
	return UnitArt.opaque_fraction(shape_id, team)
