extends "res://Tests/TestCase.gd"


## Issue 764: the Siege Master's Mark row needs two things of one condition
## slot -- wait until an enemy is close, and refuse to pay 15 again for a mark
## that is already standing. Measured cause: re-marking starved the Build row,
## which needs 40 out of a 50 pool.

const REACH := 350.0

func _unit(id: int, team: CG.Team, at: Vector2) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.display_name = "U%d" % id
	u.hp_max = 100
	u.hp = 100
	u.position = at
	return u

func _block(range_units: float = REACH) -> EnemyInRangeWithoutStatusBlock:
	var b := EnemyInRangeWithoutStatusBlock.new()
	b.range_units = range_units
	b.status = CG.Status.MARKED
	return b

func _state(enemy_at: Vector2) -> CombatState:
	var s := CombatState.new(764)
	s.units.append(_unit(0, CG.Team.PLAYER, Vector2.ZERO))
	s.units.append(_unit(1, CG.Team.ENEMY, enemy_at))
	return s

func test_an_unmarked_enemy_inside_the_reach_holds() -> void:
	var s := _state(Vector2(200.0, 0.0))
	assert_true(_block().holds(s, s.units[0]))

func test_the_same_enemy_once_marked_does_not() -> void:
	var s := _state(Vector2(200.0, 0.0))
	s.units[1].statuses[CG.Status.MARKED] = 150
	assert_false(_block().holds(s, s.units[0]),
		"the row would pay 15 for a mark that is already standing")

## The range half is still real: an unmarked enemy beyond the reach must not
## hold it, or this block quietly becomes `enemy_lacks_status`.
func test_an_unmarked_enemy_beyond_the_reach_does_not_hold() -> void:
	var s := _state(Vector2(900.0, 0.0))
	assert_false(_block().holds(s, s.units[0]))

## And the two are independent: a marked enemy close by plus an unmarked one
## far away is still a refusal, because neither satisfies both halves.
func test_neither_half_alone_is_enough() -> void:
	var s := _state(Vector2(200.0, 0.0))
	s.units[1].statuses[CG.Status.MARKED] = 150
	s.units.append(_unit(2, CG.Team.ENEMY, Vector2(900.0, 0.0)))
	assert_false(_block().holds(s, s.units[0]))
	s.units[2].position = Vector2(300.0, 0.0)
	assert_true(_block().holds(s, s.units[0]),
		"an unmarked enemy that is now close must hold it")

func test_the_op_is_in_the_condition_dropdown_and_describes_itself() -> void:
	assert_true(BlockCatalog.CONDITION_OPS.has(&"enemy_in_range_without_status"),
		"a condition a preset uses must be one the player can pick")
	assert_eq(BlockCatalog.op_of(_block()), &"enemy_in_range_without_status")
	assert_eq(_block().describe(), "an enemy within 350 units has no Marked")
	assert_eq(_block().operands().size(), 2, "both halves must be editable")

## The Mark row is what this exists for, so the row is asserted rather than
## only the block.
func test_the_siege_masters_mark_row_carries_it() -> void:
	for plan in PresetPlans.for_class(&"siege_master"):
		if plan.id != &"siege_master_mark_default":
			continue
		assert_eq(BlockCatalog.op_of(plan.condition), &"enemy_in_range_without_status")
		assert_eq((plan.condition as EnemyInRangeWithoutStatusBlock).status, CG.Status.MARKED)
		assert_eq((plan.condition as EnemyInRangeWithoutStatusBlock).range_units,
			PresetPlans.CASTER_REACH, "the reach is unchanged at 350")
		return
	assert_true(false, "the Mark row is gone")
