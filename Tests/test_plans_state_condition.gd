extends "res://Tests/TestCase.gd"


## **Issue 495: a pawn's state as a first-class thing a CONDITION can ask
## about.** Cover is the first pair; the seam is the deliverable, so the table
## itself is asserted here as well as the pair it currently holds.

const _SEED := 11

# ---------------------------------------------------------------------------
# The seam. These assertions are about `STATE_CONDITIONS` rather than about
# cover, and they are what makes the next state one table entry plus one static
# func.

func test_every_state_in_the_table_reaches_the_editor_and_the_interpreter() -> void:
	assert_true(PlanInterpreter.STATE_CONDITIONS.size() >= 4, "the table lost its entries")
	for op in PlanInterpreter.STATE_CONDITIONS:
		var entry: Dictionary = PlanInterpreter.STATE_CONDITIONS[op]
		assert_true(PlanInterpreter.CONDITION_OPS.has(op), "%s must be in the condition dropdown" % op)
		assert_eq(String(PlanInterpreter.CONDITION_ARG_SHAPE[op].get("kind", "")), "none",
			"a state takes no argument, so the editor must not build a value box for %s" % op)
		assert_eq(PlanInterpreter.describe_op(op, {}), String(entry["text"]),
			"%s's sentence must come from the table, or the row reads as a bug" % op)
		assert_true((entry["holds"] as Callable).is_valid(), "%s has no predicate" % op)

## The other half of the derivation: nothing is in the whitelist twice, and
## nothing is in it that neither table names.
func test_the_whitelist_is_exactly_the_two_tables() -> void:
	var seen := {}
	for op in PlanInterpreter.CONDITION_OPS:
		assert_false(seen.has(op), "%s is in CONDITION_OPS twice" % op)
		seen[op] = true
		assert_true(PlanInterpreter.VALUE_CONDITION_OPS.has(op) or PlanInterpreter.STATE_CONDITIONS.has(op),
			"%s is in the whitelist and in neither table" % op)
	for op in PlanInterpreter.STATE_CONDITIONS:
		assert_false(PlanInterpreter.VALUE_CONDITION_OPS.has(op), "%s is both a state and a value condition" % op)

# ---------------------------------------------------------------------------
# The predicate

func test_the_cover_pair_reads_cover_from_the_focus() -> void:
	var state := _state_with_a_wall()
	var unit := state.unit(0)

	assert_true(_holds(state, unit, &"self_in_cover"), "the wall is between the pawn and its focus")
	assert_false(_holds(state, unit, &"self_not_in_cover"), "the pair must not both hold")

	unit.position = Vector2(0.0, 200.0)
	assert_false(_holds(state, unit, &"self_in_cover"), "clear line to the focus")
	assert_true(_holds(state, unit, &"self_not_in_cover"), "the pair must not both fail")

## Cover is from the focus and from nobody else, which is the ruling on #495 and
## what `move_into_cover` already does: a second enemy with a clear line does not
## change the answer.
func test_a_second_enemy_with_a_clear_line_does_not_change_the_answer() -> void:
	var state := _state_with_a_wall()
	var unit := state.unit(0)
	var other := _unit(2, CG.Team.ENEMY, Vector2(0.0, 200.0))
	state.units.append(other)
	assert_true(_holds(state, unit, &"self_in_cover"), "the focus is still behind the wall")

## The edge the whole two-row plan rests on: with no focus yet, or a dead one,
## `self_not_in_cover` is the half that holds, so "not in cover -> take cover"
## fires on the first tick of a fight and again when the focus dies.
func test_no_focus_and_a_dead_focus_are_both_not_in_cover() -> void:
	var state := _state_with_a_wall()
	var unit := state.unit(0)

	unit.focus_id = -1
	assert_false(_holds(state, unit, &"self_in_cover"), "nothing to be in cover from")
	assert_true(_holds(state, unit, &"self_not_in_cover"), "the pair must stay a strict complement")

	unit.focus_id = 1
	state.unit(1).hp = 0
	state.unit(1).alive = false
	assert_false(_holds(state, unit, &"self_in_cover"), "a dead focus is not cover")
	assert_true(_holds(state, unit, &"self_not_in_cover"))

## The ground pair moved into the same table and must still answer the same way.
func test_the_ground_pair_still_reads_the_ground() -> void:
	var state := CombatState.new(_SEED)
	state.terrain = [Terrain.hazard(Rect2(-10.0, -10.0, 20.0, 20.0), 2, CG.DamageType.FIRE)]
	var unit := _unit(0, CG.Team.PLAYER, Vector2.ZERO)
	state.units.append(unit)
	assert_true(_holds(state, unit, &"self_on_harmful_ground"))
	assert_false(_holds(state, unit, &"self_on_safe_ground"))

# ---------------------------------------------------------------------------
# The loop. #381's shape: the edit must reach the simulation.

## Any row, any action, anywhere in the stack -- the pair is asked here on a row
## carrying an ordinary attack and no MOVEMENT block at all.
func test_an_in_cover_row_fires_its_action_with_no_movement_block() -> void:
	var state := _state_with_a_wall()
	var unit := state.unit(0)
	unit.actions = [&"warrior_guard"] as Array[StringName]
	unit.resource = 100
	unit.pawn = PawnFactory.make_starter_pawn(&"warrior", &"warrior_0", "Warrior")
	unit.pawn.plans = [_act_plan(&"self_in_cover", &"warrior_guard")] as Array[Plan]

	var intent := PlanInterpreter.decide(state, unit)
	assert_not_null(intent, "in cover, the row must fire")
	assert_eq(intent.kind, CG.IntentKind.USE_ACTION)

	unit.position = Vector2(0.0, 200.0)
	assert_eq(PlanInterpreter.decide(state, unit), null, "out of cover, the same row must not fire")

## Issue 481's own case, end to end: a pawn that reaches cover and has a row
## naming that state casts from it, and the same party with the state row's
## condition inverted casts nothing. Two real fights on the room #481 measured.
func test_the_pair_gives_the_pawn_in_cover_something_to_do() -> void:
	assert_true(_casts_from_cover(&"self_in_cover") > 0,
		"the in-cover row never fired, so the condition did not reach the simulation")
	assert_eq(_casts_from_cover(&"self_on_harmful_ground"), 0,
		"the same row gated on a state that never holds must never fire")

# ---------------------------------------------------------------------------

func _casts_from_cover(op: StringName) -> int:
	var party: Array[PawnData] = []
	for cid in [&"geysermancer", &"priest", &"siege_master", &"warrior"]:
		var pawn := PawnFactory.make_preset_pawn(cid, StringName("%s_0" % cid), String(cid))
		if cid == &"geysermancer":
			pawn.plans.remove_at(pawn.plans.size() - 1)
			pawn.plans.remove_at(pawn.plans.size() - 1)
			pawn.plans.insert(0, _act_plan(op, &"geyser_scald"))
			pawn.plans.insert(0, _cover_plan())
		party.append(pawn)

	var state := CombatSim.build(party, Registry.get_encounter(&"floor1_cover"), _SEED)
	CombatSim.run(state)
	var casts := 0
	for e in state.events:
		if e.source_plan == &"cover_act":
			casts += 1
	return casts

## A wall on the x axis, a focus beyond it, and the pawn behind it.
func _state_with_a_wall() -> CombatState:
	var state := CombatState.new(_SEED)
	state.terrain = [Terrain.make(Terrain.Kind.WALL, Rect2(-20.0, -20.0, 40.0, 40.0))]
	var unit := _unit(0, CG.Team.PLAYER, Vector2(-100.0, 0.0))
	unit.focus_id = 1
	state.units.append(unit)
	state.units.append(_unit(1, CG.Team.ENEMY, Vector2(100.0, 0.0)))
	return state

func _unit(id: int, team: CG.Team, at: Vector2) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.position = at
	u.hp_max = 1000
	u.hp = u.hp_max
	return u

func _holds(state: CombatState, unit: CombatUnit, op: StringName) -> bool:
	var plan := Plan.new()
	plan.id = &"probe"
	plan.condition = _block(PlanBlock.Kind.CONDITION, op)
	return PlanInterpreter.condition_holds(state, unit, plan)

func _cover_plan() -> Plan:
	var p := Plan.new()
	p.id = &"cover_move"
	p.display_name = "Take cover"
	p.condition = _block(PlanBlock.Kind.CONDITION, &"self_not_in_cover")
	p.blocks = [
		_block(PlanBlock.Kind.TARGETING, &"target_nearest_enemy"),
		_block(PlanBlock.Kind.MOVEMENT, &"move_into_cover"),
	]
	return p

func _act_plan(op: StringName, action_id: StringName) -> Plan:
	var action := _block(PlanBlock.Kind.ACTION, &"use_action")
	action.args = {"action_id": action_id}
	var p := Plan.new()
	p.id = &"cover_act"
	p.display_name = "Act from cover"
	p.condition = _block(PlanBlock.Kind.CONDITION, op)
	p.blocks = [_block(PlanBlock.Kind.TARGETING, &"target_nearest_enemy"), action]
	return p

func _block(kind, op: StringName) -> PlanBlock:
	var b := PlanBlock.new()
	b.kind = kind
	b.op = op
	return b
