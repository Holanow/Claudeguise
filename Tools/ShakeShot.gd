extends Node

## Issue 518: does a death-gated screen shake cost more legibility than it buys?
##
## Three strips of sixteen consecutive rendered frames across one death -- shake
## off, shake on with the freeze off, and shake on with #515's freeze on, which
## is the shipped pairing if a player turns this row up.
##
## The crop origin is computed ONCE, before the first frame, and every panel is
## cut at that same viewport rectangle. The ruler is then blitted onto the
## finished image. Both live outside the node that shakes, which is the whole
## point: a ruler drawn in the arena shakes with the picture and proves nothing.

const OUT_DIR := "res://Screenshots"
const SEED := 7
const FRAMES_PER_TICK := 4
const FRAMES := 16
const CROP := Vector2i(230, 150)
const ZOOM := 2
const RULER := Color(1.0, 0.2, 0.6)
const RULER_WIDTH := 2
const COST_FRAMES := 240
const ScreenSweepScript := preload("res://Tools/ScreenSweep.gd")

var _view: Node2D = null

func _ready() -> void:
	Offscreen.hide_window(self)
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("ShakeShot: refusing to run in the main checkout -- use a worktree.")
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

## The BIGGEST body to die anywhere in the class sweep, because amplitude is
## scaled to the body and a strip of the smallest one shows the least the
## feature ever does (#280).
func _death() -> Dictionary:
	var best := {}
	var best_size := 0.0
	for party_ids in ScreenSweepScript.sweep_parties(Registry.all_class_ids()):
		var state := CombatSim.build(_party(party_ids), _encounter(), SEED)
		var cursor := 0
		while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
			CombatSim.step(state)
			for e in state.events_since(cursor):
				if e.kind != CG.EventKind.DEATH or state.tick <= FRAMES:
					continue
				var dead := state.unit(e.target_id)
				if dead == null:
					continue
				var size := UnitView.drawn_half_width(
					UnitView.shape_id(dead), dead.team, UnitView.display_radius(dead))
				if size <= best_size:
					continue
				best_size = size
				best = {"tick": state.tick - 1, "dead": dead.id, "party": party_ids}
			cursor = state.events.size()
	if not best.is_empty():
		print("ShakeShot: unit %d dies on tick %d, %.0f px half-width, party %s" % [
			best["dead"], int(best["tick"]) + 1, best_size,
			", ".join(PackedStringArray(best["party"]))])
	return best

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

## `origin` is in VIEWPORT space and is the same for every panel in a strip.
func _crop(full: Image, origin: Vector2i) -> Image:
	origin = origin.clamp(Vector2i.ZERO, full.get_size() - CROP)
	var panel := full.get_region(Rect2i(origin, CROP))
	panel.resize(CROP.x * ZOOM, CROP.y * ZOOM, Image.INTERPOLATE_NEAREST)
	return panel

func _prefix() -> String:
	var stem := OS.get_environment("SHAKE_SHOT_NAME")
	return stem if stem != "" else "teal_518"

func _save(panels: Array[Image], stem: String) -> void:
	var strip := Image.create(CROP.x * ZOOM * panels.size(), CROP.y * ZOOM, false, panels[0].get_format())
	for i in panels.size():
		strip.blit_rect(panels[i], Rect2i(Vector2i.ZERO, panels[i].get_size()), Vector2i(i * CROP.x * ZOOM, 0))
		strip.fill_rect(Rect2i((i * CROP.x + CROP.x / 2) * ZOOM, 0, RULER_WIDTH, CROP.y * ZOOM), RULER)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := "%s/%s_%s.png" % [OUT_DIR, _prefix(), stem]
	strip.save_png(path)
	print("ShakeShot: %s" % path)

func _teardown() -> void:
	_view.queue_free()
	_view = null
	await get_tree().process_frame

func _run() -> void:
	var death := _death()
	if death.is_empty():
		printerr("ShakeShot: no death found in any sweep party. Nothing measured.")
		return
	await _strip(death, false, false, "off")
	await _strip(death, true, false, "on")
	await _strip(death, true, true, "on_frozen")
	## The counterfactual the recommendation needs: what "big enough to notice
	## without a ruler beside it" costs. Driven by hand, three times the shipped
	## amplitude, and it is not a state the shipped code can reach.
	await _strip(death, true, false, "loud", 3.0)
	for units in [14, 100]:
		await _cost(units, false)
		await _cost(units, true)

func _strip(death: Dictionary, shake: bool, freeze: bool, stem: String, amplify: float = 1.0) -> void:
	DisplayOptions.set_enabled(&"screen_shake", shake)
	DisplayOptions.set_enabled(&"hit_stop", freeze)
	await _build_view(death["party"])
	while _view.state.tick < death["tick"]:
		_frame()
	await get_tree().process_frame

	# Once, before the first panel, and in viewport space. Every panel is cut at
	# this same rectangle, so the arena moving under it is the whole picture.
	var body: Node2D = _view._unit_views[death["dead"]]
	var origin := Vector2i(body.get_global_transform_with_canvas().origin) - CROP / 2
	var panels: Array[Image] = []
	var moved := 0
	var furthest := 0.0
	var amplified := false
	print("  shake %s, freeze %s, amplify %.1fx" % [shake, freeze, amplify])
	for i in FRAMES:
		var at: Vector2 = _view._arena.position - _view._arena_base
		if at != Vector2.ZERO:
			moved += 1
		furthest = maxf(furthest, at.length())
		print("    frame %2d  tick %d  arena %+.2f, %+.2f  (%.1f px)  frozen %s" % [
			i, _view.state.tick, at.x, at.y, at.length(), _view._freeze_left > 0.0])
		panels.append(_crop(await _shot(), origin))
		_frame()
		if amplify != 1.0 and _view._shake_amplitude > 0.0 and not amplified:
			amplified = true
			_view._shake_amplitude *= amplify
			_view._advance_shake(0.0)
		await get_tree().process_frame
	print("  %d of %d frames have the arena off its layout pixel, furthest %.1f px" % [
		moved, FRAMES, furthest])
	_save(panels, stem)
	DisplayOptions.reset()
	await _teardown()

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

## A shake is one node's position per frame however many bodies are on screen,
## so it is held live for every frame of the row rather than fired once.
func _cost(units: int, on: bool) -> void:
	seed(SEED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayOptions.set_enabled(&"screen_shake", on)
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
		if on:
			_view._shake_age = 0.0
			_view._shake_amplitude = BattleView.SHAKE_PIXELS
		_frame()
		await RenderingServer.frame_post_draw
		frames += 1
	var spent := Time.get_ticks_usec() - t0
	print("ShakeShot cost, %d units, shake %s held live: %d us per rendered frame (n=%d)" % [
		state.units.size(), on, 0 if frames == 0 else spent / frames, frames])
	DisplayOptions.reset()
	await _teardown()
