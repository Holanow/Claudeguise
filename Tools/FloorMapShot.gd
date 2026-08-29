extends SceneTree


## Issue 804: a picture of the scatter. Renders a few generated floors as grid
## maps into one PNG so the layouts can be eyeballed rather than read out of a
## `neighbours_of` dump.
##
##   godot --headless --script Tools/FloorMapShot.gd -- 1 2 3 4 5 6
##
## Pure `Image` work, no viewport and no scene, so it cannot hang on art.

const CELL := 34
const GAP := 6
const PAD := 12
const COLUMNS := 3

const BACKGROUND := Color(0.09, 0.09, 0.12)
const ORDINARY := Color(0.42, 0.46, 0.55)
const ENTRANCE := Color(0.35, 0.72, 0.45)
const MINIBOSS := Color(0.85, 0.65, 0.25)
const BOSS := Color(0.80, 0.28, 0.28)
const DOOR := Color(0.70, 0.72, 0.78)

func _init() -> void:
	var seeds: Array[int] = []
	for a in OS.get_cmdline_user_args():
		seeds.append(int(a))
	if seeds.is_empty():
		seeds = [1, 2, 3, 4, 5, 6]

	var plans: Array[FloorPlan] = []
	for s in seeds:
		plans.append(FloorGenerator.generate(s))

	var tile := _tile_size(plans)
	var rows := int(ceil(float(plans.size()) / COLUMNS))
	var img := Image.create(COLUMNS * tile.x, rows * tile.y, false, Image.FORMAT_RGBA8)
	img.fill(BACKGROUND)
	for i in plans.size():
		var origin := Vector2i(i % COLUMNS, i / COLUMNS) * tile
		_draw_plan(img, plans[i], origin, tile)

	var out := "res://Screenshots/wren_804_floor_scatter.png"
	img.save_png(ProjectSettings.globalize_path(out))
	print("FloorMapShot: seeds %s -> %s (%dx%d)" % [seeds, out, img.get_width(), img.get_height()])
	quit()

## One tile per floor, big enough for the widest and tallest floor in the set,
## so every map is drawn at the same scale and they can be compared.
func _tile_size(plans: Array[FloorPlan]) -> Vector2i:
	var span := Vector2i.ONE
	for plan in plans:
		span = span.max(_bounds(plan).size + Vector2i.ONE)
	return span * (CELL + GAP) + Vector2i.ONE * (PAD * 2)

func _bounds(plan: FloorPlan) -> Rect2i:
	var r := Rect2i(plan.rooms[0].cell, Vector2i.ZERO)
	for room in plan.rooms:
		r = r.expand(room.cell)
	return r

func _draw_plan(img: Image, plan: FloorPlan, origin: Vector2i, tile: Vector2i) -> void:
	var bounds := _bounds(plan)
	var span := (bounds.size + Vector2i.ONE) * (CELL + GAP)
	var offset := origin + (tile - span) / 2

	for room in plan.rooms:
		var at := offset + (room.cell - bounds.position) * (CELL + GAP)
		img.fill_rect(Rect2i(at, Vector2i(CELL, CELL)), _colour(plan, room))
		## A door is drawn only in the gap between two cells that are actually
		## neighbours, so a map with a missing corridor is visibly wrong.
		for e in plan.exits_of(room.id):
			var dir: Vector2i = e["dir"]
			if dir.x < 0 or dir.y < 0:
				continue
			var door := at + dir * CELL + Vector2i(dir.y, dir.x) * (CELL / 2 - 2)
			img.fill_rect(Rect2i(door, Vector2i(dir.x * GAP + dir.y * 4, dir.y * GAP + dir.x * 4)), DOOR)

func _colour(plan: FloorPlan, room: FloorRoom) -> Color:
	if room.id == plan.boss_id:
		return BOSS
	if room.id == plan.miniboss_id:
		return MINIBOSS
	if room.id == plan.entrance_id:
		return ENTRANCE
	return ORDINARY
