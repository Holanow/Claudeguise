extends "res://Tests/TestCase.gd"

## Issue 690. A rotated part must pivot about its own drawn centroid rather
## than about the canvas centre it shares with the rest of the body. Per #280
## this reads real baked pixels rather than an offset formula, replicating
## `Sprite2D`'s own draw transform over every opaque source pixel, headless.

## Where one opaque source pixel of `sprite`'s texture actually lands, in the
## space `sprite`'s parent draws into. Mirrors Sprite2D's own placement: a
## `centered` sprite's local rect starts at `-size/2`, `offset` shifts it
## before the node's own transform (rotation, scale, position) is applied.
static func _drawn_point(sprite: Sprite2D, tex_px: Vector2) -> Vector2:
	var size := Vector2(sprite.texture.get_width(), sprite.texture.get_height())
	var local := tex_px - size * 0.5 + sprite.offset
	return sprite.transform * local

## Every opaque pixel of every sprite in `slot`, in the slot node's own parent
## space -- one coordinate system for both slots being compared.
static func _opaque_points(visual: UnitVisual, slot: StringName) -> PackedVector2Array:
	var out := PackedVector2Array()
	var node: Node2D = visual._slots[slot]
	for sprite in node.get_children():
		var image := (sprite as Sprite2D).texture.get_image()
		for y in image.get_height():
			for x in image.get_width():
				if image.get_pixel(x, y).a > 0.0:
					out.append(node.transform * _drawn_point(sprite, Vector2(x, y)))
	return out

static func _centroid(points: PackedVector2Array) -> Vector2:
	var sum := Vector2.ZERO
	for p in points:
		sum += p
	return sum / float(points.size())

static func _bounds(points: PackedVector2Array) -> Rect2:
	var r := Rect2(points[0], Vector2.ZERO)
	for p in points:
		r = r.expand(p)
	return r

## The closest distance between any point of `a` and any point of `b`, by a
## grid bucket rather than the O(n*m) brute force -- a bounding-box overlap is
## not enough: a long thin blade's box can swallow the hand's box while the
## actual line drawn never comes near it.
static func _nearest_gap(a: PackedVector2Array, b: PackedVector2Array, cell: float) -> float:
	var grid := {}
	for p in a:
		var key := Vector2i(floori(p.x / cell), floori(p.y / cell))
		if not grid.has(key):
			grid[key] = PackedVector2Array()
		grid[key].append(p)
	var best := INF
	for p in b:
		var base := Vector2i(floori(p.x / cell), floori(p.y / cell))
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var key := base + Vector2i(dx, dy)
				if grid.has(key):
					for q in grid[key]:
						best = minf(best, p.distance_to(q))
	return best

## The hand does not orbit the body: its own drawn centroid at a wide swing
## angle must stay close to where it sat at rest. Unfixed, `hand_wide`'s
## centroid sits ~17 drawn units from the canvas centre at this radius, so a
## 75-degree rotation about that canvas centre displaces it by roughly
## `2 * 17 * sin(37.5deg)` =~ 21 units; a part rotating about its own centroid
## does not move at all.
func test_the_hand_does_not_orbit_the_body() -> void:
	var visual := in_tree(UnitVisual.new())
	visual.build(&"sellsword", CG.Team.ENEMY, 22.5, &"sword")
	var at_rest := _centroid(_opaque_points(visual, &"HandMain"))
	visual.rotate_slot(&"HandMain", deg_to_rad(75.0))
	var swung := _centroid(_opaque_points(visual, &"HandMain"))
	assert_true(at_rest.distance_to(swung) < 2.0,
		"the hand's own drawn centroid moved %.1f units under its own rotation" %
			at_rest.distance_to(swung))

## The blade must sit in the hand at rest and at the Crescent's 75-degree
## wind-back alike. This is the "one arm, one pivot" half: even a hand that
## does not orbit its body can still lose its weapon if the weapon pivots
## about its OWN centroid (up the blade) rather than the hand's.
func test_the_blade_stays_by_the_hand_through_the_full_swing() -> void:
	var visual := in_tree(UnitVisual.new())
	visual.build(&"sellsword", CG.Team.ENEMY, 22.5, &"sword")
	for angle_deg in [0.0, 25.0, 50.0, 75.0]:
		visual.rotate_slot(&"HandMain", deg_to_rad(angle_deg))
		visual.rotate_slot(&"Weapon", deg_to_rad(angle_deg))
		var hand := _opaque_points(visual, &"HandMain")
		var blade := _opaque_points(visual, &"Weapon")
		var gap := _nearest_gap(hand, blade, 2.0)
		assert_true(gap < 1.0,
			"at %d degrees the nearest hand-to-blade pixel gap is %.2f drawn units" %
				[angle_deg, gap])

## The negative case: two parts that do NOT share a wielder must be free to
## sit apart, or the gap check above would pass on any two parts at all.
func test_unrelated_parts_are_not_forced_together() -> void:
	var visual := in_tree(UnitVisual.new())
	visual.build(&"sellsword", CG.Team.ENEMY, 22.5, &"sword")
	var head := _bounds(_opaque_points(visual, &"Head"))
	var off_hand := _bounds(_opaque_points(visual, &"HandOff"))
	assert_false(head.intersects(off_hand),
		"the head and the off hand should not overlap; this test measures nothing")
