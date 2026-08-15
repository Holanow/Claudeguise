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
const Plan := preload("res://Scripts/Core/Plan.gd")
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


## Issue 52: Warrior ships three, not two. SHIELDING has no path from the
## game to a player without a preset plan (the plan editor is deferred), so
## warrior_block needed a third slot rather than replacing warrior_guard's
## or warrior_taunt's already-tuned ones -- both stay, disclosed in
## starting_classes.gd's own WIS 4->6 note (the budget the third plan needed
## a raise for) and PresetPlans.gd's own comment on warrior_block_default.
##
## Priest ships four: the player's own "one for speed, one for resistance"
## direction (priest_haste, priest_ward) added two plans on top of the
## original heal/smite pair, same reasoning and the same WIS-budget-raise
## shape as the Warrior's own third plan -- see starting_classes.gd's WIS
## 5->8 note.
##
## Issue 79: Warrior ships four. warrior_execute had no preset plan at all
## after issue 30 deleted `warrior_execute_when_raging`, and DefaultBehavior
## never picks it (no ranged action in the kit, so `_choose_attack_action`
## always falls back to warrior_strike) -- so the action fired zero times in
## 210 real fights. A preset plan is once again the only path from the game to
## it. Same WIS-budget-raise shape as the two entries above; see
## starting_classes.gd's own WIS 6->8 note.
##
## Every other class keeps the original two-plan invariant.
##
## Issue 87: Geysermancer ships three. `geyser_cleanse` is ally-targeted, and
## `DefaultBehavior` cannot reach an ally-targeted action for this class at all,
## so -- exactly like warrior_execute and warrior_block before it -- a preset
## plan is the only path from the game to the ability. Measured, not assumed:
## swift's `Tools/CleanseWindow.gd` fired a *free* cleanse zero times in 210
## real fights when it sat in `starting_actions` and nowhere else. Unlike those
## two this needed no WIS raise: three plans at 2 blocks each is exactly the
## WIS-6 budget this class already had.
##
## Issue 206: Abomination ships three. Same shape as every entry above -- the
## Sickle grants `abomination_claw` and Claw fired **zero** times, so a preset
## plan is the only path from the game to it. Measured twice before settling:
## "Claw while you cannot afford a Hook" fired 3 times in 80 fights, because this
## class sits under Hook's cost for 0.2% of its alive ticks; "Claw whoever is not
## poisoned" fires 260. WIS 4 -> 6 for the third plan, the same pure-capacity
## raise the Warrior and Priest entries above record.
##
## Issue 160: Warrior ships five. `warrior_block` has now been rescued from
## unreachability three times -- issue 52 filed it existing and never firing,
## issue 99 moved it onto `plate_mail` and deleted its plan in the same commit,
## and swift then measured 0 SHIELDING and 0 BLOCKED across 40 seeds of 7
## encounters. `DefaultBehavior` cannot reach a zero-power self-buff, so a preset
## plan is the only path, and four plans at 2 blocks each sat exactly at the
## WIS-8 budget. WIS 8 -> 10, the same pure-capacity raise this class's own entry
## records at 4 -> 6 and 6 -> 8, and `Balance.plan_block_budget` is still the only
## reader of WIS anywhere in `Scripts/`.
##
## Issue 219: Abomination ships four. `abomination_immolate` is the only
## sustained action in the game, so it is the only thing that can produce a
## `SUSTAIN_START` or a `SUSTAIN_END` -- two event kinds that had rendered
## correct log lines and fired zero times in 100 fights since #61. It cannot
## arrive through `DefaultBehavior`: that layer is deliberately blind to
## sustained actions now (see `_attack_candidates`), because a channel lit by the
## fallback is a pawn holding an aura for a reason written in no plan. WIS 6 -> 8,
## the same pure-capacity raise this class's own 4 -> 6 entry records.
const _EXPECTED_PLAN_COUNT := {
	&"warrior": 5,
	&"priest": 4,
	&"geysermancer": 3,
	&"abomination": 4,
}

func test_every_class_ships_its_expected_preset_plans_within_its_wis_budget() -> void:
	for id in EXPECTED_CLASS_IDS:
		var plans := PresetPlans.for_class(id)
		var expected: int = _EXPECTED_PLAN_COUNT.get(id, 2)
		assert_eq(plans.size(), expected, "%s should ship exactly %d preset plans" % [id, expected])
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
	# taunt to land (cast + travel time) and an enemy to commit to a target,
	# but not so long that a two-pawn party alone against a full room's worth
	# of enemies runs past the Warrior's own survival time -- issue 30's
	# survivability pass (CON 9->14) measurably extended that, and past it
	# the Warrior's death stops registering it as a living candidate for any
	# enemy re-deciding afterward, which tests a different thing (what
	# happens once the tank is gone) than what this test is checking (does
	# taunt redirect while both are alive). 100 ticks was checked directly:
	# Warrior alive at 163/246 hp, no false failure from this effect.
	for i in 100:
		CombatSim.step(state)
	var warrior_unit := state.unit(0)
	assert_true(warrior_unit.alive, "expected the Warrior to still be alive at 100 ticks")
	assert_true(warrior_unit.has_status(CG.Status.TAUNTING), "expected the Warrior to have cast its default taunt plan within 100 ticks")
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


## Issue 30, second pass: a taunting Warrior that dies inside its own taunt
## window is a worse tank than one that never taunted (rook's framing).
## `no_abomination`'s own boss fight measured the Warrior dying to The
## Warden at tick 203 of a 240-tick taunt, both before and after several
## CON values up to 35 -- proof CON alone does not fix that specific comp,
## reported in the PR rather than a claim this test could cheaply stand in
## for (a single pawn vs a real boss is a different, larger scenario). What
## this test checks instead, cheaply and directly: warrior_guard's own
## trigger. Raised 0.35->0.65 so a Warrior takes real proactive cover after
## one meaningful hit rather than needing to already be almost dead --
## checked against the exact number rather than trusting the comment above
## the constant to stay true.
func test_warrior_guards_proactively_not_only_when_nearly_dead() -> void:
	var warrior := PawnFactory.make_starter_pawn(&"warrior", &"warrior", "Warrior")
	var plans := PresetPlans.for_class(&"warrior")
	var guard_plan: Plan = null
	for p in plans:
		if p.id == &"warrior_guard_when_hurt":
			guard_plan = p
	assert_not_null(guard_plan, "expected warrior to still ship a guard-when-hurt plan")
	assert_not_null(guard_plan.condition, "expected warrior_guard_when_hurt to carry a trigger condition")
	assert_eq(guard_plan.condition.op, &"self_hp_below_fraction")
	var fraction := float(guard_plan.condition.args.get("fraction", 0.0))
	assert_true(fraction >= 0.5, "guard should trigger well before critical, got a %.0f%% threshold" % (fraction * 100.0))


## Real numbers, not just a shape check: CON 9->14 measurably raised
## warrior_strike's own damage_reduction, which is the other half of
## issue 30's survivability pass alongside the guard threshold above.
func test_warrior_con_gives_real_extra_damage_reduction() -> void:
	var warrior := PawnFactory.make_starter_pawn(&"warrior", &"warrior", "Warrior")
	var unit := CombatUnit.new()
	unit.pawn = warrior
	var reduction := Balance.damage_reduction(unit)
	assert_true(reduction >= 0.14, "expected at least 14%% natural reduction from CON 14, got %.0f%%" % (reduction * 100.0))
