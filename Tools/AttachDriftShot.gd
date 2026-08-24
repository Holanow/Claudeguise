extends Node

## Issue 511: does everything a body wears move with the body between ticks?
## Two strips of eight consecutive rendered frames. One of a pawn walking with
## its name plate and, where the fight offers one, a shield plate up. One of a
## unit dying, because a damage number and a death plate are meant to STAY where
## the event happened while the ring on the body does not.
##
## The number is per-band distinct-frame counts, taken off the rendered pixels
## rather than off the geometry that produced them: a check on the geometry
## keeps passing once the geometry stops being what ships (#280).

const OUT_DIR := "res://Screenshots"
const SEED := 7
const FRAMES_PER_TICK := 4
const FRAMES := 8
const CROP := Vector2i(200, 150)
const ZOOM := 4
const RULER := Color(1.0, 0.2, 0.6)
const RULER_WIDTH := 2
const ScreenSweepScript := preload("res://Tools/ScreenSweep.gd")

var _view: Node2D = null

func _ready() -> void:
	Offscreen.hide_window(self)
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("AttachDriftShot: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	await _run()
	get_tree().quit(0)

func _party(party_ids: Array) -> Array[PawnData]:
	var party: Array[PawnData] = []
	for i in party_ids.size():
		party.append(PawnFactory.make_starter_pawn(party_ids[i], StringName("p%d" % i), String(party_ids[i])))
	return party

func _encounter():
	return Registry.get_encounter(Registry.all_encounter_ids()[0])

## Simulation only. The tick at which some named pawn covers the most ground in
## one step, preferring one holding cover: a plate is the widest attachment and
## the easiest drift to see.
func _walk() -> Dictionary:
	var best := {"tick": -1, "id": -1, "moved": 0.0, "party": [], "cover": false}
	for party_ids in ScreenSweepScript.sweep_parties(Registry.all_class_ids()):
		var state := CombatSim.build(_party(party_ids), _encounter(), SEED)
		var was := {}
		while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
			for u in state.units:
				was[u.id] = u.position
			CombatSim.step(state)
			for u in state.units:
				if not u.alive or not was.has(u.id) or u.team != CG.Team.PLAYER:
					continue
				var moved: float = u.position.distance_to(was[u.id])
				var cover := ShieldWall.is_up(u)
				if moved > u.move_speed * 3.0 or state.tick <= FRAMES:
					continue
				# Cover beats distance: a plate that drifts is the loudest case.
				if (cover and not best["cover"]) or (cover == best["cover"] and moved > best["moved"]):
					best = {"tick": state.tick - 1, "id": u.id, "moved": moved,
						"party": party_ids, "cover": cover}
	print("AttachDriftShot: party %s, unit %d walks %.1f units in one tick, cover %s, tick %d" % [
		", ".join(PackedStringArray(best["party"])), best["id"], best["moved"],
		best["cover"], best["tick"]])
	return best

## The first tick a unit dies with somebody still walking nearby, so the strip
## shows a number that should stay put beside a body that should not.
func _kill() -> Dictionary:
	for party_ids in ScreenSweepScript.sweep_parties(Registry.all_class_ids()):
		var state := CombatSim.build(_party(party_ids), _encounter(), SEED)
		var cursor := 0
		while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
			CombatSim.step(state)
			for e in state.events_since(cursor):
				if e.kind == CG.EventKind.DEATH and state.tick > FRAMES:
					print("AttachDriftShot: unit %d dies at tick %d, party %s" % [
						e.target_id, state.tick, ", ".join(PackedStringArray(party_ids))])
					return {"tick": state.tick - 1, "id": e.target_id, "party": party_ids}
			cursor = state.events.size()
	return {}

## Started the way the game starts one, so `_text_layer` exists (#512).
func _build_view(party_ids: Array) -> void:
	var cfg := RunConfig.new()
	cfg.party = _party(party_ids)
	cfg.encounter_id = Registry.all_encounter_ids()[0]
	cfg.seed = SEED
	var packed: PackedScene = load("res://Scenes/Battle.tscn")
	_view = packed.instantiate()
	add_child(_view)
	await get_tree().process_frame
	_view.begin_with_encounter(cfg, _encounter())
	_view.set_process(false)

## The view's own clock, plus every transient's. A ring and a number age on the
## engine's real delta, and the frames this tool draws cost almost no wall clock,
## so left alone forty of them pile up and none of them ever expires.
func _frame() -> void:
	var slice := CG.TICK_SECONDS / float(FRAMES_PER_TICK)
	_view._process(slice)
	for child in _view._arena.get_children():
		if child.is_queued_for_deletion():
			continue
		if child.get_script() == ImpactFlash or child.get_script() == DamageFloater:
			child.set_process(false)
			child._process(slice)

func _shot() -> Image:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()

func _crop(full: Image, centre: Vector2) -> Image:
	var origin := Vector2i(centre) - CROP / 2
	origin = origin.clamp(Vector2i.ZERO, full.get_size() - CROP)
	var panel := full.get_region(Rect2i(origin, CROP))
	panel.resize(CROP.x * ZOOM, CROP.y * ZOOM, Image.INTERPOLATE_NEAREST)
	return panel

## The name plate's chip in screen pixels, grown a little so the tether's foot
## and the chip's own edge are both inside the band being counted.
func _plate_band(full: Image, id: int) -> PackedByteArray:
	var layout: Dictionary = UnitView.plate_layout(_view.state)
	if not layout.has(id):
		return PackedByteArray()
	var xform: Transform2D = _view._arena.get_global_transform_with_canvas()
	var chip: Rect2 = layout[id]
	var rect := Rect2i(xform * chip.position, Vector2i(xform.get_scale() * chip.size))
	rect = rect.grow(12).intersection(Rect2i(Vector2i.ZERO, full.get_size()))
	if rect.size.x <= 0 or rect.size.y <= 0:
		return PackedByteArray()
	return full.get_region(rect).get_data()

## The first tick a shielder holds cover while the scrum is nudging its drawn
## body off its simulated one. That gap is where the plate's anchor is wrong:
## `ShieldWall.draw_all` read `u.position`, which no body is drawn at.
func _cover() -> Dictionary:
	for party_ids in ScreenSweepScript.sweep_parties(Registry.all_class_ids()):
		var state := CombatSim.build(_party(party_ids), _encounter(), SEED)
		while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
			CombatSim.step(state)
			if state.tick <= FRAMES:
				continue
			for u in state.units:
				if not ShieldWall.is_up(u):
					continue
				var nudge := UnitView.visual_offset(u, state.units).length()
				if nudge < 4.0:
					continue
				print("AttachDriftShot: unit %d holds cover at tick %d, scrum nudge %.1f, party %s" % [
					u.id, state.tick, nudge, ", ".join(PackedStringArray(party_ids))])
				return {"tick": state.tick - 1, "id": u.id, "party": party_ids}
	print("AttachDriftShot: no shielder was ever nudged by the scrum; no cover strip")
	return {}

## Where the shield plate is actually drawn, read out of the same field
## `ArenaFloor._draw` passes to `ShieldWall.draw_all`. A version without that
## field draws at the simulated position, which is the defect.
func _cover_anchor(u: CombatUnit) -> Vector2:
	if "unit_positions" in _view._arena:
		return _view._arena.unit_positions.get(u.id, u.position)
	return u.position

func _run() -> void:
	await _drift_strip(_walk(), "drift")
	await _drift_strip(_cover(), "cover")
	await _kill_strip(_kill())

func _save(panels: Array[Image], stem: String) -> void:
	var strip := Image.create(CROP.x * ZOOM * panels.size(), CROP.y * ZOOM, false, panels[0].get_format())
	for i in panels.size():
		strip.blit_rect(panels[i], Rect2i(Vector2i.ZERO, panels[i].get_size()), Vector2i(i * CROP.x * ZOOM, 0))
		strip.fill_rect(Rect2i((i * CROP.x + CROP.x / 2) * ZOOM, 0, RULER_WIDTH, CROP.y * ZOOM), RULER)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var prefix := OS.get_environment("DRIFT_SHOT_NAME")
	if prefix == "":
		prefix = "sable_511"
	var path := "%s/%s_%s.png" % [OUT_DIR, prefix, stem]
	strip.save_png(path)
	print("AttachDriftShot: %s" % path)

func _teardown() -> void:
	_view.queue_free()
	_view = null
	await get_tree().process_frame

func _drift_strip(walk: Dictionary, stem: String) -> void:
	if walk.is_empty() or walk["id"] < 0:
		return
	await _build_view(walk["party"])
	while _view.state.tick < walk["tick"]:
		_frame()
	await get_tree().process_frame

	var id: int = walk["id"]
	var body: Node2D = _view._unit_views[id]
	var centre: Vector2 = body.get_global_transform_with_canvas().origin
	var panels: Array[Image] = []
	var last_body := Vector2.INF
	var last_plate := PackedByteArray()
	var moved_body := 0
	var moved_plate := 0
	for i in FRAMES:
		var full := await _shot()
		var plate := _plate_band(full, id)
		if body.position != last_body:
			moved_body += 1
		if plate != last_plate:
			moved_plate += 1
		var u := _view.state.unit(id)
		print("  frame %d  tick %d  body %.2f, %.2f  plate anchor %.2f, %.2f  gap %.2f" % [
			i, _view.state.tick, body.position.x, body.position.y,
			_cover_anchor(u).x, _cover_anchor(u).y, _cover_anchor(u).distance_to(body.position)])
		last_body = body.position
		last_plate = plate
		panels.append(_crop(full, centre))
		_frame()
		await get_tree().process_frame
	print("  body: %d of %d frames are a new position" % [moved_body, FRAMES])
	print("  name plate: %d of %d frames are a new picture" % [moved_plate, FRAMES])
	_save(panels, stem)
	await _teardown()

func _kill_strip(kill: Dictionary) -> void:
	if kill.is_empty():
		return
	await _build_view(kill["party"])
	while _view.state.tick < kill["tick"]:
		_frame()
	await get_tree().process_frame

	var id: int = kill["id"]
	var body: Node2D = _view._unit_views[id]
	var centre: Vector2 = body.get_global_transform_with_canvas().origin
	var panels: Array[Image] = []
	for i in FRAMES:
		var full := await _shot()
		print("  frame %d  tick %d  body %.1f, %.1f %s %s" % [
			i, _view.state.tick, body.position.x, body.position.y,
			"alive" if body.visible else "DEAD", _marks(id)])
		panels.append(_crop(full, centre))
		_frame()
		await get_tree().process_frame
	_save(panels, "kill")
	await _teardown()

## The ring on one named unit and the transients nearest it: whether the ring
## still holds a body, and where the number and the death plate sit.
func _marks(id: int) -> String:
	var body: Node2D = _view._unit_views[id]
	var out := ""
	for child in _view._arena.get_children():
		if child.is_queued_for_deletion():
			continue
		if child.get_script() == ImpactFlash and child.position.distance_to(body.position) < 60.0:
			out += " ring@%.1f,%.1f %s" % [child.position.x, child.position.y,
				"following" if child._follow != null else "LET GO"]
		elif child.get_script() == DamageFloater and child.position.distance_to(body.position) < 90.0:
			out += " %s@%.1f,%.1f" % ["plate" if child.death_marker else "number",
				child.position.x, child.position.y]
	return out
