extends SceneTree

## Issue 572. Writes the in-flight projectile marks to `Assets/UI/projectile/`.
##
## Run once, commit the output. `AttackFX._PROJECTILE_SHAPES` stays as the
## AUTHORING source -- the same relationship `BakeParts.gd` has with the part
## sprites -- and stops being what the game draws every frame.

const OUT_DIR := "res://Assets/UI/projectile"

## The player, on #566's canvas: a 256 px source drawn at 5 px is a sharp 5 px
## mark. Sharper, not bigger.
const N := 256

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var written := 0
	for dt in AttackFX.damage_types():
		var name := AttackFX.projectile_art_name(dt)
		var img := _bake(dt)
		var used := img.get_used_rect()
		if used.size.x <= 0 or used.size.y <= 0:
			printerr("BakeProjectiles: '%s' puts no ink on the canvas" % name)
			continue
		img.save_png("res://Assets/UI/%s.png" % name)
		written += 1
		print("  %-24s ink %d x %d of %d" % [String(name), used.size.x, used.size.y, N])
	print("BakeProjectiles: %d mark(s) at %dx%d written to %s" % [written, N, N, OUT_DIR])
	quit(0)

## The mark for one damage type: the authored polygon filled in its damage
## colour, with the same outline `draw_outlined_polygon` used to stroke on it.
func _bake(dt: CG.DamageType) -> Image:
	var points := AttackFX.projectile_points(dt, 1.0, Vector2.RIGHT)
	var fill := Palette.damage_color(dt)
	var half := AttackFX.PROJECTILE_OUTLINE_WIDTH * 0.5
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in N:
		for x in N:
			var p := _at(x, y)
			var d := _distance_to_edge(points, p)
			if d <= half:
				img.set_pixel(x, y, Palette.ARENA_EDGE)
			elif _inside(points, p):
				img.set_pixel(x, y, fill)
	return img

## One pixel's centre, in the local units the shapes are authored in.
func _at(x: int, y: int) -> Vector2:
	var span := AttackFX.PROJECTILE_ART_SPAN
	return Vector2(
		((float(x) + 0.5) / float(N)) * span * 2.0 - span,
		((float(y) + 0.5) / float(N)) * span * 2.0 - span)

func _inside(points: PackedVector2Array, p: Vector2) -> bool:
	var hit := false
	var j := points.size() - 1
	for i in points.size():
		var a := points[i]
		var b := points[j]
		if (a.y > p.y) != (b.y > p.y):
			var t := (p.y - a.y) / (b.y - a.y)
			if p.x < a.x + t * (b.x - a.x):
				hit = not hit
		j = i
	return hit

func _distance_to_edge(points: PackedVector2Array, p: Vector2) -> float:
	var best := INF
	var j := points.size() - 1
	for i in points.size():
		best = minf(best, _distance_to_segment(p, points[j], points[i]))
		j = i
	return best

func _distance_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq <= 0.000001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)
