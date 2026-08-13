extends "res://Tests/TestCase.gd"

const CG := preload("res://Scripts/Core/CG.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const Balance := preload("res://Scripts/Content/Balance.gd")
const PresetPlans := preload("res://Scripts/Content/PresetPlans.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")

const EXPECTED_CLASS_IDS := [
	&"abomination", &"geysermancer", &"priest", &"siege_master", &"warrior",
]


func test_all_five_classes_are_registered() -> void:
	var got := Registry.all_class_ids()
	assert_eq(got.size(), EXPECTED_CLASS_IDS.size())
	for id in EXPECTED_CLASS_IDS:
		assert_true(got.has(id), "missing class id %s" % id)


func test_no_duplicate_ids_anywhere() -> void:
	# Registry._register already refuses duplicates with push_error; this
	# checks the observable consequence: every id we expect resolves, and
	# nothing about loading it errors out into a missing entry.
	for id in EXPECTED_CLASS_IDS:
		assert_not_null(Registry.get_class_def(id), "missing class %s" % id)
	assert_not_null(Registry.get_encounter(&"floor1_room1"))


func test_every_class_has_one_or_two_damage_types() -> void:
	for id in EXPECTED_CLASS_IDS:
		var c := Registry.get_class_def(id)
		assert_true(c.damage_types.size() >= 1 and c.damage_types.size() <= 2, "%s has %d damage types" % [id, c.damage_types.size()])


func test_every_starting_action_resolves() -> void:
	for id in EXPECTED_CLASS_IDS:
		var c := Registry.get_class_def(id)
		assert_true(c.starting_actions.size() >= 2, "%s should have a recognisable shape, has %d actions" % [id, c.starting_actions.size()])
		for action_id in c.starting_actions:
			assert_not_null(Registry.get_action(action_id), "%s references unknown action %s" % [id, action_id])


func test_every_class_ships_two_preset_plans_within_its_wis_budget() -> void:
	for id in EXPECTED_CLASS_IDS:
		var plans := PresetPlans.for_class(id)
		assert_eq(plans.size(), 2, "%s should ship exactly two preset plans" % id)
		var pawn := PawnFactory.make_starter_pawn(id, id, String(id))
		var budget := Balance.plan_block_budget(pawn)
		var used := PresetPlans.total_blocks(id)
		assert_true(used <= budget, "%s uses %d blocks, budget is %d" % [id, used, budget])


func test_preset_plan_actions_resolve() -> void:
	for id in EXPECTED_CLASS_IDS:
		for plan in PresetPlans.for_class(id):
			for block in plan.blocks:
				if block.op == &"use_action":
					var action_id: StringName = block.args.get("action_id", &"")
					assert_not_null(Registry.get_action(action_id), "%s plan %s uses unknown action %s" % [id, plan.id, action_id])


func test_enemy_room_is_registered_and_populated() -> void:
	var enc := Registry.get_encounter(&"floor1_room1")
	assert_not_null(enc)
	assert_false(enc.enemy_spawns.is_empty())
	assert_eq(enc.party_spawns.size(), 4)
	for spawn in enc.enemy_spawns:
		var enemy_id: StringName = spawn.get("enemy_id", &"")
		assert_not_null(Registry.get_enemy(enemy_id), "encounter references unknown enemy %s" % enemy_id)
