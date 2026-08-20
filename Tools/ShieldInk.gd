extends Node

## Issue 315: **where does the drawn shield actually put ink, and is it as wide
## as the simulation says it is?**
##
##   godot --path . --resolution 1280x720 res://Tools/ShieldInk.tscn
##
## Measured by difference against the same unit with its facing taken away:
## the status, the badge row and the body are identical in both frames, so
## every changed pixel is the plate and only the plate.
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

## The three states this measures, all rendered through the shipped `_draw`.
## "no facing" keeps the status up, so the status badge, the bars and the body
## are identical to "up" and the only thing that can differ is the plate:
## `UnitView.facing_left` reads the same for a player unit facing right and for
## one facing nowhere.
func _set_state(shielding: bool, facing: Vector2) -> void:
	var u: CombatUnit = _view.state.unit(_shielder_id)
	if shielding:
		u.statuses[CG.Status.SHIELDING] = 999
	else:
		u.statuses.erase(CG.Status.SHIELDING)
	u.facing = facing
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
		if c.facing.x > 0.0:
			shielder = c
			break
	if shielder == null:
		print("ShieldInk: no player unit faces right yet; nothing to measure")
		return
	_shielder_id = shielder.id
	var facing: Vector2 = shielder.facing.normalized()

	await _set_state(true, facing)
	var up := await _frame()
	await _set_state(true, Vector2.ZERO)
	var noface := await _frame()
	await _set_state(false, facing)
	var off := await _frame()
	await _set_state(false, Vector2.ZERO)
	var off_noface := await _frame()

	var scale: float = _view.get_node("Arena").scale.x
	var origin: Vector2 = _view._unit_views[_shielder_id].get_global_transform_with_canvas().origin
	var perp := Vector2(-facing.y, facing.x)

	var ink := _changed(up, noface)

	# The "it is up right now" half, and it cannot be contaminated by the
	# status badge: both these frames have SHIELDING down, so a facing that
	# changes nothing on screen is a shield that is not drawn.
	var quiet := _changed(off, off_noface).size()

	var across := Vector2(INF, -INF)
	var along := Vector2(INF, -INF)
	for p in ink:
		var rel := (p - origin) / scale
		var a := rel.dot(perp)
		var f := rel.dot(facing)
		across = Vector2(minf(across.x, a), maxf(across.y, a))
		along = Vector2(minf(along.x, f), maxf(along.y, f))

	print("ShieldInk: unit %d, facing %s, arena scale %.3f" % [_shielder_id, facing, scale])
	print("  plate pixels, SHIELDING up vs the same unit with no facing   %d" % ink.size())
	print("  pixels facing changes once SHIELDING is gone                %d   (0 = no plate is drawn at all)" % quiet)
	print("  frontage across facing  %.1f .. %.1f world units, span %.1f" % [
		across.x, across.y, across.y - across.x])
	print("  simulation's own band   %.1f .. %.1f, span %.1f  (CombatSim.SHIELD_WIDTH)" % [
		-CombatSim.SHIELD_WIDTH * 0.5, CombatSim.SHIELD_WIDTH * 0.5, CombatSim.SHIELD_WIDTH])
	print("  reach along facing      %.1f .. %.1f world units  (both positive = it is in front)" % [
		along.x, along.y])

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	up.save_png("%s/sable_315_shield_up.png" % OUT_DIR)
	off.save_png("%s/sable_315_shield_down.png" % OUT_DIR)
	var mask := Image.create(up.get_width(), up.get_height(), false, up.get_format())
	mask.fill(Color.BLACK)
	for p in ink:
		mask.set_pixel(int(p.x), int(p.y), Color.WHITE)
	mask.save_png("%s/sable_315_shield_ink.png" % OUT_DIR)
	print("ShieldInk: wrote sable_315_shield_up.png, _down.png, _ink.png")
	await _catch_a_block(facing)

## The picture the issue is actually about: a shot stopped by the plate. The
## status is held up by hand each tick, which is a fixture rather than a fight
## the plans could produce today.
func _catch_a_block(facing: Vector2) -> void:
	var seen: int = _view.state.events.size()
	for i in 1200:
		var u: CombatUnit = _view.state.unit(_shielder_id)
		if u == null or not u.alive:
			break
		u.statuses[CG.Status.SHIELDING] = 999
		u.facing = facing
		_view._process(CG.TICK_SECONDS)
		var blocked := false
		for e in _view.state.events_since(seen):
			if e.kind == CG.EventKind.BLOCKED:
				blocked = true
		seen = _view.state.events.size()
		if not blocked:
			continue
		await get_tree().process_frame
		var shot := await _frame()
		shot.save_png("%s/sable_315_shot_blocked.png" % OUT_DIR)
		print("ShieldInk: a shot was blocked at tick %d; wrote sable_315_shot_blocked.png" % _view.state.tick)
		return
	print("ShieldInk: no BLOCKED event in 1200 ticks with the plate held up")
