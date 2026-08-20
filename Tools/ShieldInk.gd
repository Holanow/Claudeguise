extends Node

## Issue 315: **where does the drawn shield actually put ink, and is it as wide
## as the simulation says it is?**
##
##   godot --path . --resolution 1280x720 res://Tools/ShieldInk.tscn
##
## Measured by difference: one frame with SHIELDING up, one with it down and
## nothing else touched, so every changed pixel is the plate and only the plate.
## OWNER: sable. Not part of the game and not part of the gate.

const OUT_DIR := "res://Screenshots"
const SEED := 7

var _view: Node2D = null
var _shielder_id := -1

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("ShieldInk: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	await _run()
	get_tree().quit(0)

func _party() -> Array[PawnData]:
	var party: Array[PawnData] = []
	var class_ids := Registry.all_class_ids()
	for i in mini(4, class_ids.size()):
		party.append(PawnFactory.make_starter_pawn(class_ids[i], StringName("p%d" % i), String(class_ids[i])))
	return party

func _frame() -> Image:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()

func _set_shield(up: bool) -> void:
	var u: CombatUnit = _view.state.unit(_shielder_id)
	if up:
		u.statuses[CG.Status.SHIELDING] = 999
	else:
		u.statuses.erase(CG.Status.SHIELDING)
	_view._unit_views[_shielder_id].queue_redraw()
	await get_tree().process_frame

## Pixels that differ between two frames, as a list of screen positions.
func _changed(a: Image, b: Image) -> PackedVector2Array:
	var out := PackedVector2Array()
	for y in a.get_height():
		for x in a.get_width():
			var d := a.get_pixel(x, y) - b.get_pixel(x, y)
			if absf(d.r) + absf(d.g) + absf(d.b) > 0.02:
				out.append(Vector2(x, y))
	return out

func _run() -> void:
	var packed: PackedScene = load("res://Scenes/Battle.tscn")
	_view = packed.instantiate()
	add_child(_view)
	await get_tree().process_frame
	_view.set_process(false)
	_view.state = CombatSim.build(_party(), Registry.get_encounter(Registry.all_encounter_ids()[0]), SEED)
	_view.event_cursor = 0

	# A few ticks so the pawns have a facing: a shielder with none blocks
	# nothing, and the drawing says so by not appearing.
	for i in 20:
		_view._process(CG.TICK_SECONDS)
	await get_tree().process_frame

	var shielder: CombatUnit = null
	for candidate in _view.state.living(CG.Team.PLAYER):
		var c: CombatUnit = candidate
		if c.facing != Vector2.ZERO:
			shielder = c
			break
	if shielder == null:
		print("ShieldInk: no player unit has a facing yet; nothing to measure")
		return
	_shielder_id = shielder.id

	await _set_shield(true)
	var up := await _frame()
	await _set_shield(false)
	var down := await _frame()
	var control := await _frame()

	var scale: float = _view.get_node("Arena").scale.x
	var origin: Vector2 = _view._unit_views[_shielder_id].get_global_transform_with_canvas().origin
	var facing: Vector2 = shielder.facing.normalized()
	var perp := Vector2(-facing.y, facing.x)

	var ink := _changed(up, down)
	var quiet := _changed(down, control)
	var across := Vector2(INF, -INF)
	var along := Vector2(INF, -INF)
	for p in ink:
		var rel := (p - origin) / scale
		var a := rel.dot(perp)
		var f := rel.dot(facing)
		across = Vector2(minf(across.x, a), maxf(across.y, a))
		along = Vector2(minf(along.x, f), maxf(along.y, f))

	print("ShieldInk: unit %d, facing %s, arena scale %.3f" % [_shielder_id, facing, scale])
	print("  inked pixels with SHIELDING up   %d" % ink.size())
	print("  inked pixels with SHIELDING down %d   (0 = the plate goes when the status goes)" % quiet.size())
	print("  frontage across facing  %.1f .. %.1f world units, span %.1f" % [
		across.x, across.y, across.y - across.x])
	print("  simulation's own band   %.1f .. %.1f, span %.1f  (2 x CombatSim.SHIELD_WIDTH)" % [
		-CombatSim.SHIELD_WIDTH, CombatSim.SHIELD_WIDTH, CombatSim.SHIELD_WIDTH * 2.0])
	print("  reach along facing      %.1f .. %.1f world units  (both positive = it is in front)" % [
		along.x, along.y])

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	up.save_png("%s/sable_315_shield_up.png" % OUT_DIR)
	down.save_png("%s/sable_315_shield_down.png" % OUT_DIR)
	var mask := Image.create(up.get_width(), up.get_height(), false, up.get_format())
	mask.fill(Color.BLACK)
	for p in ink:
		mask.set_pixel(int(p.x), int(p.y), Color.WHITE)
	mask.save_png("%s/sable_315_shield_ink.png" % OUT_DIR)
	print("ShieldInk: wrote sable_315_shield_up.png, _down.png, _ink.png")
