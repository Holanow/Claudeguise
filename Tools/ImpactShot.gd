extends Node

## Issue 516: does a body compress when it is hit, and does the thing that hit
## it rock backward? A still cannot show a decay, so this is two strips of
## sixteen consecutive rendered frames across one melee blow -- the same fight,
## the same tick, the toggle off in one and on in the other -- with the squash
## scale and the recoil offset printed for every frame so the easing can be read
## off the numbers as well as off the pixels.
##
## Then what it costs a WHOLE RENDERED FRAME at 14 and at 100 units. Timing
## `_process` alone answers the wrong question: the canvas is rebuilt after it
## returns, and a squash is a canvas rebuild.

const OUT_DIR := "res://Screenshots"
const SEED := 7
const FRAMES_PER_TICK := 4
## Four ticks, because SQUASH_SECONDS is 0.22 and a strip shorter than the decay
## cannot show the decay.
const FRAMES := 16
const CROP := Vector2i(180, 130)
const ZOOM := 3
const RULER := Color(1.0, 0.2, 0.6)
const RULER_WIDTH := 2
const COST_FRAMES := 240
const ScreenSweepScript := preload("res://Tools/ScreenSweep.gd")

var _view: Node2D = null

func _ready() -> void:
	Offscreen.hide_window(self)
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("ImpactShot: refusing to run in the main checkout -- use a worktree.")
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

## Simulation only. Every melee blow that carries an action and lands on a body
## still standing next to whoever threw it -- exactly the pair of gates
## `BattleView._apply_impact` applies, so the strip photographs a hit the
## shipped code will actually react to.
##
## The BIGGEST struck body wins, not the first. A 22% compression of an
## eleven-pixel goblin is two pixels, and a strip nobody can read is not
## evidence of anything (#280).
func _blow() -> Dictionary:
	var best := {}
	var best_size := 0.0
	for party_ids in ScreenSweepScript.sweep_parties(Registry.all_class_ids()):
		var state := CombatSim.build(_party(party_ids), _encounter(), SEED)
		var cursor := 0
		while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
			CombatSim.step(state)
			for e in state.events_since(cursor):
				if e.kind != CG.EventKind.DAMAGE or e.action_id == &"" or state.tick <= FRAMES:
					continue
				var source := state.unit(e.source_id)
				var target := state.unit(e.target_id)
				if source == null or target == null or source.id == target.id:
					continue
				var reach := (UnitView.display_radius(source) + UnitView.display_radius(target)) \
					* BattleView.RECOIL_REACH
				if source.position.distance_to(target.position) > reach:
					continue
				var size := UnitView.drawn_half_width(
					UnitView.shape_id(target), target.team, UnitView.display_radius(target))
				if size <= best_size:
					continue
				best_size = size
				best = {"tick": state.tick - 1, "source": source.id, "target": target.id,
					"party": party_ids, "action": e.action_id}
			cursor = state.events.size()
	if not best.is_empty():
		print("ImpactShot: unit %d hits unit %d with %s at tick %d, struck body %.0f px half-width, party %s" % [
			best["source"], best["target"], best["action"], int(best["tick"]) + 1, best_size,
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

## The view's clock, plus every transient's. The squash needs no help: it is
## spent by `_render` off the same delta this passes in. A ring and a number age
## on the engine's real delta instead, and the frames this tool draws cost almost
## no wall clock, so left alone forty of them pile up and none ever expires.
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
	var stem := OS.get_environment("IMPACT_SHOT_NAME")
	return stem if stem != "" else "sable_516"

func _save(panels: Array[Image], stem: String) -> void:
	var strip := Image.create(CROP.x * ZOOM * panels.size(), CROP.y * ZOOM, false, panels[0].get_format())
	for i in panels.size():
		strip.blit_rect(panels[i], Rect2i(Vector2i.ZERO, panels[i].get_size()), Vector2i(i * CROP.x * ZOOM, 0))
		strip.fill_rect(Rect2i((i * CROP.x + CROP.x / 2) * ZOOM, 0, RULER_WIDTH, CROP.y * ZOOM), RULER)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := "%s/%s_%s.png" % [OUT_DIR, _prefix(), stem]
	strip.save_png(path)
	print("ImpactShot: %s" % path)

func _teardown() -> void:
	_view.queue_free()
	_view = null
	await get_tree().process_frame

func _run() -> void:
	var blow := _blow()
	if blow.is_empty():
		printerr("ImpactShot: no melee blow found in any sweep party. Nothing measured.")
		return
	await _strip(blow, false)
	await _strip(blow, true)
	await _still(blow)
	for units in [14, 100]:
		await _cost(units, false, false)
		await _cost(units, true, false)
		await _cost(units, true, true)

## One strip. `on` is the only difference between the two: same party, same
## seed, same tick, same frames.
func _strip(blow: Dictionary, on: bool) -> void:
	DisplayOptions.set_enabled(&"impact_squash", on)
	# Off, so what a strip shows and what a stopwatch reads is this issue's
	# effect rather than #515's freeze mixed in with it.
	DisplayOptions.set_enabled(&"hit_stop", false)
	await _build_view(blow["party"])
	while _view.state.tick < blow["tick"]:
		_frame()
	await get_tree().process_frame

	var struck: Node2D = _view._unit_views[blow["target"]]
	var attacker: Node2D = _view._unit_views[blow["source"]]
	# Weighted toward the struck body: the squash is the claim, the recoil rides
	# along beside it.
	var centre: Vector2 = struck.get_global_transform_with_canvas().origin.lerp(
		attacker.get_global_transform_with_canvas().origin, 0.35)
	var panels: Array[Image] = []
	var moved := 0
	print("  toggle %s" % ("ON" if on else "off"))
	for i in FRAMES:
		var squash: Vector2 = UnitView.squash_scale(struck._squash_age)
		var recoil: Vector2 = UnitView.recoil_offset(attacker._recoil_age, attacker._recoil_direction)
		if squash != Vector2.ONE or recoil != Vector2.ZERO:
			moved += 1
		print("    frame %2d  tick %d  squash %.3f x %.3f  recoil %.2f, %.2f  (%.1f px)" % [
			i, _view.state.tick, squash.x, squash.y, recoil.x, recoil.y, recoil.length()])
		panels.append(_crop(await _shot(), centre))
		_frame()
		await get_tree().process_frame
	print("  %d of %d frames carry an impact transform" % [moved, FRAMES])
	_save(panels, "on" if on else "off")
	DisplayOptions.reset()
	await _teardown()

## The whole screen at full scale, with the ENGINE driving `_process` on real
## deltas: every strip above drives it by hand, so none of them is the path a
## player takes.
func _still(blow: Dictionary) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var cfg := RunConfig.new()
	cfg.party = _party(blow["party"])
	cfg.encounter_id = Registry.all_encounter_ids()[0]
	cfg.seed = SEED
	var packed: PackedScene = load("res://Scenes/Battle.tscn")
	_view = packed.instantiate()
	add_child(_view)
	await get_tree().process_frame
	_view.begin_with_encounter(cfg, _encounter())

	var waited := 0
	var seen := 0
	while _view.state.tick < blow["tick"] + 1 and waited < 20000:
		await RenderingServer.frame_post_draw
		waited += 1
		for id in _view._unit_views:
			if _view._unit_views[id].impact_active():
				seen += 1
				break
	await RenderingServer.frame_post_draw
	var path := "%s/%s_battle_screen.png" % [OUT_DIR, _prefix()]
	get_viewport().get_texture().get_image().save_png(path)
	print("ImpactShot: %s at tick %d after %d engine frames, %d of them with a live impact" % [
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

## `storm` strikes every body on the screen every frame. A real fight lands a
## handful of blows a second and the clones never fight at all, so without it a
## hundred-unit row measures a hundred bodies at rest; with it, it measures the
## ceiling nothing can exceed.
func _cost(units: int, on: bool, storm: bool) -> void:
	seed(SEED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayOptions.set_enabled(&"impact_squash", on)
	# Off, so what a strip shows and what a stopwatch reads is this issue's
	# effect rather than #515's freeze mixed in with it.
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
				_view._unit_views[id].struck()
				_view._unit_views[id].recoiled(Vector2.RIGHT)
		_frame()
		await RenderingServer.frame_post_draw
		frames += 1
	var spent := Time.get_ticks_usec() - t0
	print("ImpactShot cost, %d units, impact %s, storm %s: %d us per rendered frame (n=%d)" % [
		state.units.size(), on, storm, 0 if frames == 0 else spent / frames, frames])
	DisplayOptions.reset()
	await _teardown()
