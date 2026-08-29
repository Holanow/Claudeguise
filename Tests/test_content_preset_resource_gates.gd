extends "res://Tests/TestCase.gd"


## Issue 824. A preset row that gates on Mana states a number the player reads
## as "this fires from here up". `_action_can_fire` then refuses it on cost with
## nothing on screen, so a gate below the action's cost is a lie for the whole
## window between the two -- `siege_master_build_when_ready` gated at 25 against
## a 40-Mana summon. A gate above the class's Mana ceiling is the same lie with
## no window at all.

func test_every_resource_gate_covers_its_own_action_and_is_reachable() -> void:
	var checked := 0
	for class_id in ClassLibrary.all_ids():
		var def := ClassLibrary.get_class_def(class_id)
		if def == null:
			continue
		var ceiling := Balance.max_resource(PawnFactory.make_preset_pawn(class_id, &"probe", "probe"))
		for plan in PresetPlans.for_class(class_id):
			if not (plan.condition is SelfResourceAtLeastBlock):
				continue
			var action := _action_of(plan)
			if action == null:
				continue
			var gate := (plan.condition as SelfResourceAtLeastBlock).amount
			checked += 1
			assert_true(gate >= action.resource_cost,
				"%s gates at %d but %s costs %d, so the row is selected and silently refused between them" % [
					plan.id, gate, action.id, action.resource_cost])
			assert_true(gate <= ceiling,
				"%s gates at %d, above the %s's %d maximum, so the row can never fire" % [
					plan.id, gate, class_id, ceiling])
	assert_true(checked > 0, "no preset row gates on resource -- this check saw nothing and proved nothing")

func _action_of(plan) -> ActionDef:
	for b in plan.blocks:
		if b is UseActionBlock:
			return (b as UseActionBlock).action
	return null
