extends Node

## Issue 531: does a ranged attacker kick back at the moment it looses? A still
## cannot show a decay, so this is two strips of sixteen consecutive rendered
## frames across one loose -- the same fight, the same tick, the toggle off in
## one and on in the other -- with the recoil offset printed for every frame.
##
## The ruler is blitted onto the captured image at a fixed image coordinate, so
## it cannot ride the body it is measuring.
##
## Then what it costs a WHOLE RENDERED FRAME at 14 and at 100 units, because the
## canvas is rebuilt after `_process` returns.

const OUT_DIR := "res://Screenshots"
const SEED := 7
const FRAMES_PER_TICK := 4
## Four ticks, because RECOIL_SECONDS is 0.18 and a strip shorter than the decay
## cannot show the decay.
const FRAMES := 16
const CROP := Vector2i(150, 130)
const ZOOM := 3
const RULER := Color(1.0, 0.2, 0.6)
const RULER_WIDTH := 2
const COST_FRAMES := 240
const ScreenSweepScript := preload("res://Tools/ScreenSweep.gd")

var _view: Node2D = null

func _ready() -> void:
	Offscreen.hide_window(self)
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("LooseShot: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	await _run()
	get_tree().quit(0)

func _party(party_ids: Array) -> Array[PawnData]:
	var party: Array[PawnData] = []
	for i in party_ids.size():
		party.append(PawnFactory.make_starter_pawn(
			party_ids[i], StringName("p%d" % i), String(party_ids[i])))
	return party

func _encounter():
	return Registry.get_encounter(Registry.all_encounter_ids()[0])

## Simulation only. Every ACTION_FIRE whose action carries a projectile and
## whose shooter still has a focus to kick away from -- exactly the gates
## `BattleView._apply_loose` applies, so the strip photographs a loose the
## shipped code will actually react to.
##
## The BIGGEST shooter wins, not the first. Four pixels off an eleven-pixel
## goblin is an unreadable strip, and that is not evidence of anything (#280).
func _loose() -> Dictionary:
	var best := {}
	var best_size := 0.0
	for party_ids in ScreenSweepScript.sweep_parties(Registry.all_class_ids()):
		var state := CombatSim.build(_party(party_ids), _encounter(), SEED)
		var cursor := 0
		while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
			CombatSim.step(state)
			for e in state.events_since(cursor):
				if e.kind != CG.EventKind.ACTION_FIRE or state.tick <= FRAMES:
					continue
				var action := ActionLibrary.get_action(e.action_id)
				if action == null or action.projectile_speed <= 0.0:
					continue
				var source := state.unit(e.source_id)
				var target := state.unit(e.target_id)
				if source == null or target == null or source.id == target.id:
					continue
				var size := UnitView.drawn_half_width(
					UnitView.shape_id(source), source.team, UnitView.display_radius(source))
				if size <= best_size:
					continue
				best_size = size
				best = {"tick": state.tick - 1, "source": source.id, "target": target.id,
					"party": party_ids, "action": e.action_id}
			cursor = state.events.size()
	if not best.is_empty():
		print("LooseShot: unit %d looses %s at unit %d on tick %d, shooter %.0f px half-width, party %s" % [
			best["source"], best["action"], best["target"], int(best["tick"]) + 1, best_size,
			", ".join(PackedStringArray(best["party"]))])
	return best

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

## The view's clock, plus every transient's -- same reasoning as ImpactShot: a
## ring aged on the engine's real delta never expires in a tool whose frames
## cost no wall clock.
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

func _prefix() -> String:
	var stem := OS.get_environment("LOOSE_SHOT_NAME")
	return stem if stem != "" else "teal_531"

func _save(panels: Array[Image], stem: String) -> void:
	var strip := Image.create(CROP.x * ZOOM * panels.size(), CROP.y * ZOOM, false, panels[0].get_format())
	for i in panels.size():
		strip.blit_rect(panels[i], Rect2i(Vector2i.ZERO, panels[i].get_size()), Vector2i(i * CROP.x * ZOOM, 0))
		strip.fill_rect(Rect2i((i * CROP.x + CROP.x / 2) * ZOOM, 0, RULER_WIDTH, CROP.y * ZOOM), RULER)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := "%s/%s_%s.png" % [OUT_DIR, _prefix(), stem]
	strip.save_png(path)
	print("LooseShot: %s" % path)

func _teardown() -> void:
	_view.queue_free()
	_view = null
	await get_tree().process_frame

func _run() -> void:
	var loose := _loose()
	if loose.is_empty():
		printerr("LooseShot: no projectile loose found in any sweep party. Nothing measured.")
		return
	await _strip(loose, false)
	await _strip(loose, true)
	await _still(loose)
	for units in [14, 100]:
		await _cost(units, false, false)
		await _cost(units, true, false)
		await _cost(units, true, true)

## One strip. `on` is the only difference between the two: same party, same
## seed, same tick, same frames.
func _strip(loose: Dictionary, on: bool) -> void:
	DisplayOptions.set_enabled(&"impact_squash", on)
	# Off, so what a strip shows and what a stopwatch reads is this issue's
	# effect rather than #515's freeze mixed in with it.
	DisplayOptions.set_enabled(&"hit_stop", false)
	await _build_view(loose["party"])
	while _view.state.tick < loose["tick"]:
		_frame()
	await get_tree().process_frame

	var shooter: Node2D = _view._unit_views[loose["source"]]
	var centre: Vector2 = shooter.get_global_transform_with_canvas().origin
	var panels: Array[Image] = []
	var moved := 0
	print("  toggle %s" % ("ON" if on else "off"))
	for i in FRAMES:
		var kick: Vector2 = UnitView.recoil_offset(
			shooter._recoil_age, shooter._recoil_direction, shooter._recoil_pixels)
		if kick != Vector2.ZERO:
			moved += 1
		print("    frame %2d  tick %d  kick %.2f, %.2f  (%.1f px)" % [
			i, _view.state.tick, kick.x, kick.y, kick.length()])
		panels.append(_crop(await _shot(), centre))
		_frame()
		await get_tree().process_frame
	print("  %d of %d frames carry a kick" % [moved, FRAMES])
	_save(panels, "on" if on else "off")
	DisplayOptions.reset()
	await _teardown()

## The whole screen at full scale, with the ENGINE driving `_process` on real
## deltas: every strip above drives it by hand, so none of them is the path a
## player takes.
func _still(loose: Dictionary) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var cfg := RunConfig.new()
	cfg.party = _party(loose["party"])
	cfg.encounter_id = Registry.all_encounter_ids()[0]
	cfg.seed = SEED
	var packed: PackedScene = load("res://Scenes/Battle.tscn")
	_view = packed.instantiate()
	add_child(_view)
	await get_tree().process_frame
	_view.begin_with_encounter(cfg, _encounter())

	var waited := 0
	var seen := 0
	while _view.state.tick < loose["tick"] + 1 and waited < 20000:
		await RenderingServer.frame_post_draw
		waited += 1
		for id in _view._unit_views:
			if _view._unit_views[id].impact_active():
				seen += 1
				break
	await RenderingServer.frame_post_draw
	var path := "%s/%s_battle_screen.png" % [OUT_DIR, _prefix()]
	get_viewport().get_texture().get_image().save_png(path)
	print("LooseShot: %s at tick %d after %d engine frames, %d of them with a live impact" % [
		path, _view.state.tick, waited, seen])
	await _teardown()

## Copies every script variable, so a field added to CombatUnit later is carried
## without this list rotting. Fabricated bodies for a cost measurement only --
## never read a fight outcome off an inflated state.
func _clone(src: CombatUnit, id: int) -> CombatUnit:
	var out := CombatUnit.new()
	for p in src.get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			out.set(p.name, src.get(p.name))
	out.id = id
	out.position = Vector2(
		randf_range(-CG.ARENA_HALF_WIDTH, CG.ARENA_HALF_WIDTH),
		randf_range(-CG.ARENA_HALF_HEIGHT, CG.ARENA_HALF_HEIGHT))
	return out

## `storm` makes every body on the screen loose every frame, which no fight
## does: it is the ceiling the real thing cannot exceed. Without it the row is
## the shipped path, where a loose is a handful of events a second.
func _cost(units: int, on: bool, storm: bool) -> void:
	seed(SEED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayOptions.set_enabled(&"impact_squash", on)
	DisplayOptions.set_enabled(&"hit_stop", false)
	var party_ids: Array = ScreenSweepScript.sweep_parties(Registry.all_class_ids())[0]
	await _build_view(party_ids)
	var state: CombatState = _view.state
	var source: Array = state.units.duplicate()
	while state.units.size() < units:
		state.units.append(_clone(source[state.units.size() % source.size()], state.units.size()))
	_view._ensure_unit_views()
	await RenderingServer.frame_post_draw

	var frames := 0
	var t0 := Time.get_ticks_usec()
	for i in COST_FRAMES:
		if state.outcome != CombatState.Outcome.UNRESOLVED:
			break
		if storm:
			for id in _view._unit_views:
				_view._unit_views[id].recoiled(Vector2.RIGHT, UnitView.LOOSE_PIXELS)
		_frame()
		await RenderingServer.frame_post_draw
		frames += 1
	var spent := Time.get_ticks_usec() - t0
	print("LooseShot cost, %d units, kick %s, storm %s: %d us per rendered frame (n=%d)" % [
		state.units.size(), on, storm, 0 if frames == 0 else spent / frames, frames])
	DisplayOptions.reset()
	await _teardown()
