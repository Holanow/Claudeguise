extends RefCounted
class_name AttackFX


## The attack visuals PLAYTEST-NOTES item 4 asks for: "every class needs an
## attack asset or animation so I know what's up."
##
## MANAGER-OWNED (`Scripts/Art/**`). Both pieces are wired into the fight and
## both call sites are `Scripts/UI`, wren's: `ArenaFloor` draws the projectile
## marker and `ImpactFlash` draws the burst.
##
## ---------------------------------------------------------------------------
## WHY DAMAGE TYPE AND NOT CLASS
##
## A per-class animation would lose to the outline the same way a literal
## rasterization of the old polygons lost to Silhouettes' hand-designed
## shapes in the first art pass -- interior detail and motion both vanish at
## the size a unit or a 5px projectile mark actually draws. Damage type
## survives that: every action already carries one (ActionDef.damage_type),
## the floating numbers already colour by it (Palette.damage_color), and a
## Priest's Smite now reads nothing like a Cultist's Dark Bolt even though
## both are "a ranged bolt" in the abstract -- which is closer to what the
## player is actually asking to be able to tell apart than "which class
## threw it" is.
##
## ---------------------------------------------------------------------------
## TWO PIECES
##
## 1. Projectile shape (`projectile_points` / `draw_projectile`) -- a small
##    distinct silhouette per damage type, replacing a single dot-with-trail
##    for every ranged shot.
## 2. Impact flash (`impact_flash_radius` / `impact_flash_alpha` /
##    `draw_impact_flash`) -- a brief radial burst at the position and tick a
##    DAMAGE/HEAL event lands, so melee gets an actual attack visual and not
##    just a number appearing.
##
## There were three. The middle one was a wind-up telegraph ring, and it is
## gone: PR #84 replaced the ring with a progress bar carrying an ability icon
## (`UnitView._draw_wind_up` + `ActionIcons`), the player preferred the bar, and
## nothing in the game reached `draw_wind_up` afterwards. Removed in issue #85
## rather than left with passing tests, which is the one thing that makes dead
## code look load-bearing.
##
## Geometry and colour are split from the actual draw_* calls the same way
## Silhouettes.build_parts is split from Silhouettes.draw_unit: Godot refuses
## draw_* outside _draw(), so a test that only calls the draw_ wrapper logs a
## wall of errors and asserts nothing.

## One polygon per damage type, in a unit circle (-1..1) with +X as "forward"
## -- the direction of travel. draw_projectile rotates and scales these; nothing
## here knows about world space.
##
## Colour alone already carries most of the read at the ~5-10px a projectile
## mark draws (Palette.damage_color, same as the floating numbers), so shape
## is the secondary cue -- for a viewer who cannot rely on the colour, same
## reasoning Terrain's hazard stripes exist alongside its colour fill. Kept
## simple on purpose: one polygon, no negative-space islands, because there is
## no room for a detached feature at this size the way there is on a full unit
## silhouette.
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
## Split from draw_projectile so a test can check the geometry without a
## live canvas.
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
	var points := projectile_points(damage_type, size, forward)
	for i in points.size():
		points[i] += position
	UIArt.draw_outlined_polygon(canvas, points, Palette.damage_color(damage_type), Palette.ARENA_EDGE, 1.0)

## Impact flash geometry. `progress` is 0 at the tick the hit lands, 1 at the
## end of its own short on-screen life (a fraction of a second -- callers own
## the actual duration, same split BattleView's DamageFloater already uses
## between "how long" and "what it looks like at time t").
static func impact_flash_radius(base_radius: float, progress: float) -> float:
	return base_radius * lerpf(0.4, 1.8, clampf(progress, 0.0, 1.0))

static func impact_flash_alpha(progress: float) -> float:
	return lerpf(0.9, 0.0, clampf(progress, 0.0, 1.0))

## A brief coloured ring expanding and fading at the moment a hit lands --
## the piece melee attacks had nothing of before this file. Ring rather than
## a filled burst so it reads as an event (something just happened here)
## rather than as a new solid object sitting on the arena.
static func draw_impact_flash(canvas: CanvasItem, position: Vector2, base_radius: float, damage_type: CG.DamageType, progress: float) -> void:
	var alpha := impact_flash_alpha(progress)
	if alpha <= 0.0:
		return
	var color := Palette.damage_color(damage_type)
	color.a = alpha
	canvas.draw_arc(position, impact_flash_radius(base_radius, progress), 0.0, TAU, 20, color, 3.0, true)
