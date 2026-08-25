extends Node

## Issue 562: is the drag visible? A hook is found in a real fight, and the
## dragged body is then rendered four frames to the tick for the whole pull,
## with the drawn position printed for every frame. A snap is one jump and
## repeats either side of it; a drag is a new position on nearly every frame.

const OUT_DIR := "res://Screenshots"
const SEED := 7
## A 60Hz display against a 15Hz simulation, the ratio #501 is about.
const FRAMES_PER_TICK := 4
const CROP := Vector2i(192, 108)
const ZOOM := 4
const ScreenSweepScript := preload("res://Tools/ScreenSweep.gd")

var _view: Node2D = null
var _encounter_id: StringName = &""

## The sweep's own answer, and the point of the change: how close the longest
## drag step gets to the limit past which `BattleView._tween_body` stops
## interpolating, over every hook in every room.
var _hooks := 0
var _worst := 0.0
var _worst_at_one_tick := 0.0

func _ready() -> void:
	Offscreen.hide_window(self)
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("HookDragShot: refusing to run in the main checkout -- use a worktree.")
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
	return Registry.get_encounter(_encounter_id)

## The hook whose target is dragged furthest, over every room and every party
## that can throw one. The first hook is not the one to draw: a pull into a wall
## stops where `_sweep` stops it, which is correct and shows nothing.
func _longest_drag() -> Dictionary:
	var best := {"tick": -1, "id": -1, "party": [], "encounter": &"", "moved": 0.0}
	for encounter_id in Registry.all_encounter_ids():
		for party_ids in ScreenSweepScript.sweep_parties(Registry.all_class_ids()):
			if not party_ids.has(&"abomination"):
				continue
			var state := CombatSim.build(_party(party_ids), Registry.get_encounter(encounter_id), SEED)
			var dragging := {}
			while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
				CombatSim.step(state)
				for u in state.units:
					if u.pull_ticks_left == CombatSim.PULL_TICKS - 1:
						dragging[u.id] = {"tick": state.tick, "from": u.position}
					elif u.pull_ticks_left == 0 and dragging.has(u.id):
						var run: Dictionary = dragging[u.id]
						var moved: float = u.position.distance_to(run["from"])
						_hooks += 1
						var limit: float = u.move_speed * 3.0 + UnitView.display_radius(u) * 3.0
						_worst = maxf(_worst, moved / float(CombatSim.PULL_TICKS) / limit)
						_worst_at_one_tick = maxf(_worst_at_one_tick, moved / limit)
						if moved > best["moved"]:
							best = {"tick": run["tick"], "id": u.id, "party": party_ids,
								"encounter": encounter_id, "moved": moved}
						dragging.erase(u.id)
	if best["id"] < 0:
		print("HookDragShot: no hook landed anywhere. Nothing to show.")
		return best
	print("HookDragShot: %d hooks landed. Longest step is %.2f of the target's own interpolation limit; at one tick it would have been %.2f." % [
		_hooks, _worst, _worst_at_one_tick])
	_encounter_id = best["encounter"]
	print("HookDragShot: %s, party %s, unit %d hooked on tick %d and dragged %.1f units" % [
		String(best["encounter"]), ", ".join(PackedStringArray(best["party"])),
		best["id"], best["tick"], best["moved"]])
	return best

## Started the way the game starts one, per InterpShot's own note: setting
## `state` by hand leaves `_text_layer` null and every stepped frame then dies.
func _build_view(party_ids: Array) -> void:
	var cfg := RunConfig.new()
	cfg.party = _party(party_ids)
	cfg.encounter_id = _encounter_id
	cfg.seed = SEED
	var packed: PackedScene = load("res://Scenes/Battle.tscn")
	_view = packed.instantiate()
	add_child(_view)
	await get_tree().process_frame
	_view.begin_with_encounter(cfg, _encounter())
	_view.set_process(false)

func _frame() -> void:
	_view._process(CG.TICK_SECONDS / float(FRAMES_PER_TICK))

func _panel(centre: Vector2) -> Image:
	await RenderingServer.frame_post_draw
	var full := get_viewport().get_texture().get_image()
	var origin := Vector2i(centre) - CROP / 2
	origin = origin.clamp(Vector2i.ZERO, full.get_size() - CROP)
	var panel := full.get_region(Rect2i(origin, CROP))
	panel.resize(CROP.x * ZOOM, CROP.y * ZOOM, Image.INTERPOLATE_NEAREST)
	return panel

func _run() -> void:
	var hook := _longest_drag()
	if hook["id"] < 0:
		return
	await _build_view(hook["party"])
	while _view.state.tick < int(hook["tick"]) - 1:
		_frame()
	await get_tree().process_frame

	var body: Node2D = _view._unit_views[hook["id"]]
	var centre: Vector2 = body.get_global_transform_with_canvas().origin
	var panels: Array[Image] = []
	var last := Vector2.INF
	var distinct := 0
	var biggest := 0.0
	var frames := FRAMES_PER_TICK * (CombatSim.PULL_TICKS + 2)
	var was_at := Vector2.INF
	var snaps := 0
	for i in frames:
		var at := body.position
		var moved := 0.0 if last == Vector2.INF else at.distance_to(last)
		if at != last:
			distinct += 1
		biggest = maxf(biggest, moved)
		var u: CombatUnit = _view.state.unit(hook["id"])
		## The interpolator's own rule, asked rather than retyped: a step longer
		## than this is drawn as a jump, which is the defect this issue is about.
		var limit: float = u.move_speed * 3.0 + UnitView.display_radius(u) * 3.0
		var sim_step := 0.0 if was_at == Vector2.INF else u.position.distance_to(was_at)
		if u.position != was_at:
			if sim_step > limit:
				snaps += 1
			print("  tick %d  sim step %.2f  limit %.2f  %s" % [
				_view.state.tick, sim_step, limit, "SNAP" if sim_step > limit else "slides"])
		was_at = u.position
		print("  frame %2d  tick %d  drawn %.2f, %.2f  moved %.2f  stunned %s" % [
			i, _view.state.tick, at.x, at.y, moved, u.has_status(CG.Status.STUN)])
		last = at
		if i % FRAMES_PER_TICK == 0:
			panels.append(await _panel(centre))
		_frame()
		await get_tree().process_frame
	print("  %d of %d frames are a new position; the largest single frame's move is %.2f" % [
		distinct, frames, biggest])
	print("  %d of the drag's steps were too long for the view to interpolate" % snaps)

	var strip := Image.create(CROP.x * ZOOM * panels.size(), CROP.y * ZOOM, false, panels[0].get_format())
	for i in panels.size():
		strip.blit_rect(panels[i], Rect2i(Vector2i.ZERO, panels[i].get_size()), Vector2i(i * CROP.x * ZOOM, 0))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := "%s/teal_562_hook_drag.png" % OUT_DIR
	strip.save_png(path)
	print("HookDragShot: %s" % path)
