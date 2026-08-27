extends "res://Tests/TestCase.gd"


## Issues 100 and 99: equipment that grants an action, and the Warrior's
## self-sustain that replaces the action it grants.

const SEEDS := 6

func _warrior() -> PawnData:
	return PawnFactory.make_starter_pawn(&"warrior", &"warrior_0", "Warrior")

func _party() -> Array[PawnData]:
	var out: Array[PawnData] = []
	for cid in ClassLibrary.all_ids():
		if cid == &"geysermancer":
			continue
		out.append(PawnFactory.make_starter_pawn(cid, StringName("%s_%d" % [cid, out.size()]), String(cid)))
	return out

## The same party carrying its classes' library rows. Issue 522: without this,
## every assertion about a plan-sourced event over `_party()` is vacuous.
func _preset_party() -> Array[PawnData]:
	var out: Array[PawnData] = []
	for cid in ClassLibrary.all_ids():
		if cid == &"geysermancer":
			continue
		out.append(PawnFactory.make_preset_pawn(cid, StringName("%s_%d" % [cid, out.size()]), String(cid)))
	return out

# ---------------------------------------------------------------------------
# the grant itself
# ---------------------------------------------------------------------------

func test_plate_mail_grants_directional_block() -> void:
	var plate := ItemLibrary.get_equipment(&"plate_mail")
	assert_not_null(plate, "plate_mail is not registered")
	assert_true(plate.granted_actions.has(&"warrior_block"),
		"README's armor table says Plate Mail | Tank | Block")
	assert_not_null(ActionLibrary.get_action(&"warrior_block"),
		"plate_mail grants an action that does not exist")

## The negative half, and the one that would have caught the original defect:
func test_at_least_one_registered_item_grants_an_action() -> void:
	var granting := 0
	for id in ItemLibrary.all_ids():
		if not ItemLibrary.get_equipment(id).granted_actions.is_empty():
			granting += 1
	assert_true(granting > 0,
		"no registered item grants any action, so granted_actions is unreachable again")

func test_every_granted_action_resolves() -> void:
	for id in ItemLibrary.all_ids():
		for action_id in ItemLibrary.get_equipment(id).granted_actions:
			assert_not_null(ActionLibrary.get_action(action_id),
				"item %s grants unknown action %s" % [id, action_id])

# ---------------------------------------------------------------------------
# the grant reaching a pawn
# ---------------------------------------------------------------------------

## `ActionLibrary.actions_for_pawn` is what the plan editor and the fight must both
## read, so that what a player can plan and what a pawn can do cannot diverge.
func test_equipping_plate_adds_block_to_what_the_pawn_can_do() -> void:
	var pawn := _warrior()
	pawn.armor = null
	assert_false(ActionLibrary.actions_for_pawn(pawn).has(&"warrior_block"),
		"a bare Warrior should not have Block -- issue 99 took it off the class")
	pawn.armor = ItemLibrary.get_equipment(&"plate_mail")
	assert_true(ActionLibrary.actions_for_pawn(pawn).has(&"warrior_block"),
		"wearing plate should grant Block")

func test_the_union_keeps_every_class_action_too() -> void:
	var pawn := _warrior()
	pawn.armor = ItemLibrary.get_equipment(&"plate_mail")
	var available := ActionLibrary.actions_for_pawn(pawn)
	for action_id in pawn.pawn_class.starting_action_ids():
		assert_true(available.has(action_id),
			"equipping something dropped class action %s" % action_id)

## An equipped item must reach the *fight*, not only a content helper.
func test_a_summoned_fight_gives_the_plate_wearer_block() -> void:
	var party := _party()
	for p in party:
		if p.pawn_class.id == &"warrior":
			p.armor = ItemLibrary.get_equipment(&"plate_mail")
	var state := CombatSim.build(party, RoomLibrary.get_room(&"floor1_room1"), 0)
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
func test_a_warrior_without_plate_cannot_block() -> void:
	var bare := _warrior()
	bare.armor = null
	var intent := _decide_with_block_plan(bare)
	assert_true(intent == null,
		"a Warrior owning no Block still fired one, so equipping plate means nothing")

func test_a_warrior_wearing_plate_can_block() -> void:
	var pawn := _warrior()
	pawn.armor = ItemLibrary.get_equipment(&"plate_mail")
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
	self_unit.actions = ActionLibrary.actions_for_pawn(pawn)
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
	plan.condition = _block_of(&"always", {})
	var blocks: Array[PlanBlock] = []
	blocks.append(_block_of(&"target_self", {}))
	blocks.append(_block_of(&"use_action", {"action_id": &"warrior_block"}))
	plan.blocks = blocks
	pawn.plans = [plan]
	return PlanInterpreter.decide(state, self_unit)

# ---------------------------------------------------------------------------
# issue 99: the Warrior's second wind
# ---------------------------------------------------------------------------

func test_the_warrior_traded_block_for_second_wind() -> void:
	var warrior := ClassLibrary.get_class_def(&"warrior")
	assert_false(warrior.starting_action_ids().has(&"warrior_block"),
		"Block should come from plate now, not from the class")
	assert_true(warrior.starting_action_ids().has(&"warrior_second_wind"),
		"the Warrior should have gained a self-sustain")

## Self-only, and asserted through the field that makes it so rather than by
## naming the action: a heal with no reach can only land on its caster.
func test_second_wind_is_self_only_and_gated() -> void:
	var a := ActionLibrary.get_action(&"warrior_second_wind")
	assert_not_null(a, "warrior_second_wind is not registered")
	assert_true(a.heals, "a second wind should heal")
	assert_almost_eq(a.range_units, 0.0, 0.0001, "a self-heal should have no reach")
	assert_true(a.cooldown_ticks > 0,
		"without a cooldown a free self-heal wins every decide() tick forever")
func _is_basic_attack(action) -> bool:
	return action != null and not action.heals and action.power_scale > 0.0 and action.resource_cost <= 0

func _weapon_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in ItemLibrary.all_ids():
		if ItemLibrary.get_equipment(id).slot == EquipmentDef.Slot.WEAPON:
			out.append(id)
	return out

func test_every_weapon_provides_exactly_one_basic_attack() -> void:
	var weapons := _weapon_ids()
	assert_true(weapons.size() >= 6,
		"expected at least the six base weapon types; found %d" % weapons.size())
	for id in weapons:
		var item := ItemLibrary.get_equipment(id)
		assert_eq(item.granted_actions.size(), 1,
			"%s should provide exactly one attack -- README's Provided Actions column has one entry per weapon, and a weapon granting none is a trap: the pawn holding it has no free action at all" % id)
		var action = ActionLibrary.get_action(item.granted_actions[0])
		assert_true(_is_basic_attack(action),
			"%s provides %s, which is not a free damaging attack" % [id, item.granted_actions[0]])

## The move actually happened. Without this the whole issue can be "done" by
## adding grants and leaving the class copies in place, and every pawn would
## keep attacking exactly as it did with the weapon slot doing nothing.
func test_no_class_still_carries_a_basic_attack_of_its_own() -> void:
	for cid in ClassLibrary.all_ids():
		var def := ClassLibrary.get_class_def(cid)
		for action_id in def.starting_action_ids():
			assert_false(_is_basic_attack(ActionLibrary.get_action(action_id)),
				"%s still ships %s, a free attack of its own -- issue 129 moves those onto weapons" % [cid, action_id])

## Every class starts holding something, and holding something it is allowed to
## hold. A starter equipped with a piece `EquipmentDef.allows` refuses is a pawn
## carrying gear its own equip screen would never have offered it.
func test_every_class_starts_armed_with_a_weapon_it_may_use() -> void:
	for cid in ClassLibrary.all_ids():
		var pawn := PawnFactory.make_starter_pawn(cid, cid, String(cid))
		assert_not_null(pawn.weapon, "%s starts with an empty main hand" % cid)
		if pawn.weapon == null:
			continue
		assert_eq(pawn.weapon.slot, EquipmentDef.Slot.WEAPON,
			"%s starts holding %s, which is not a weapon" % [cid, pawn.weapon.id])
		assert_true(pawn.weapon.allows(pawn.pawn_class.method),
			"%s may not use %s, so the equip screen would never offer it" % [cid, pawn.weapon.id])

## Issue 226, the player's ruling: "every class should have default dress". The
## twin of the weapon test above, and the reason it is asserted rather than read
## off the table is that a sixth class would otherwise ship bare.
func test_every_class_starts_dressed_in_armour_it_may_wear() -> void:
	for cid in ClassLibrary.all_ids():
		var pawn := PawnFactory.make_starter_pawn(cid, cid, String(cid))
		assert_not_null(pawn.armor, "%s starts wearing nothing" % cid)
		if pawn.armor == null:
			continue
		assert_eq(pawn.armor.slot, EquipmentDef.Slot.ARMOR,
			"%s starts wearing %s, which is not armour" % [cid, pawn.armor.id])
		assert_true(pawn.armor.allows_class(pawn.pawn_class),
			"%s may not wear %s, so the equip screen would never offer it" % [cid, pawn.armor.id])

## The load-bearing pair, part one: armed, every class can attack for free.
func test_an_armed_pawn_has_a_free_attack() -> void:
	for cid in ClassLibrary.all_ids():
		var pawn := PawnFactory.make_starter_pawn(cid, cid, String(cid))
		var free := 0
		for action_id in ActionLibrary.actions_for_pawn(pawn):
			if _is_basic_attack(ActionLibrary.get_action(action_id)):
				free += 1
		assert_true(free > 0,
			"%s holding %s still has no free attack" % [cid, pawn.weapon.id if pawn.weapon != null else &"nothing"])

## Part two, and the half that makes part one mean something: take the weapon
## away and the free attack goes with it. If this passed too, the weapon slot
## would be decoration.
func test_an_unarmed_pawn_has_none() -> void:
	for cid in ClassLibrary.all_ids():
		var pawn := PawnFactory.make_starter_pawn(cid, cid, String(cid))
		pawn.weapon = null
		for action_id in ActionLibrary.actions_for_pawn(pawn):
			assert_false(_is_basic_attack(ActionLibrary.get_action(action_id)),
				"%s with an empty hand still has %s to swing" % [cid, action_id])

## And what that costs, stated rather than left to be discovered. An unarmed
## Warrior or Abomination stops fighting: every action it has left costs Rage,
## and Rage only refills from a landed hit. This is the shipped answer to the
## issue's open question -- no implicit unarmed strike -- so it is asserted, not
## assumed, and it fails loudly if somebody adds one.
func test_an_unarmed_rage_pawn_cannot_act_at_all() -> void:
	var pawn := PawnFactory.make_starter_pawn(&"warrior", &"warrior_0", "Warrior")
	pawn.weapon = null
	var affordable := 0
	for action_id in ActionLibrary.actions_for_pawn(pawn):
		var a = ActionLibrary.get_action(action_id)
		if a != null and not a.heals and a.resource_cost <= 0 and a.power_scale > 0.0:
			affordable += 1
	assert_eq(affordable, 0,
		"an unarmed Warrior has a free attack after all -- if that is now wanted, the file header in PawnFactory.gd argues the other way and should be rewritten rather than left false")

## The whole-fight half, and the one the issue names: "a weapon-granted basic
## attack must actually fire in a real fight", not merely exist.
var _fires_cache := {}
func test_a_rage_starved_abomination_reaches_for_the_sickles_claw() -> void:
	var pawn := PawnFactory.make_starter_pawn(&"abomination", &"a0", "Abomination")
	pawn.plans = []
	var state := CombatState.new(0)
	var unit := CombatUnit.new()
	unit.id = 0
	unit.team = CG.Team.PLAYER
	unit.position = Vector2.ZERO
	unit.hp_max = 100
	unit.hp = 100
	unit.move_speed = 3.0
	unit.pawn = pawn
	unit.resource_kind = CG.ResourceKind.RAGE
	unit.resource_max = 100
	unit.resource = 0
	unit.actions = ActionLibrary.actions_for_pawn(pawn)
	state.units.append(unit)
	var enemy := CombatUnit.new()
	enemy.id = 1
	enemy.team = CG.Team.ENEMY
	enemy.hp_max = 100
	enemy.hp = 100
	enemy.position = Vector2(20.0, 0.0)
	state.units.append(enemy)

	var intent := DefaultBehavior.decide(state, unit)
	assert_eq(intent.kind, CG.IntentKind.USE_ACTION,
		"an Abomination with a Sickle and no Rage should swing it")
	assert_eq(intent.action_id, &"abomination_claw",
		"Hook and Grapple both cost Rage; the Sickle's Claw is the only thing it can pay for")

	# And with the Sickle gone, everything it can name costs Rage it does not
	# have. **Asserted on the cost rather than on an IDLE intent, because
	# `DefaultBehavior` does not check affordability at all** -- it picks the
	# cheapest attack whether or not the unit can pay, and `CombatSim` is what
	# refuses. My first version of this assertion expected an idle and was wrong
	# about the mechanism, which is worth leaving written down: an unarmed pawn
	# does not stand still politely, it spends every tick ordering something the
	# simulation throws away. That hole predates this issue and only becomes
	# reachable now that an empty main hand is possible; issue 22 closed the same
	# hole in `PlanInterpreter` and never in this file.
	pawn.weapon = null
	unit.actions = ActionLibrary.actions_for_pawn(pawn)
	var unarmed := DefaultBehavior.decide(state, unit)
	if unarmed.kind == CG.IntentKind.USE_ACTION:
		assert_true(ActionLibrary.get_action(unarmed.action_id).resource_cost > 0,
			"with the Sickle gone it found something free to swing after all")
func _block_of(op: StringName, args: Dictionary = {}) -> PlanBlock:
	return PlanFixtures.block(op, args)

# ---------------------------------------------------------------------------
# Issue 160: the Directional Block reaches a real fight.

const BLOCK_SEEDS := 6
const BLOCK_ROOM := &"floor1_chokepoint"

## Floors at roughly a third of the measured counts on this room, which is
## announcement rule 4: an `> 0` on an emergent count cannot warn, only fail.
const MIN_BLOCK_CASTS := 10

## ISSUE 593 CHANGED THE DENOMINATOR, and this comment records why rather than
## the old number moving quietly. The share of ALL enemy shots was the right
## metric while the shield was indestructible and lasted a flat 10 seconds: it
## could stop everything crossing it for its whole life. The shield now has 40
## health and breaks, so the number of shots one raise can ever stop is bounded
## by the pool, and the share of a room's total fire is structurally capped and
## drifts with how many enemies the room holds. The property that is still about
## the mechanic is SHOTS STOPPED PER RAISE.
const MIN_BLOCKS_PER_RAISE := 1.0
func test_the_warrior_starts_wearing_the_plate_that_teaches_the_block() -> void:
	var w := _warrior()
	assert_not_null(w.armor, "a starter Warrior wears no armour, so nothing can grant it Block")
	assert_eq(w.armor.id, &"plate_mail")
	assert_true(w.armor.granted_actions.has(&"warrior_block"))