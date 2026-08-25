extends RefCounted
class_name AttackFX


## Attack visuals, keyed by damage type rather than by class. Interior detail
## vanishes at the size a unit or a 5px projectile mark actually draws, and
## every action already carries a damage type that the floating numbers
## already colour by.

## Issue 572: the shapes below are now AUTHORING data for
## `Tools/BakeProjectiles.gd` rather than what the game draws every frame. A
## dart is the same picture on every frame -- only its rotation and position
## change -- so it does not qualify for the art ruling's aim-line carve-out.

## How far past the authored +/-1 the baked canvas reaches, so the outline the
## bake strokes on is not clipped at the tips. The draw below spans the same.
const PROJECTILE_ART_SPAN := 1.05

## The outline's width in the units the shapes are authored in. `ArenaFloor`
## draws a mark at `size` 15 and the polyline this replaces was 1.0 unit wide,
## so 1/15 reproduces exactly what shipped -- and now scales with the mark
## rather than staying one unit wide whatever the mark does.
const PROJECTILE_OUTLINE_WIDTH := 1.0 / 15.0

const _PROJECTILE_SHAPES := {
	# Arrow: a head and a shaft, the plainest "this is a shot" read.
	CG.DamageType.PHYSICAL: [
		[1.0, 0.0], [0.25, 0.4], [0.25, 0.15], [-1.0, 0.15],
		[-1.0, -0.15], [0.25, -0.15], [0.25, -0.4],
	],
	# Flame: asymmetric, wide and licking at the back, tapering to a point.
	CG.DamageType.FIRE: [
		[1.0, 0.0], [0.2, 0.55], [-0.6, 0.4], [-1.0, 0.0],
		[-0.5, -0.5], [0.1, -0.35], [0.4, -0.15],
	],
	# Droplet: symmetric, rounded, the plain opposite of fire's wobble.
	CG.DamageType.WATER: [
		[1.0, 0.0], [0.3, 0.55], [-0.5, 0.6], [-1.0, 0.0],
		[-0.5, -0.6], [0.3, -0.55],
	],
	# Crescent: a thin curved sliver, the only shape here with a concave edge.
	CG.DamageType.AIR: [
		[0.9, 0.3], [0.3, 0.75], [-0.6, 0.55], [-0.9, 0.0],
		[-0.5, 0.15], [-0.1, 0.35], [0.5, 0.1],
	],
	# Chunk: blunt and angular, the only shape here with no point at all.
	CG.DamageType.EARTH: [
		[0.7, 0.5], [-0.3, 0.7], [-0.9, 0.2], [-0.7, -0.5],
		[0.2, -0.7], [0.8, -0.1],
	],
	# Spike: a symmetric elongated cross -- front and back points reach
	# further than top and bottom, so it still reads as "travelling" rather
	# than as a plain plus sign.
	CG.DamageType.DIVINE: [
		[1.0, 0.0], [0.15, 0.15], [0.15, 0.7], [-0.15, 0.7],
		[-0.15, 0.15], [-1.0, 0.0], [-0.15, -0.15], [-0.15, -0.7],
		[0.15, -0.7], [0.15, -0.15],
	],
	# Barb: a dart with two backward-facing hooks, the only shape here that
	# reaches furthest sideways rather than forward or back.
	CG.DamageType.PROFANE: [
		[1.0, 0.0], [0.2, 0.3], [-0.4, 0.7], [-0.1, 0.15],
		[-1.0, 0.5], [-0.3, 0.0], [-1.0, -0.5], [-0.1, -0.15],
		[-0.4, -0.7], [0.2, -0.3],
	],
	# Burst: a plain four-point star, no directionality at all -- Raw is the
	# one damage type with no elemental or moral read, so its mark does not
	# pretend to point anywhere.
	CG.DamageType.RAW: [
		[1.0, 0.0], [0.2, 0.2], [0.0, 1.0], [-0.2, 0.2],
		[-1.0, 0.0], [-0.2, -0.2], [0.0, -1.0], [0.2, -0.2],
	],
}

## The points for one damage type, scaled to `size` and rotated so local +X
## points along `forward` (world space, not necessarily normalised).
static func projectile_points(damage_type: CG.DamageType, size: float, forward: Vector2) -> PackedVector2Array:
	var raw: Array = _PROJECTILE_SHAPES.get(damage_type, _PROJECTILE_SHAPES[CG.DamageType.PHYSICAL])
	var angle := forward.angle() if forward.length_squared() > 0.0001 else 0.0
	var rot := Transform2D(angle, Vector2.ZERO)
	var out := PackedVector2Array()
	for p in raw:
		out.append(rot * (Vector2(p[0], p[1]) * size))
	return out

## Draws one in-flight shot at `position`, oriented along `forward` (its
## direction of travel), coloured and shaped by `damage_type`. Caller's job to
## only call this while a shot is unresolved -- same filter ArenaFloor already
## applies to its own marker.
static func draw_projectile(canvas: CanvasItem, position: Vector2, forward: Vector2, damage_type: CG.DamageType, size: float) -> void:
	var half := size * PROJECTILE_ART_SPAN
	var box := Rect2(Vector2(-half, -half), Vector2(half, half) * 2.0)
	var tex := UIArt.texture_for(projectile_art_name(damage_type))
	if tex == null:
		# The player's ruling: a missing sprite is a black square, which is an
		# obvious defect rather than a silent one.
		canvas.draw_rect(Rect2(position + box.position, box.size), Color.BLACK)
		return
	var angle := forward.angle() if forward.length_squared() > 0.0001 else 0.0
	canvas.draw_set_transform(position, angle, Vector2.ONE)
	canvas.draw_texture_rect(tex, box, false)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## The file one mark is drawn from: `Assets/UI/projectile/fire.png`. Lower-cased
## enum name, the same convention `StatusIcons.art_name` uses.
static func projectile_art_name(damage_type: CG.DamageType) -> StringName:
	return StringName("projectile/%s" % String(CG.DamageType.keys()[damage_type]).to_lower())

## Every damage type, in enum order. The set is bounded and small; enumerated
## here so the bake and the tests cannot disagree about which marks exist.
static func damage_types() -> Array:
	var out: Array = []
	for name in CG.DamageType.keys():
		out.append(CG.DamageType[name])
	return out

## Interrupt ring geometry, and only that since #573 deleted the damage ring.
## `progress` is 0 at the tick the event lands, 1 at the
## end of its own short on-screen life (a fraction of a second -- callers own
## the actual duration, same split BattleView's DamageFloater already uses
## between "how long" and "what it looks like at time t").
static func impact_flash_radius(base_radius: float, progress: float) -> float:
	return base_radius * lerpf(0.4, 1.8, clampf(progress, 0.0, 1.0))

static func impact_flash_alpha(progress: float) -> float:
	return lerpf(0.9, 0.0, clampf(progress, 0.0, 1.0))

