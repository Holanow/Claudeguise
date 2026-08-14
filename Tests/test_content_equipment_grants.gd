extends "res://Tests/TestCase.gd"

const CG := preload("res://Scripts/Core/CG.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const Plan := preload("res://Scripts/Core/Plan.gd")
const PlanBlock := preload("res://Scripts/Core/PlanBlock.gd")
const PlanInterpreter := preload("res://Scripts/Plans/PlanInterpreter.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")
const EquipmentDef := preload("res://Scripts/Core/EquipmentDef.gd")
const Intent := preload("res://Scripts/Core/Intent.gd")

## Issues 100 and 99: equipment that grants an action, and the Warrior's
## self-sustain that replaces the action it grants.
##
## **Why this file runs fights and builds real pawns instead of checking
## tables.** `EquipmentDef.granted_actions` existed from issue 39 and every one
## of the seventeen registered items left it empty, so nothing ever proved the
## field reached anything. Equipment was the first built-and-unreachable thing
## found on this project. A test that asserts `plate_mail.granted_actions ==
## [warrior_block]` would have passed on the day this shipped and told nobody
## whether wearing plate does anything.
##
## The load-bearing pair is `test_a_warrior_without_plate_cannot_block` and
## `test_a_warrior_wearing_plate_can_block`. Either alone is worthless: the first
## also passes if Block is broken for everyone, the second also passes if Block
## fires for everyone. Only together do they say "the item is what did it".

const SEEDS := 6

func _warrior() -> PawnData:
	return PawnFactory.make_starter_pawn(&"warrior", &"warrior_0", "Warrior")

func _party() -> Array[PawnData]:
	var out: Array[PawnData] = []
	for cid in Registry.all_class_ids():
		if cid == &"geysermancer":
			continue
		out.append(PawnFactory.make_starter_pawn(cid, StringName("%s_%d" % [cid, out.size()]), String(cid)))
	return out

# ---------------------------------------------------------------------------
# the grant itself
# ---------------------------------------------------------------------------

func test_plate_mail_grants_directional_block() -> void:
	var plate := Registry.get_equipment(&"plate_mail")
	assert_not_null(plate, "plate_mail is not registered")
	assert_true(plate.granted_actions.has(&"warrior_block"),
		"README's armor table says Plate Mail | Tank | Block")
	assert_not_null(Registry.get_action(&"warrior_block"),
		"plate_mail grants an action that does not exist")

## The negative half, and the one that would have caught the original defect:
## before this issue every item granted nothing, so "at least one item grants
## something" is the assertion that was silently false for the whole life of the
## field.
func test_at_least_one_registered_item_grants_an_action() -> void:
	var granting := 0
	for id in Registry.all_equipment_ids():
		if not Registry.get_equipment(id).granted_actions.is_empty():
			granting += 1
	assert_true(granting > 0,
		"no registered item grants any action, so granted_actions is unreachable again")

func test_every_granted_action_resolves() -> void:
	for id in Registry.all_equipment_ids():
		for action_id in Registry.get_equipment(id).granted_actions:
			assert_not_null(Registry.get_action(action_id),
				"item %s grants unknown action %s" % [id, action_id])

# ---------------------------------------------------------------------------
# the grant reaching a pawn
# ---------------------------------------------------------------------------

## `Registry.actions_for_pawn` is what the plan editor and the fight must both
## read, so that what a player can plan and what a pawn can do cannot diverge.
func test_equipping_plate_adds_block_to_what_the_pawn_can_do() -> void:
	var pawn := _warrior()
	assert_false(Registry.actions_for_pawn(pawn).has(&"warrior_block"),
		"a bare Warrior should not have Block -- issue 99 took it off the class")
	pawn.armor = Registry.get_equipment(&"plate_mail")
	assert_true(Registry.actions_for_pawn(pawn).has(&"warrior_block"),
		"wearing plate should grant Block")

func test_the_union_keeps_every_class_action_too() -> void:
	var pawn := _warrior()
	pawn.armor = Registry.get_equipment(&"plate_mail")
	var available := Registry.actions_for_pawn(pawn)
	for action_id in pawn.pawn_class.starting_actions:
		assert_true(available.has(action_id),
			"equipping something dropped class action %s" % action_id)

## An equipped item must reach the *fight*, not only a content helper.
func test_a_summoned_fight_gives_the_plate_wearer_block() -> void:
	var party := _party()
	for p in party:
		if p.pawn_class.id == &"warrior":
			p.armor = Registry.get_equipment(&"plate_mail")
	var state := CombatSim.build(party, Registry.get_encounter(&"floor1_room1"), 0)
	var found := false
	for u in state.units:
		if u.pawn != null and u.pawn.pawn_class.id == &"warrior":
			found = true
			assert_true(u.actions.has(&"warrior_block"),
				"the Warrior is wearing plate but the fight did not give it Block")
	assert_true(found, "no Warrior was built into the fight")

# ---------------------------------------------------------------------------
# the pair that proves the item is what did it
# ---------------------------------------------------------------------------

## Fires a Block plan at a Warrior that does not own Block. It must decline.
##
## Before issue 100 nothing checked action ownership anywhere: `PlanInterpreter`
## resolved straight out of `Registry`, so this plan fired happily on a pawn
## wearing nothing, and equipping the item changed precisely nothing observable.
func test_a_warrior_without_plate_cannot_block() -> void:
	var intent := _decide_with_block_plan(_warrior())
	assert_true(intent == null,
		"a Warrior owning no Block still fired one, so equipping plate means nothing")

func test_a_warrior_wearing_plate_can_block() -> void:
	var pawn := _warrior()
	pawn.armor = Registry.get_equipment(&"plate_mail")
	var intent := _decide_with_block_plan(pawn)
	assert_not_null(intent, "a Warrior wearing plate should be able to Block")
	if intent != null:
		assert_eq(intent.action_id, &"warrior_block", "fired the wrong action")

## One pawn, one plan, one decision -- the same plan both ways, so the only
## difference between the two tests above is the armour.
func _decide_with_block_plan(pawn: PawnData) -> Intent:
	var state := CombatState.new(0)
	var self_unit := CombatUnit.new()
	self_unit.id = 0
	self_unit.team = CG.Team.PLAYER
	self_unit.hp_max = 100
	self_unit.hp = 100
	self_unit.resource_max = 100
	self_unit.resource = 100
	self_unit.pawn = pawn
	self_unit.actions = Registry.actions_for_pawn(pawn)
	state.units.append(self_unit)
	var enemy := CombatUnit.new()
	enemy.id = 1
	enemy.team = CG.Team.ENEMY
	enemy.hp_max = 100
	enemy.hp = 100
	enemy.position = Vector2(50.0, 0.0)
	state.units.append(enemy)

	var plan := Plan.new()
	plan.id = &"equipment_block_probe"
	plan.display_name = "Block"
	plan.condition = _block_of(PlanBlock.Kind.CONDITION, &"always", {})
	var blocks: Array[PlanBlock] = []
	blocks.append(_block_of(PlanBlock.Kind.TARGETING, &"target_self", {}))
	blocks.append(_block_of(PlanBlock.Kind.ACTION, &"use_action", {"action_id": &"warrior_block"}))
	plan.blocks = blocks
	pawn.plans = [plan]
	return PlanInterpreter.decide(state, self_unit)

# ---------------------------------------------------------------------------
# issue 99: the Warrior's second wind
# ---------------------------------------------------------------------------

func test_the_warrior_traded_block_for_second_wind() -> void:
	var warrior := Registry.get_class_def(&"warrior")
	assert_false(warrior.starting_actions.has(&"warrior_block"),
		"Block should come from plate now, not from the class")
	assert_true(warrior.starting_actions.has(&"warrior_second_wind"),
		"the Warrior should have gained a self-sustain")

## Self-only, and asserted through the field that makes it so rather than by
## naming the action: a heal with no reach can only land on its caster.
func test_second_wind_is_self_only_and_gated() -> void:
	var a := Registry.get_action(&"warrior_second_wind")
	assert_not_null(a, "warrior_second_wind is not registered")
	assert_true(a.heals, "a second wind should heal")
	assert_almost_eq(a.range_units, 0.0, 0.0001, "a self-heal should have no reach")
	assert_true(a.cooldown_ticks > 0,
		"without a cooldown a free self-heal wins every decide() tick forever")

## The whole-fight half. A green declaration test above cannot tell whether the
## ability is ever cast, which is exactly how warrior_execute sat unreachable
## for its entire existence.
func test_second_wind_actually_fires_and_heals_in_a_real_fight() -> void:
	var fires := 0
	var heals := 0
	for s in SEEDS:
		var state := CombatSim.build(_party(), Registry.get_encounter(&"floor1_warden"), s)
		CombatSim.run(state)
		for e in state.events:
			if e.action_id != &"warrior_second_wind":
				continue
			if e.kind == CG.EventKind.ACTION_FIRE:
				fires += 1
			elif e.kind == CG.EventKind.HEAL:
				heals += 1
	assert_true(fires > 0,
		"Second Wind never fired in %d real fights -- it is unreachable" % SEEDS)
	assert_true(heals > 0,
		"Second Wind fired %d times and healed nothing" % fires)

func _block_of(kind: PlanBlock.Kind, op: StringName, args: Dictionary) -> PlanBlock:
	var b := PlanBlock.new()
	b.kind = kind
	b.op = op
	b.args = args
	return b
