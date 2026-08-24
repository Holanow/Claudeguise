extends Node

## Issue 501: does the view move between simulation ticks? Eight consecutive
## rendered frames of one pawn crossing the arena, as one strip, with the drawn
## position printed for each. Three repeats and a jump is the bug; eight
## distinct positions is the fix. Then the per-frame cost at 14 and 100 units,
## because a lerp per body per frame is new work the view has never carried.

const OUT_DIR := "res://Screenshots"
const SEED := 7
## A 60Hz display against a 15Hz simulation. The whole defect is this ratio.
const FRAMES_PER_TICK := 4
const FRAMES := 8
const CROP := Vector2i(96, 72)
const ZOOM := 8
## Where the body stood in the first panel, painted into every panel. Without a
## fixed mark a strip of eight crops of one pawn looks the same either way.
const RULER := Color(1.0, 0.2, 0.6)
const RULER_WIDTH := 3
const COST_FRAMES := 240
const BIG_UNITS := 100
const ScreenSweepScript := preload("res://Tools/ScreenSweep.gd")

var _view: Node2D = null

func _ready() -> void:
	Offscreen.hide_window(self)
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("InterpShot: refusing to run in the main checkout -- use a worktree.")
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

## Simulation only: the tick at which some unit covers the most ground in one
## step, because that is where a 15Hz snap is largest and a lerp most visible.
func _fastest_walk() -> Dictionary:
	var best := {"tick": -1, "id": -1, "moved": 0.0, "party": []}
	for party_ids in ScreenSweepScript.sweep_parties(Registry.all_class_ids()):
		var state := CombatSim.build(_party(party_ids), _encounter(), SEED)
		var was := {}
		while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
			for u in state.units:
				was[u.id] = u.position
			CombatSim.step(state)
			for u in state.units:
				if not u.alive or not was.has(u.id):
					continue
				var moved: float = u.position.distance_to(was[u.id])
				# A walk, not a jump the view is meant to snap through.
				if moved > best["moved"] and moved <= u.move_speed * 3.0 and state.tick > FRAMES:
					best = {"tick": state.tick - 1, "id": u.id, "moved": moved, "party": party_ids}
	print("InterpShot: party %s, unit %d walks %.1f units in one tick, strip starts at tick %d" % [
		", ".join(PackedStringArray(best["party"])), best["id"], best["moved"], best["tick"]])
	return best

## Started the way the game starts one. Setting `state` by hand instead leaves
## `_text_layer` null, and every stepped frame then dies inside `_process`
## before it draws -- which is what this tool exists to look at.
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

## One rendered frame's worth of wall clock, driven by hand: the view's own
## `_process` spends real time, which would make the strip unrepeatable.
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
	var walk := _fastest_walk()
	if walk["id"] < 0:
		return
	await _strip(walk)
	await _cost(14)
	await _cost(BIG_UNITS)

func _strip(walk: Dictionary) -> void:
	await _build_view(walk["party"])
	# Driven to the tick through the view's own clock, four rendered frames to
	# the tick, so the strip shows exactly what a 60Hz display shows.
	while _view.state.tick < walk["tick"]:
		_frame()
	await get_tree().process_frame

	var body: Node2D = _view._unit_views[walk["id"]]
	var centre: Vector2 = body.get_global_transform_with_canvas().origin
	var panels: Array[Image] = []
	var last := Vector2.INF
	var distinct := 0
	for i in FRAMES:
		var at := body.position
		if at != last:
			distinct += 1
		print("  frame %d  tick %d  drawn %.2f, %.2f  moved %.2f  alpha %.3f" % [
			i, _view.state.tick, at.x, at.y, 0.0 if last == Vector2.INF else at.distance_to(last),
			_view._tick_accumulator / CG.TICK_SECONDS])
		last = at
		panels.append(await _panel(centre))
		_frame()
		await get_tree().process_frame
	print("  %d of %d frames are a new position" % [distinct, FRAMES])

	var strip := Image.create(CROP.x * ZOOM * panels.size(), CROP.y * ZOOM, false, panels[0].get_format())
	for i in panels.size():
		strip.blit_rect(panels[i], Rect2i(Vector2i.ZERO, panels[i].get_size()), Vector2i(i * CROP.x * ZOOM, 0))
		strip.fill_rect(Rect2i(
			(i * CROP.x + CROP.x / 2) * ZOOM, 0, RULER_WIDTH, CROP.y * ZOOM), RULER)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var stem := OS.get_environment("INTERP_SHOT_NAME")
	if stem == "":
		stem = "sable_501_interpolated"
	var path := "%s/%s.png" % [OUT_DIR, stem]
	strip.save_png(path)
	print("InterpShot: %s" % path)
	_view.queue_free()
	_view = null
	await get_tree().process_frame

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

func _cost(units: int) -> void:
	seed(SEED)
	var party_ids: Array = ScreenSweepScript.sweep_parties(Registry.all_class_ids())[0]
	await _build_view(party_ids)
	var state: CombatState = _view.state
	var source: Array = state.units.duplicate()
	while state.units.size() < units:
		state.units.append(_clone(source[state.units.size() % source.size()], state.units.size()))
	_view._ensure_unit_views()
	await get_tree().process_frame

	var stepped_us := 0
	var stepped := 0
	var between_us := 0
	var between := 0
	for i in COST_FRAMES:
		if state.outcome != CombatState.Outcome.UNRESOLVED:
			break
		var before := state.tick
		var t0 := Time.get_ticks_usec()
		_frame()
		var spent := Time.get_ticks_usec() - t0
		if state.tick != before:
			stepped_us += spent
			stepped += 1
		else:
			between_us += spent
			between += 1
	print("InterpShot cost, %d units: stepping frame %d us (n=%d), between-tick frame %d us (n=%d)" % [
		state.units.size(),
		0 if stepped == 0 else stepped_us / stepped, stepped,
		0 if between == 0 else between_us / between, between])
	_view.queue_free()
	_view = null
	await get_tree().process_frame
