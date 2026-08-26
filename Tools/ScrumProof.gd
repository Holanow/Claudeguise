extends Node

## Issue 604. The cache's claim is that nothing on screen moves, so this
## photographs a scrum and prints every drawn body position, and is run once on
## the base commit and once on the branch.
##
## Hand-driven like `Tools/HandCost.gd`: with `_process` off and the delta fed
## in as an exact quarter tick, `_anim_seconds` is a function of the frame
## number rather than of the wall clock, so two runs of the same build are
## byte-identical and a difference means the drawn picture changed.

const ScreenSweepScript := preload("res://Tools/ScreenSweep.gd")
const OUT_DIR := "res://Screenshots"
const SEED := 7
const FRAMES_PER_TICK := 4
## Far enough in that the melee has closed and bodies overlap.
const START_TICK := 90
const FRAMES := 4

var _view: Node2D = null

func _ready() -> void:
	Offscreen.hide_window(self)
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("ScrumProof: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	var args := OS.get_cmdline_user_args()
	await _run("base" if args.is_empty() else args[0])
	get_tree().quit(0)

## Floaters, plates and the arena's own children keep their `_process`, which
## the engine calls with the wall clock. Re-applied every frame because a fight
## makes new ones.
func _freeze() -> void:
	_view.propagate_call(&"set_process", [false])
	_view.propagate_call(&"set_physics_process", [false])

func _party(ids: Array) -> Array[PawnData]:
	var out: Array[PawnData] = []
	for i in ids.size():
		out.append(PawnFactory.make_starter_pawn(
			ids[i], StringName("p%d" % i), String(ids[i])))
	return out

func _run(tag: String) -> void:
	seed(SEED)
	DisplayOptions.reset()
	# Everything that ages on the engine's own delta rather than on the tick,
	# which is the one thing a hand-driven capture cannot make deterministic.
	DisplayOptions.set_enabled(&"hit_stop", false)
	DisplayOptions.set_enabled(&"impact_particles", false)
	DisplayOptions.set_enabled(&"death_explosion", false)
	DisplayOptions.set_enabled(&"part_animation", true)

	var cfg := RunConfig.new()
	cfg.party = _party(ScreenSweepScript.sweep_parties(Registry.all_class_ids())[0])
	cfg.encounter_id = &"floor1_room1"
	cfg.seed = SEED
	var packed: PackedScene = load("res://Scenes/Battle.tscn")
	_view = packed.instantiate()
	add_child(_view)
	await get_tree().process_frame
	_view.begin_with_encounter(cfg, Registry.get_encounter(cfg.encounter_id))
	_view.set_process(false)
	await RenderingServer.frame_post_draw

	var step := CG.TICK_SECONDS / float(FRAMES_PER_TICK)
	while _view.state.tick < START_TICK and _view.state.outcome == CombatState.Outcome.UNRESOLVED:
		_view._process(step)
		_freeze()
		await RenderingServer.frame_post_draw

	var overlapping := 0
	for i in FRAMES:
		_view._process(step)
		_freeze()
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
		image.save_png("%s/sable_604_scrum_%s_%d.png" % [OUT_DIR, tag, i])
		var ids: Array = _view._unit_views.keys()
		ids.sort()
		for id in ids:
			var view = _view._unit_views[id]
			if not view.visible:
				continue
			print("ScrumProof %s frame %d unit %d at (%.6f, %.6f) nudge (%.6f, %.6f)" % [
				tag, i, id, view.position.x, view.position.y,
				UnitView.visual_offset(_view.state.unit(int(id)), _view.state.units).x,
				UnitView.visual_offset(_view.state.unit(int(id)), _view.state.units).y])
			if UnitView.visual_offset(_view.state.unit(int(id)), _view.state.units) != Vector2.ZERO:
				overlapping += 1
	print("ScrumProof %s: tick %d, %d units, %d nudged body-frames (0 would mean this photographed no scrum)" % [
		tag, _view.state.tick, _view.state.units.size(), overlapping])
	DisplayOptions.reset()
