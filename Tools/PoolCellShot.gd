extends Node2D

## Issue 625: what a pool looks like once it is cells instead of a rectangle.
## The one irreversible aesthetic change in that issue, so it gets a picture
## before anything is built on top of it.

## The two authored pool radii in the game: `geyser_spout` and `geyser_blast`.
const RADII := [25.0, 50.0]

## 20 is the proposal. 15 and 30 are the neighbours that also divide the arena
## (960 x 540) and `ArenaFloor.GRID_SPACING` exactly. 25, which issue 625
## named, divides neither and is drawn anyway so the reason is visible.
const SIZES := [15.0, 20.0, 25.0, 30.0]

const OUT := "res://Screenshots/teal_625_pool_cell_sizes.png"
const PANEL := Vector2(300.0, 170.0)

func _ready() -> void:
	Offscreen.hide_window(self)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(1280, 720)), Palette.ARENA_FLOOR)
	for row in RADII.size():
		for col in SIZES.size():
			_panel(Vector2(20.0 + col * PANEL.x, 40.0 + row * (PANEL.y + 150.0)),
				RADII[row], SIZES[col])

func _panel(origin: Vector2, radius: float, cell: float) -> void:
	var centre := origin + PANEL * 0.5
	var water := Palette.damage_color(CG.DamageType.WATER)
	water.a = 0.45

	var faint := Palette.ARENA_EDGE
	faint.a = 0.16
	var g := -PANEL.x * 0.5
	while g <= PANEL.x * 0.5:
		draw_line(centre + Vector2(g, -PANEL.y * 0.5), centre + Vector2(g, PANEL.y * 0.5), faint, 1.0)
		g += cell
	g = -PANEL.y * 0.5
	while g <= PANEL.y * 0.5:
		draw_line(centre + Vector2(-PANEL.x * 0.5, g), centre + Vector2(PANEL.x * 0.5, g), faint, 1.0)
		g += cell

	for c in _cells(centre, radius, cell):
		draw_rect(Rect2(Vector2(c) * cell, Vector2(cell, cell)), water)

	## The float circle it replaces, so the ground gained and lost is visible
	## rather than described.
	draw_arc(centre, radius, 0.0, TAU, 48, Palette.TEXT_DIM, 1.5, true)

	## A pawn, to the same scale, because "chunky" only means anything against
	## the thing that walks on it.
	draw_circle(centre + Vector2(0.0, PANEL.y * 0.5 - 24.0), 22.0, Palette.TEXT_DIM)

	draw_string(ThemeDB.fallback_font, origin + Vector2(8.0, -10.0),
		"cell %d   pool r=%d   %d cells" % [
			int(cell), int(radius), _cells(centre, radius, cell).size()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Palette.TEXT_DIM)

## `TerrainGrid.cells_in_circle` with the cell size lifted out, so one picture
## can show four of them. Keep the two in step.
func _cells(centre: Vector2, radius: float, cell: float) -> Array:
	var out: Array = []
	var lo := Vector2i(floori((centre.x - radius) / cell), floori((centre.y - radius) / cell))
	var hi := Vector2i(floori((centre.x + radius) / cell), floori((centre.y + radius) / cell))
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var mid := Vector2(x * cell + cell * 0.5, y * cell + cell * 0.5)
			if mid.distance_to(centre) <= radius:
				out.append(Vector2i(x, y))
	return out

func _process(_delta: float) -> void:
	set_process(false)
	queue_redraw()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT)
	print("wrote ", OUT)
	get_tree().quit(0)
