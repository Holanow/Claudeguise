extends "res://Tests/TestCase.gd"


## **Issue 376: a plan edit was accepted, echoed back, and the fight came out
## byte-identical.** The plan editor writes one number into a block and
## nothing in the suite asserted that number reaches a fight, which is the loop
## the whole game is built on. This file is that assertion.

## Goblins, because they do not taunt: `CombatSim._decide_phase` takes the
## compulsion branch before the plan layer, so a taunter in the room can stop
## every plan being read at all and would mask what this file measures.
func _enemies() -> Array[Dictionary]:
	return [
		{"enemy_id": &"goblin", "position": Vector2(120.0, -40.0)},
		{"enemy_id": &"goblin", "position": Vector2(120.0, 40.0)},
		{"enemy_id": &"goblin", "position": Vector2(150.0, 0.0)},
	]

const _SEED := 7

func test_a_condition_value_edit_changes_the_fight() -> void:
	var never := _fight(0.05)
	var eager := _fight(0.95)
	assert_eq(never["casts"], 0, "gated at 5% hp the row must never reach its action")
	assert_true(eager["casts"] > 0, "gated at 95%% hp the row must fire; it fired %d times" % eager["casts"])
	assert_ne(
		eager["signature"], never["signature"],
		"the same seed produced the same event stream at 5% and at 95%, so the edited number never reached the simulation"
	)

## The negative half. Without this, the test above passes for a fight that is
## simply not deterministic, which would tell nobody anything.
func test_the_same_value_twice_is_the_same_fight() -> void:
	assert_eq(_fight(0.95)["signature"], _fight(0.95)["signature"], "the same plan and seed must replay identically")

# ---------------------------------------------------------------------------

## One fight, with the Warrior carrying exactly one plan: heal itself when its
## hp is below `fraction`. `fraction` is the number the plan editor's SpinBox
## writes, and the only thing that differs between two runs here.
func _fight(fraction: float) -> Dictionary:
	var pawn := PawnFactory.make_starter_pawn(&"warrior", &"warrior_0", "Warrior")
	var condition := PlanFixtures.block(&"self_hp_below_fraction", {"fraction": fraction})
	var targeting := PlanFixtures.block(&"target_self")
	var action := PlanFixtures.block(&"use_action", {"action_id": &"warrior_second_wind"})
	var plan := Plan.new()
	plan.id = &"heal_when_hurt"
	plan.display_name = "Heal when hurt"
	plan.condition = condition as ConditionBlock
	plan.blocks = [targeting, action] as Array[PlanBlock]
	pawn.plans = [plan] as Array[Plan]

	var encounter := Encounter.new()
	encounter.id = &"test_plan_edit"
	encounter.party_spawns = [Vector2(-120.0, 0.0)] as Array[Vector2]
	encounter.enemy_spawns = _enemies()

	var state := CombatSim.build([pawn] as Array[PawnData], encounter, _SEED)
	CombatSim.run(state)

	var casts := 0
	var parts := PackedStringArray()
	for e in state.events:
		if e.source_plan == plan.id:
			casts += 1
		parts.append("%d:%d:%d:%d:%s:%d" % [e.tick, e.kind, e.source_id, e.target_id, e.action_id, e.amount])
	return {"casts": casts, "signature": "|".join(parts)}
