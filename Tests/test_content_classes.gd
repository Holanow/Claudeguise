extends "res://Tests/TestCase.gd"

const CG := preload("res://Scripts/Core/CG.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const Balance := preload("res://Scripts/Content/Balance.gd")
const PresetPlans := preload("res://Scripts/Content/PresetPlans.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")
const PlanInterpreter := preload("res://Scripts/Plans/PlanInterpreter.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")
const PlanBlock := preload("res://Scripts/Core/PlanBlock.gd")
const Terrain := preload("res://Scripts/Core/Terrain.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")

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


## Every action a player can actually see (starting_actions of a real class)
## has a real description -- pike's inspect screen shows "(no description
## yet)" for anything empty, and an empty description is a defect per
## ActionDef's own doc comment, not a default.
func test_every_playable_classs_action_has_a_description() -> void:
	for id in EXPECTED_CLASS_IDS:
		var c := Registry.get_class_def(id)
		for action_id in c.starting_actions:
			var action := Registry.get_action(action_id)
			assert_false(action.description.is_empty(), "%s (used by %s) has no description" % [action_id, id])


## Issue 14a: walks every real preset plan (from PresetPlans, not a hand-typed
## list) and proves PlanInterpreter never orders a shot it already knows will
## miss. Each plan runs in isolation (on a pawn carrying only that one plan)
## against a deliberately adversarial state: a hurt ally and a hurt enemy both
## placed far away (5000 units), plus, for an enemy_in_range condition, a
## second full-health enemy placed exactly at the condition's own range so the
## condition can genuinely hold. If decide() fires at all, its target must be
## within the fired action's range_units — that is the one invariant this
## checks, regardless of which condition or targeting op the plan uses.
func test_no_preset_plan_ever_orders_an_out_of_range_shot() -> void:
	var checked := 0
	for class_id in EXPECTED_CLASS_IDS:
		for plan in PresetPlans.for_class(class_id):
			checked += 1
			var state := CombatState.new(0)
			var self_unit := _adversarial_self(plan.condition)
			state.units.append(self_unit)

			var far_ally := _unit(1, CG.Team.PLAYER, Vector2(5000.0, 0.0), 10)
			state.units.append(far_ally)
			var far_enemy := _unit(2, CG.Team.ENEMY, Vector2(0.0, 5000.0), 10)
			state.units.append(far_enemy)

			if plan.condition != null and plan.condition.op == &"enemy_in_range":
				var cond_range := float(plan.condition.args.get("range", 0.0))
				var near_enemy := _unit(3, CG.Team.ENEMY, Vector2(cond_range * 0.9, 0.0), 100)
				state.units.append(near_enemy)

			var pawn := PawnFactory.make_starter_pawn(class_id, class_id, String(class_id))
			pawn.plans = [plan]
			self_unit.pawn = pawn
			self_unit.actions = pawn.pawn_class.starting_actions.duplicate()

			var intent := PlanInterpreter.decide(state, self_unit)
			if intent == null or intent.kind != CG.IntentKind.USE_ACTION:
				continue

			var action := Registry.get_action(intent.action_id)
			var target := state.unit(intent.target_id)
			assert_not_null(action, "%s plan %s fired an unknown action" % [class_id, plan.id])
			assert_not_null(target, "%s plan %s fired at an unknown target id" % [class_id, plan.id])
			if action != null and target != null:
				var dist := self_unit.position.distance_to(target.position)
				assert_true(dist <= action.range_units, "%s plan %s ordered a shot at distance %.1f beyond its action's range %.1f" % [class_id, plan.id, dist, action.range_units])
	assert_true(checked >= 10, "expected to walk at least 10 real preset plans, walked %d" % checked)


func _unit(id: int, team: CG.Team, pos: Vector2, hp: int) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.position = pos
	u.hp_max = 100
	u.hp = hp
	u.resource_max = 1000
	u.resource = 0
	u.focus_id = -1
	return u


## A self unit configured, from the plan's own condition, to make that
## condition hold — so the test actually exercises the firing path rather than
## trivially passing because the condition never triggers.
func _adversarial_self(condition: PlanBlock) -> CombatUnit:
	var u := _unit(0, CG.Team.PLAYER, Vector2.ZERO, 100)
	if condition == null:
		return u
	match condition.op:
		&"self_hp_below_fraction":
			var fraction := float(condition.args.get("fraction", 1.0))
			u.hp = maxi(1, int(u.hp_max * fraction * 0.5))
		&"self_resource_at_least":
			var amount := int(condition.args.get("amount", 0))
			u.resource_max = amount + 100
			u.resource = amount + 50
	return u


func test_enemy_room_is_registered_and_populated() -> void:
	var enc := Registry.get_encounter(&"floor1_room1")
	assert_not_null(enc)
	assert_false(enc.enemy_spawns.is_empty())
	assert_eq(enc.party_spawns.size(), 4)
	for spawn in enc.enemy_spawns:
		var enemy_id: StringName = spawn.get("enemy_id", &"")
		assert_not_null(Registry.get_enemy(enemy_id), "encounter references unknown enemy %s" % enemy_id)


## Skeleton addition: the party deploys in the left third of the arena so
## traversal and range still matter on tick one. Walks the real registry
## rather than a typed list of encounter ids, so a future encounter is
## covered automatically.
func test_every_encounters_party_spawns_stay_in_the_deploy_zone() -> void:
	var checked := 0
	for encounter_id in Registry.all_encounter_ids():
		var enc := Registry.get_encounter(encounter_id)
		for spawn in enc.party_spawns:
			checked += 1
			assert_true((spawn as Vector2).x <= CG.party_deploy_max_x(), "%s has a party spawn at x=%.1f, past the deploy limit of %.1f" % [encounter_id, (spawn as Vector2).x, CG.party_deploy_max_x()])
	assert_true(checked > 0, "expected at least one party spawn to check")


## Issue 13b criterion 2: no room may spawn a unit inside a WALL or PIT.
## `Terrain.point_is_blocked` is the same check the simulation itself uses for
## movement, at radius 0 -- a spawn point exactly inside a wall's rect fails
## this the same way it would fail to walk there.
func test_no_encounter_spawns_a_unit_inside_a_wall_or_pit() -> void:
	var checked := 0
	for encounter_id in Registry.all_encounter_ids():
		var enc := Registry.get_encounter(encounter_id)
		if enc.terrain.is_empty():
			continue
		for spawn in enc.party_spawns:
			checked += 1
			assert_false(Terrain.point_is_blocked(enc.terrain, spawn, 0.0), "%s has a party spawn inside a wall/pit at %s" % [encounter_id, spawn])
		for enemy_spawn in enc.enemy_spawns:
			var pos: Vector2 = enemy_spawn.get("position", Vector2.ZERO)
			checked += 1
			assert_false(Terrain.point_is_blocked(enc.terrain, pos, 0.0), "%s has an enemy spawn inside a wall/pit at %s" % [encounter_id, pos])
	assert_true(checked > 0, "expected at least one encounter with terrain to check")


## Issue 30: warrior_taunt's own shape. The mechanism (TAUNTING,
## taunt_radius, DefaultBehavior._nearest_taunter) already has its own
## tests; this checks the content built against it.
func test_warrior_taunt_action_shape() -> void:
	var a := Registry.get_action(&"warrior_taunt")
	assert_not_null(a)
	assert_eq(a.range_units, 0.0, "self-targeted, matching how it is cast (target_self)")
	assert_true(a.applies_status_enabled)
	assert_eq(a.applies_status, CG.Status.TAUNTING)
	assert_true(a.taunt_radius > 0.0, "a taunt with no radius taunts nothing")
	assert_eq(a.status_duration_ticks, a.cooldown_ticks, "cooldown must not outlast the buff itself, or uptime has a gap; must not undercut it either, or it refreshes before lapsing")
	assert_eq(a.resource_cost, 0, "must be castable before any Rage has built, at the start of a fight")


## Real end-to-end proof, not just a shape check: a Warrior actually holding
## an enemy's attention onto itself and off a squishier ally, through a real
## CombatSim.step() loop -- the same claim issue 30 makes about what fixes
## the Siege Master's own engine, checked against the mechanism it borrows
## rather than assumed to work because the pieces exist.
func test_a_taunting_warrior_draws_a_real_enemy_off_a_squishier_ally() -> void:
	var warrior := PawnFactory.make_starter_pawn(&"warrior", &"warrior", "Warrior")
	var geysermancer := PawnFactory.make_starter_pawn(&"geysermancer", &"geysermancer", "Geysermancer")
	var party: Array[PawnData] = [warrior, geysermancer]
	var encounter := Registry.get_encounter(&"floor1_room1")
	var state := CombatSim.build(party, encounter, 1)
	# Both start together; let the fight run long enough for the Warrior's
	# taunt to land (cast + travel time) and an enemy to commit to a target.
	for i in 200:
		CombatSim.step(state)
	var warrior_unit := state.unit(0)
	assert_true(warrior_unit.has_status(CG.Status.TAUNTING), "expected the Warrior to have cast its default taunt plan within 200 ticks")
	var enemies_focused_on_warrior := 0
	var enemies_focused_on_geysermancer := 0
	for u in state.units:
		if u.team != CG.Team.ENEMY or not u.alive:
			continue
		if u.focus_id == warrior_unit.id:
			enemies_focused_on_warrior += 1
		elif u.focus_id == 1:
			enemies_focused_on_geysermancer += 1
	assert_true(enemies_focused_on_warrior > 0, "expected at least one living enemy focused on the taunting Warrior")
	# Not asserting zero on the Geysermancer: floor1_room1 spreads enemies
	# across a real room, and one far enough away to be outside the
	# Warrior's own taunt_radius is a legitimate case, not a bug -- taunt
	# reaches what it reaches, it does not blanket the whole encounter.
	# The real claim is that taunt clearly wins the room, not that it wins
	# every single enemy regardless of distance.
	assert_true(enemies_focused_on_warrior > enemies_focused_on_geysermancer, "a taunting Warrior in range should pull most of the room off the Geysermancer, got %d on the Warrior vs %d still on the Geysermancer" % [enemies_focused_on_warrior, enemies_focused_on_geysermancer])
