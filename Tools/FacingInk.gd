extends Node2D


## Issue 241. **Where does `draw_unit` actually put ink, per facing?**
##
##   godot --path . --resolution 1280x720 res://Tools/FacingInk.tscn
##
## OWNER: wren. Not part of the game and not part of the gate.

const ORIGIN_Y := 120.0
const ROW_STEP := 200.0
const SHAPES := [
	[&"the_warden", 33.0, CG.Team.ENEMY],
	[&"goblin", 16.5, CG.Team.ENEMY],
	[&"warrior", 33.0, CG.Team.PLAYER],
]
const ORIGIN_X := 320.0

var _drawn := false

func _draw() -> void:
	for i in SHAPES.size():
		var row: Array = SHAPES[i]
		var y := ORIGIN_Y + ROW_STEP * i
		Silhouettes.draw_unit(self, row[0], row[1], row[2], CG.DamageType.PHYSICAL, false,
			Vector2(ORIGIN_X, y))
		Silhouettes.draw_unit(self, row[0], row[1], row[2], CG.DamageType.PHYSICAL, true,
			Vector2(ORIGIN_X * 2.0, y))
	_drawn = true

func _process(_delta: float) -> void:
	if not _drawn:
		return
	set_process(false)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	print("FacingInk: inked columns, origin marked O. right-facing at x=%d, left-facing at x=%d" % [
		int(ORIGIN_X), int(ORIGIN_X * 2.0)])
	for i in SHAPES.size():
		var row: Array = SHAPES[i]
		var y := ORIGIN_Y + ROW_STEP * i
		var r: float = row[1]
		var right := _span(image, y - r, y + r, ORIGIN_X - r * 3.0, ORIGIN_X + r * 3.0)
		var left := _span(image, y - r, y + r, ORIGIN_X * 2.0 - r * 3.0, ORIGIN_X * 2.0 + r * 3.0)
		print("  %-13s r=%4.1f  right-facing ink %6.1f..%6.1f centre %+7.1f from O" % [
			row[0], r, right.x, right.y, (right.x + right.y) * 0.5 - ORIGIN_X])
		print("  %-13s          left-facing  ink %6.1f..%6.1f centre %+7.1f from O" % [
			"", left.x, left.y, (left.x + left.y) * 0.5 - ORIGIN_X * 2.0])
	get_tree().quit(0)

## First and last column in the band that is not the clear colour.
func _span(image: Image, y0: float, y1: float, x0: float, x1: float) -> Vector2:
	var bg := image.get_pixel(int(x0), int(y0))
	var lo := INF
	var hi := -INF
	for x in range(int(x0), int(x1)):
		for y in range(int(y0), int(y1)):
			if image.get_pixel(x, y) != bg:
				lo = minf(lo, float(x))
				hi = maxf(hi, float(x))
				break
	return Vector2(lo, hi)
