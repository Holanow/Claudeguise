extends Node

## Issues 315 and 332: **where does the drawn shield put ink, and does it hide
## the units it is supposed to be sheltering?**
##
##   godot --path . --resolution 1280x720 res://Tools/ShieldInk.tscn
##
## Measured by difference against the same frame with SHIELDING taken away, so
## every changed pixel is the plate and only the plate.
## OWNER: sable. Not part of the game and not part of the gate.

const OUT_DIR := "res://Screenshots"
const SEED := 7

## The party is named, never an alphabetical prefix of the roster. Issue 350:
## `all_class_ids()` sorts, so `mini(4, ...)` could not select the Warrior and
## this instrument could not photograph the one class the shield belongs to.
const PARTY := [&"warrior", &"priest", &"geysermancer", &"abomination"]

var _view: Node2D = null
var _shielder_id := -1
var _tag := "before"

## `last` moves the shielder's own node to the end of the arena's child order.
## A plate drawn inside a UnitView covers exactly the units drawn before it, so
## a Warrior -- always party slot 0, always the first child -- covered nobody
## and the defect was invisible on the one class that has the ability. This is
## the position a summoned or later-slot shielder holds, and it is the only
## arrangement in which the old drawing can be falsified.
var _draw_last := false

func _ready() -> void:
	Offscreen.hide_window(self)
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("ShieldInk: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg == "last":
			_draw_last = true
			_tag += "_last"
		else:
			_tag = arg
	await _run()
	get_tree().quit(0)

func _party() -> Array[PawnData]:
	var party: Array[PawnData] = []
	for id in PARTY:
		party.append(PawnFactory.make_starter_pawn(id, StringName("p_%s" % id), String(id)))
	return party

func _frame() -> Image:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()

## Redraws everything the plate can appear in. The plate moved out of `UnitView`
## into the arena layer in #332, so a redraw of the unit alone no longer covers
## it.
func _redraw() -> void:
	_view._arena.units = _view.state.units
	_view._arena.queue_redraw()
	for id in _view._unit_views:
		_view._unit_views[id].queue_redraw()
	await get_tree().process_frame

## Drops the damage numbers and hit flashes the stepped ticks left behind. They
## animate on their own, so two frames of the same state differ and a moving
## picture gets counted as the plate.
func _freeze() -> void:
	var keep: Array = _view._unit_views.values()
	for child in _view._arena.get_children():
		if not keep.has(child):
			_view._arena.remove_child(child)
			child.queue_free()
	await _redraw()
	await get_tree().process_frame

## The comparison frame: SHIELDING stays up, so the badge row, the bars and the
## body are pixel-identical and the only thing that can differ is the plate,
## which draws nothing for a shielder with no facing.
func _set_facing(facing: Vector2) -> void:
	_view.state.unit(_shielder_id).facing = facing
	await _redraw()

## Pixels that differ between two frames, as a list of screen positions.
func _changed(a: Image, b: Image) -> PackedVector2Array:
	var out := PackedVector2Array()
	for y in a.get_height():
		for x in a.get_width():
			var d := a.get_pixel(x, y) - b.get_pixel(x, y)
			if absf(d.r) + absf(d.g) + absf(d.b) > 0.02:
				out.append(Vector2(x, y))
	return out

## The plate, and nothing but the plate. Two frames taken with nothing changed
## give the pixels that move on their own -- pulsing rings, the aim lines -- and
## those are subtracted, so a moving picture cannot be mistaken for cover.
func _plate_ink(up: Image, off: Image, noise: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in _changed(up, off):
		if not noise.has(p):
			out.append(p)
	return out

func _noise(a: Image, b: Image, into: Dictionary) -> Dictionary:
	for p in _changed(a, b):
		into[p] = true
	return into

## The screen-space box the unit's body is drawn into, which is what "the plate
## is painting over that unit" has to be measured against.
func _body_box(u: CombatUnit) -> Rect2:
	var view: Node2D = _view._unit_views[u.id]
	var radius: float = UnitView.display_radius(u)
	var box := UnitView.drawn_box(UnitView.shape_id(u), u.team, radius)
	var scale: float = _view._arena.scale.x
	var origin: Vector2 = view.get_global_transform_with_canvas().origin
	return Rect2(origin + box.position * scale, box.size * scale)

## Exactly which screen pixels a unit puts on the field, taken by hiding its
## node and diffing: a bounding box would count the empty corners of a
## silhouette as covered and the plate would fail a test it had passed.
func _own_pixels(id: int) -> Dictionary:
	var view: Node2D = _view._unit_views[id]
	await _redraw()
	var a := await _frame()
	var b := await _frame()
	view.visible = false
	await _redraw()
	var without := await _frame()
	view.visible = true
	await _redraw()
	var out := {}
	var flicker := _noise(a, b, {})
	for p in _changed(b, without):
		if not flicker.has(p):
			out[p] = true
	return out

## The whole point of the issue: how many of somebody else's drawn pixels the
## plate repaints. Zero is the only acceptable answer.
func _covered(ink: PackedVector2Array) -> Dictionary:
	var plate := {}
	for p in ink:
		plate[p] = true
	var out := {}
	for candidate in _view.state.units:
		var u: CombatUnit = candidate
		if not u.alive or u.id == _shielder_id:
			continue
		var own: Dictionary = await _own_pixels(u.id)
		var n := 0
		for p in own:
			if plate.has(p):
				n += 1
		out[u.id] = n
	return out

## Steps a real fight until the Warrior raises Directional Block of its own
## accord with a crowd around it. No status is held up by hand: the picture the
## issue is about is the one a player sees.
func _find_live_shield() -> bool:
	for i in 2400:
		if _view.state.outcome != CombatState.Outcome.UNRESOLVED:
			break
		_view._process(CG.TICK_SECONDS)
		for candidate in _view.state.living(CG.Team.PLAYER):
			var u: CombatUnit = candidate
			if not ShieldWall.is_up(u):
				continue
			if _crowd(u) < 3:
				continue
			_shielder_id = u.id
			return true
	return false

## Living units, either team, inside the plate's own frontage. A shield with
## nobody near it cannot demonstrate the defect.
func _crowd(shielder: CombatUnit) -> int:
	var n := 0
	for candidate in _view.state.units:
		var u: CombatUnit = candidate
		if not u.alive or u.id == shielder.id:
			continue
		if u.position.distance_to(shielder.position) <= CombatSim.SHIELD_WIDTH:
			n += 1
	return n

func _run() -> void:
	var packed: PackedScene = load("res://Scenes/Battle.tscn")
	_view = packed.instantiate()
	add_child(_view)
	await get_tree().process_frame
	_view.set_process(false)
	_view.state = CombatSim.build(_party(), Registry.get_encounter(Registry.all_encounter_ids()[0]), SEED)
	_view.event_cursor = 0
	_view._ensure_unit_views()

	if not _find_live_shield():
		print("ShieldInk: no Warrior raised Directional Block in a crowd; nothing to measure")
		return
	await _freeze()
	if _draw_last:
		_view._arena.move_child(_view._unit_views[_shielder_id], -1)
		await _redraw()

	var shielder: CombatUnit = _view.state.unit(_shielder_id)
	var facing: Vector2 = shielder.facing.normalized()
	var up := await _frame()
	await _redraw()
	var up_again := await _frame()
	await _set_facing(Vector2.ZERO)
	var off := await _frame()
	await _redraw()
	var off_again := await _frame()
	await _set_facing(facing)

	var scale: float = _view._arena.scale.x
	var origin: Vector2 = _view._unit_views[_shielder_id].get_global_transform_with_canvas().origin
	var perp := Vector2(-facing.y, facing.x)
	var noise := _noise(off, off_again, _noise(up, up_again, {}))
	var ink := _plate_ink(up, off, noise)

	var across := Vector2(INF, -INF)
	var along := Vector2(INF, -INF)
	for p in ink:
		var rel := (p - origin) / scale
		across = Vector2(minf(across.x, rel.dot(perp)), maxf(across.y, rel.dot(perp)))
		along = Vector2(minf(along.x, rel.dot(facing)), maxf(along.y, rel.dot(facing)))

	print("ShieldInk [%s]: %s, unit %d, facing %s (%.0f deg), arena scale %.3f" % [
		_tag, shielder.display_name, _shielder_id, facing, rad2deg(facing.angle()), scale])
	print("  crowd within one frontage                                   %d units" % _crowd(shielder))
	print("  plate pixels, vs the same frame with the facing taken away   %d" % ink.size())
	print("  frontage across facing  %.1f .. %.1f world units, span %.1f" % [
		across.x, across.y, across.y - across.x])
	print("  simulation's own band   %.1f .. %.1f, span %.1f  (CombatSim.SHIELD_WIDTH)" % [
		-CombatSim.SHIELD_WIDTH * 0.5, CombatSim.SHIELD_WIDTH * 0.5, CombatSim.SHIELD_WIDTH])
	print("  reach along facing      %.1f .. %.1f world units  (both positive = it is in front)" % [
		along.x, along.y])

	var covered: Dictionary = await _covered(ink)
	var total := 0
	for id in covered:
		total += int(covered[id])
		if int(covered[id]) > 0:
			print("  COVERS unit %d (%s): %d drawn pixels repainted by the plate" % [
				id, _view.state.unit(id).display_name, covered[id]])
	print("  other units' drawn pixels repainted by the plate            %d   (0 = it hides nobody)" % total)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	up.save_png("%s/sable_332_%s_up.png" % [OUT_DIR, _tag])
	off.save_png("%s/sable_332_%s_down.png" % [OUT_DIR, _tag])
	var mask := Image.create(up.get_width(), up.get_height(), false, up.get_format())
	mask.fill(Color.BLACK)
	for p in ink:
		mask.set_pixel(int(p.x), int(p.y), Color.WHITE)
	for id in covered:
		var box := _body_box(_view.state.unit(id))
		_outline(mask, box, Color.RED if int(covered[id]) > 0 else Color.GREEN)
	mask.save_png("%s/sable_332_%s_ink.png" % [OUT_DIR, _tag])
	_zoom(up, origin).save_png("%s/sable_332_%s_zoom.png" % [OUT_DIR, _tag])
	print("ShieldInk: wrote sable_332_%s_up.png, _down.png, _ink.png" % _tag)

const ZOOM := 3
const ZOOM_SIZE := Vector2i(320, 260)

## The plate around the unit holding it, magnified. A 1280-wide frame answers
## "does it cover anybody"; only a crop answers "would a stranger know what
## that is", which is the other half of issue 332.
func _zoom(frame: Image, origin: Vector2) -> Image:
	var at := Vector2i(origin) - ZOOM_SIZE / 2
	var box := Rect2i(at, ZOOM_SIZE).intersection(Rect2i(Vector2i.ZERO, frame.get_size()))
	var crop := frame.get_region(box)
	crop.resize(box.size.x * ZOOM, box.size.y * ZOOM, Image.INTERPOLATE_NEAREST)
	return crop

func rad2deg(r: float) -> float:
	return rad_to_deg(r)

## A one-pixel rectangle on the mask, so the boxes the coverage count uses are
## visible rather than trusted.
func _outline(img: Image, box: Rect2, color: Color) -> void:
	var r := Rect2i(box).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if r.size.x <= 0 or r.size.y <= 0:
		return
	for x in range(r.position.x, r.end.x):
		img.set_pixel(x, r.position.y, color)
		img.set_pixel(x, r.end.y - 1, color)
	for y in range(r.position.y, r.end.y):
		img.set_pixel(r.position.x, y, color)
		img.set_pixel(r.end.x - 1, y, color)
