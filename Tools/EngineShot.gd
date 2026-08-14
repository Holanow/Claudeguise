extends Node

const CG := preload("res://Scripts/Core/CG.gd")
const RunConfig := preload("res://Scripts/Core/RunConfig.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")

const BATTLE_SCENE := preload("res://Scenes/Battle.tscn")

## Issue 93: the artillery rebuild on a real screen, in the real Battle scene.
##
##   godot --path . --resolution 1280x720 res://Tools/EngineShot.tscn
##
## Not part of the game and not part of the gate.
##
## A green suite proves the engine holds fire and the cap holds. It cannot prove
## a player can see any of it happen, and this project has already shipped a
## siege engine that was correct in the registry and invisible on screen twice
## (issue 75). So the frames are chosen by asking the simulation where the
## interesting ticks are rather than at fixed times: the same probe-then-replay
## trick `Tools/IconsInFight.gd` and `Tools/ContactSheet.gd` both use.
##
## Deliberately picks ticks where a bolt is actually in flight from an engine.
## A frame with an engine standing still is what this feature looked like before
## and is not evidence of anything.
##
## No --headless: `get_viewport().get_texture()` never populates under
## --headless on this machine (see Tools/AttackFXPreview.gd's own note).

const OUT_DIR := "res://Screenshots"
const FRAMES := 3

var _battle: Node = null
var _targets: Array[int] = []
var _encounter: StringName = &""
var _seed := 0
var _next := 0

func _party() -> Array[PawnData]:
	var out: Array[PawnData] = []
	for cid in Registry.all_class_ids():
		if cid == &"geysermancer":
			continue
		out.append(PawnFactory.make_starter_pawn(cid, StringName("%s_%d" % [cid, out.size()]), Registry.get_class_def(cid).display_name))
	return out

func _ready() -> void:
	# Search for a fight that actually shows the feature, rather than trusting a
	# hand-picked seed. The first version of this pinned SEED and floor1_warden
	# and found zero ticks with a bolt in flight: that fight lasts 298 ticks and
	# the build alone is a 90-tick wind-up, so there was nothing to photograph.
	# A screenshot tool that silently picks a boring fight is how a feature gets
	# signed off on a picture of nothing.
	var interesting: Array[int] = []
	for encounter_id in Registry.all_encounter_ids():
		for s in 20:
			interesting = _bolt_ticks(encounter_id, s)
			if interesting.size() >= FRAMES:
				_encounter = encounter_id
				_seed = s
				break
		if _encounter != &"":
			break
	if _encounter == &"":
		printerr("EngineShot: no engine bolt was ever in flight in any sampled fight")
		get_tree().quit(1)
		return
	print("EngineShot: %s seed %d -- %d ticks with an engine bolt in flight" % [_encounter, _seed, interesting.size()])
	for i in FRAMES:
		_targets.append(interesting[int(float(interesting.size() - 1) * float(i) / float(maxi(1, FRAMES - 1)))])

	var cfg := RunConfig.new()
	cfg.party = _party()
	cfg.encounter_id = _encounter
	cfg.seed = _seed
	_battle = BATTLE_SCENE.instantiate()
	add_child(_battle)
	_battle.begin(cfg)


## Every tick of one fight on which an unresolved engine bolt exists.
func _bolt_ticks(encounter_id: StringName, seed_value: int) -> Array[int]:
	var probe := CombatSim.build(_party(), Registry.get_encounter(encounter_id), seed_value)
	var out: Array[int] = []
	while probe.outcome == CombatState.Outcome.UNRESOLVED and probe.tick < CG.MAX_TICKS:
		CombatSim.step(probe)
		for p in probe.projectiles:
			if not p.resolved and p.action_id == &"siege_engine_bolt":
				out.append(probe.tick)
				break
	return out

func _process(_delta: float) -> void:
	if _battle == null or _next >= _targets.size():
		return
	var state = _battle.state
	if state == null or state.tick < _targets[_next]:
		return
	_capture(_next, state)
	_next += 1
	if _next >= _targets.size():
		get_tree().quit(0)

func _capture(index: int, state) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := "%s/finch_93_engine_%02d.png" % [OUT_DIR, index + 1]
	image.save_png(path)
	var engines := 0
	var marked := 0
	for u in state.units:
		if u.alive and u.enemy_id == &"siege_engine":
			engines += 1
	for u in state.living(CG.Team.ENEMY):
		if u.has_status(CG.Status.MARKED):
			marked += 1
	print("EngineShot: %s at tick %d -- %d engines alive, %d marked enemies" % [path, state.tick, engines, marked])
