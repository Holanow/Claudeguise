extends Node

## Issue 583. What moving hands cost a whole rendered frame at 14 and at 100
## units, against #566's one-draw-call-per-body baseline.
##
## Copies `Tools/ParticleCost._cost` deliberately, so the two numbers can be
## compared: a whole rendered frame, wall clock, vsync off, 240 frames, bodies
## cloned up to the count. The only variable is the `part_animation` toggle.

const ScreenSweepScript := preload("res://Tools/ScreenSweep.gd")
const SEED := 7
const COST_FRAMES := 240
const FRAMES_PER_TICK := 4

var _view: Node2D = null

func _ready() -> void:
	Offscreen.hide_window(self)
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("HandCost: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	for units in [14, 100]:
		await _cost(units, false)
		await _cost(units, false, true)
		await _cost(units, true)
	get_tree().quit(0)

func _party(ids: Array) -> Array[PawnData]:
	var out: Array[PawnData] = []
	for i in ids.size():
		out.append(PawnFactory.make_starter_pawn(
			ids[i], StringName("p%d" % i), String(ids[i])))
	return out

func _build_view(party_ids: Array) -> void:
	var cfg := RunConfig.new()
	cfg.party = _party(party_ids)
	cfg.encounter_id = Registry.all_encounter_ids()[0]
	cfg.seed = SEED
	var packed: PackedScene = load("res://Scenes/Battle.tscn")
	_view = packed.instantiate()
	add_child(_view)
	await get_tree().process_frame
	_view.begin_with_encounter(cfg, Registry.get_encounter(Registry.all_encounter_ids()[0]))
	_view.set_process(false)

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

## `redraw_only` is the control for the obvious suspicion: an idle bob has to
## repaint every body every frame, and a `UnitView._draw` is bars, badges,
## plates and a wind-up block as well as the body. It repaints without moving
## anything, so the gap between it and `hands off` is the repaint alone.
func _cost(units: int, hands: bool, redraw_only: bool = false) -> void:
	seed(SEED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayOptions.reset()
	DisplayOptions.set_enabled(&"part_animation", hands)
	var party_ids: Array = ScreenSweepScript.sweep_parties(Registry.all_class_ids())[0]
	await _build_view(party_ids)
	var state: CombatState = _view.state
	var source: Array = state.units.duplicate()
	while state.units.size() < units:
		state.units.append(_clone(source[state.units.size() % source.size()], state.units.size()))
	_view._ensure_unit_views()
	await RenderingServer.frame_post_draw

	var animated := 0
	for id in _view._unit_views:
		var u := state.unit(int(id))
		if u != null and _view._unit_views[id].can_animate(u):
			animated += 1
	var frames := 0
	var t0 := Time.get_ticks_usec()
	for i in COST_FRAMES:
		_view._process(CG.TICK_SECONDS / float(FRAMES_PER_TICK))
		if redraw_only:
			for id in _view._unit_views:
				_view._unit_views[id].queue_redraw()
		await RenderingServer.frame_post_draw
		frames += 1
	var spent := Time.get_ticks_usec() - t0
	print("HandCost: %d units, %-11s: %d us per rendered frame (n=%d, %d bodies animated, %d sprites in a warrior)" % [
		state.units.size(),
		"redraw only" if redraw_only else ("hands on" if hands else "hands off"),
		0 if frames == 0 else spent / frames, frames, animated,
		UnitArt.sprites_for(&"warrior", CG.Team.PLAYER).size()])
	DisplayOptions.reset()
	_view.queue_free()
	_view = null
	await get_tree().process_frame
