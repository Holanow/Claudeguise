extends "res://Tests/TestCase.gd"

const BattleScene := preload("res://Scenes/Battle.tscn")
const ArenaFloor := preload("res://Scripts/UI/ArenaFloor.gd")
const RunConfig := preload("res://Scripts/Core/RunConfig.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")

## Criterion 1 says the drawn arena and the simulated arena must be the same
## rectangle, not a second guess at it. ArenaFloor reads CG.ARENA_HALF_WIDTH/
## HEIGHT directly and is attached to the same Arena node _layout_arena scales
## and positions, so there is exactly one source of truth for the rectangle
## rather than two numbers that happen to agree today. This test enforces the
## wiring: the Arena node must actually carry ArenaFloor's script.

func test_arena_node_carries_the_floor_script() -> void:
	var battle = BattleScene.instantiate()
	var arena := battle.get_node("Arena")
	assert_eq(arena.get_script(), ArenaFloor, "Arena must draw the floor in the same local space _layout_arena scales")
	battle.free()

## Issue 26 item 1: a fight built without terrain (CombatState.terrain is
## empty by default) must draw exactly as it always has — nothing new
## required from teal's 13b before this is safe to merge.
func test_terrain_defaults_to_empty() -> void:
	var arena := ArenaFloor.new()
	assert_true(arena.terrain.is_empty())
	arena.free()

## begin() hands CombatState.terrain to the Arena node directly, not a copy
## or a re-derived version — one source of truth, same reasoning as the
## rectangle itself. Needs real Registry content (a real encounter to build
## against), so this is a no-op rather than a false pass while empty.
func test_begin_wires_the_states_terrain_onto_the_arena() -> void:
	var encounter_ids := Registry.all_encounter_ids()
	var class_ids := Registry.all_class_ids()
	if encounter_ids.is_empty() or class_ids.is_empty():
		return
	var battle = BattleScene.instantiate()
	battle._ready()
	var config := RunConfig.new()
	config.seed = 1
	config.encounter_id = encounter_ids[0]
	var party: Array[PawnData] = [PawnFactory.make_starter_pawn(class_ids[0], class_ids[0], String(class_ids[0]))]
	config.party = party
	battle.begin(config)
	assert_eq(battle._arena.terrain, battle.state.terrain)
	battle.free()
