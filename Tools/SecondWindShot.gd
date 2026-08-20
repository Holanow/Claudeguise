extends Node


const BATTLE_SCENE := preload("res://Scenes/Battle.tscn")

## Issue 99: the Warrior's Second Wind on a real screen, in the real Battle
## scene.
##
##   godot --path . --resolution 1280x720 res://Tools/SecondWindShot.tscn
##
## Not part of the game and not part of the gate.
##
## Searches for a fight where the ability actually fires rather than trusting a
## pinned seed, the same correction `Tools/EngineShot.gd` needed on issue 93:
## the first version of that tool photographed a fight in which the thing it was
## documenting never happened. Captures the tick of the HEAL itself, so the frame
## shows the floater and the log line rather than the wind-up.
##
## No --headless: `get_viewport().get_texture()` never populates under
## --headless on this machine (see Tools/AttackFXPreview.gd's own note).

const OUT_DIR := "res://Screenshots"
const FRAMES := 2

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
	var ticks: Array[int] = []
	for encounter_id in Registry.all_encounter_ids():
		for s in 20:
			ticks = _heal_ticks(encounter_id, s)
			if ticks.size() >= 1:
				_encounter = encounter_id
				_seed = s
				break
		if _encounter != &"":
			break
	if _encounter == &"":
		printerr("SecondWindShot: Second Wind never healed in any sampled fight")
		get_tree().quit(1)
		return
	print("SecondWindShot: %s seed %d -- Second Wind heals on ticks %s" % [_encounter, _seed, str(ticks)])
	for i in mini(FRAMES, ticks.size()):
		_targets.append(ticks[i])

	var cfg := RunConfig.new()
	cfg.party = _party()
	cfg.encounter_id = _encounter
	cfg.seed = _seed
	_battle = BATTLE_SCENE.instantiate()
	add_child(_battle)
	_battle.begin(cfg)

## The ticks on which Second Wind actually restored health. HEAL rather than
## ACTION_FIRE: a fire with no heal behind it is the ability doing nothing, and
## a screenshot of that would be evidence for the opposite of what it claims.
func _heal_ticks(encounter_id: StringName, seed_value: int) -> Array[int]:
	var state := CombatSim.build(_party(), Registry.get_encounter(encounter_id), seed_value)
	CombatSim.run(state)
	var out: Array[int] = []
	for e in state.events:
		if e.kind == CG.EventKind.HEAL and e.action_id == &"warrior_second_wind":
			out.append(e.tick)
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
	var path := "%s/finch_99_second_wind_%02d.png" % [OUT_DIR, index + 1]
	image.save_png(path)
	print("SecondWindShot: %s at tick %d" % [path, state.tick])
