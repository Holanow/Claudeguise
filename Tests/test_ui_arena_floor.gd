extends "res://Tests/TestCase.gd"

const BattleScene := preload("res://Scenes/Battle.tscn")
const ArenaFloor := preload("res://Scripts/UI/ArenaFloor.gd")

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
