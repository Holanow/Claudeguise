extends "res://Tests/TestCase.gd"


## Issues 100 and 99: equipment that grants an action, and the Warrior's
## self-sustain that replaces the action it grants.

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
	pawn.armor = null
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
func test_a_warrior_without_plate_cannot_block() -> void:
	var bare := _warrior()
	bare.armor = null
	var intent := _decide_with_block_plan(bare)
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
##
## Issue 334: it also has to say WHICH rule cast it. This test passed for years
## while the plan it is named after never fired once.
func test_second_wind_actually_fires_and_heals_in_a_real_fight() -> void:
	var fires := 0
	var heals := 0
	var by_fallback := 0
	var by_plan := 0
	for s in SEEDS:
		var state := CombatSim.build(_party(), Registry.get_encounter(&"floor1_room1"), s)
		CombatSim.run(state)
		for e in state.events:
			if e.action_id != &"warrior_second_wind":
				continue
			if e.kind == CG.EventKind.ACTION_START:
				if e.source_plan == &"":
					by_fallback += 1
				else:
					by_plan += 1
			elif e.kind == CG.EventKind.ACTION_FIRE:
				fires += 1
			elif e.kind == CG.EventKind.HEAL:
				heals += 1
	assert_true(fires > 0,
		"Second Wind never fired in %d real fights -- it is unreachable" % SEEDS)
	assert_true(heals > 0,
		"Second Wind fired %d times and healed nothing" % fires)
	assert_true(by_fallback + by_plan > 0, "nothing started Second Wind, so no path can be named")

	## Issue 334, and it is a tripwire rather than a preference: every cast
	## measured comes from `DefaultBehavior`, never from the Warrior's own row.
	## Measured 17 of 17 starts over 40 seeds. If this goes red the plan has
	## started working, which is good news -- delete the assertion and say so.
	assert_eq(by_plan, 0,
		("the Warrior's own Second Wind row fired %d of %d times. It never used to. " +
		"See issue 334; if this is deliberate, this assertion is the thing to remove") % [
			by_plan, by_fallback + by_plan])

## **Issue 334: WHY the row never fires, stated structurally so it cannot rot
## against a sample.**
##
## `DefaultBehavior` casts any heal it owns once an ally is at or below
## `HEAL_THRESHOLD_FRACTION`. A plan row gated at a LOWER fraction than that can
## never be the first to reach the action: the fallback has already cast it and
## started its cooldown by the time the pawn is hurt enough for the row to hold.
## The row is dominated, not unlucky, and no number of seeds would show
## otherwise.
func test_a_self_heal_row_gated_below_the_fallback_can_never_go_first() -> void:
	var row: Plan = null
	for plan in PresetPlans.for_class(&"warrior"):
		for block in plan.blocks:
			if block.kind == PlanBlock.Kind.ACTION and block.args.get("action_id", &"") == &"warrior_second_wind":
				row = plan
	assert_not_null(row, "the Warrior should still ship a Second Wind row")
	assert_not_null(row.condition, "an ungated self-heal row would fire constantly")
	assert_eq(row.condition.op, &"self_hp_below_fraction",
		"this test reads the row's threshold; a different condition op needs a different reading")

	var row_threshold := float(row.condition.args.get("fraction", 1.0))
	assert_true(row_threshold < DefaultBehavior.HEAL_THRESHOLD_FRACTION,
		("the Warrior's row fires at %.2f and the fallback at %.2f. This assertion records that " +
		"the row is DOMINATED -- it is the state issue 334 reports, not the state anyone wants. " +
		"If the row now goes first, that is the fix landing: delete this test") % [
			row_threshold, DefaultBehavior.HEAL_THRESHOLD_FRACTION])


# ---------------------------------------------------------------------------
# issue 129: the basic attack comes from the main-hand weapon
#
# The same pair discipline as the plate tests above, one level down. A test
# reading `sword.granted_actions == [warrior_strike]` passes on the day the
# table is typed and says nothing about whether anybody ever swings it, which is
# how `granted_actions` sat empty on seventeen items for weeks. So every claim
# here is made twice: armed, and with the same pawn's hand emptied.

## What a basic attack is, written once so four tests cannot disagree about it:
func _is_basic_attack(action) -> bool:
	return action != null and not action.heals and action.power_scale > 0.0 and action.resource_cost <= 0

func _weapon_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in Registry.all_equipment_ids():
		if Registry.get_equipment(id).slot == EquipmentDef.Slot.WEAPON:
			out.append(id)
	return out

func test_every_weapon_provides_exactly_one_basic_attack() -> void:
	var weapons := _weapon_ids()
	assert_true(weapons.size() >= 6,
		"expected at least the six base weapon types; found %d" % weapons.size())
	for id in weapons:
		var item := Registry.get_equipment(id)
		assert_eq(item.granted_actions.size(), 1,
			"%s should provide exactly one attack -- README's Provided Actions column has one entry per weapon, and a weapon granting none is a trap: the pawn holding it has no free action at all" % id)
		var action = Registry.get_action(item.granted_actions[0])
		assert_true(_is_basic_attack(action),
			"%s provides %s, which is not a free damaging attack" % [id, item.granted_actions[0]])

## The move actually happened. Without this the whole issue can be "done" by
## adding grants and leaving the class copies in place, and every pawn would
## keep attacking exactly as it did with the weapon slot doing nothing.
func test_no_class_still_carries_a_basic_attack_of_its_own() -> void:
	for cid in Registry.all_class_ids():
		var def := Registry.get_class_def(cid)
		for action_id in def.starting_actions:
			assert_false(_is_basic_attack(Registry.get_action(action_id)),
				"%s still ships %s, a free attack of its own -- issue 129 moves those onto weapons" % [cid, action_id])

## Every class starts holding something, and holding something it is allowed to
## hold. A starter equipped with a piece `EquipmentDef.allows` refuses is a pawn
## carrying gear its own equip screen would never have offered it.
func test_every_class_starts_armed_with_a_weapon_it_may_use() -> void:
	for cid in Registry.all_class_ids():
		var pawn := PawnFactory.make_starter_pawn(cid, cid, String(cid))
		assert_not_null(pawn.weapon, "%s starts with an empty main hand" % cid)
		if pawn.weapon == null:
			continue
		assert_eq(pawn.weapon.slot, EquipmentDef.Slot.WEAPON,
			"%s starts holding %s, which is not a weapon" % [cid, pawn.weapon.id])
		assert_true(pawn.weapon.allows(pawn.pawn_class.method),
			"%s may not use %s, so the equip screen would never offer it" % [cid, pawn.weapon.id])

## The load-bearing pair, part one: armed, every class can attack for free.
func test_an_armed_pawn_has_a_free_attack() -> void:
	for cid in Registry.all_class_ids():
		var pawn := PawnFactory.make_starter_pawn(cid, cid, String(cid))
		var free := 0
		for action_id in Registry.actions_for_pawn(pawn):
			if _is_basic_attack(Registry.get_action(action_id)):
				free += 1
		assert_true(free > 0,
			"%s holding %s still has no free attack" % [cid, pawn.weapon.id if pawn.weapon != null else &"nothing"])

## Part two, and the half that makes part one mean something: take the weapon
## away and the free attack goes with it. If this passed too, the weapon slot
## would be decoration.
func test_an_unarmed_pawn_has_none() -> void:
	for cid in Registry.all_class_ids():
		var pawn := PawnFactory.make_starter_pawn(cid, cid, String(cid))
		pawn.weapon = null
		for action_id in Registry.actions_for_pawn(pawn):
			assert_false(_is_basic_attack(Registry.get_action(action_id)),
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
	for action_id in Registry.actions_for_pawn(pawn):
		var a = Registry.get_action(action_id)
		if a != null and not a.heals and a.resource_cost <= 0 and a.power_scale > 0.0:
			affordable += 1
	assert_eq(affordable, 0,
		"an unarmed Warrior has a free attack after all -- if that is now wanted, the file header in PawnFactory.gd argues the other way and should be rewritten rather than left false")

## The whole-fight half, and the one the issue names: "a weapon-granted basic
## attack must actually fire in a real fight", not merely exist.
var _fires_cache := {}

func _basic_attack_fires(strip_weapons: bool) -> Dictionary:
	if _fires_cache.has(strip_weapons):
		return _fires_cache[strip_weapons]
	var counts := {}
	for s in FIGHT_SEEDS:
		var party: Array[PawnData] = []
		for cid in Registry.all_class_ids():
			var p := PawnFactory.make_starter_pawn(cid, StringName("%s_%d" % [cid, party.size()]), String(cid))
			if strip_weapons:
				p.weapon = null
			party.append(p)
		var state := CombatSim.build(party, Registry.get_encounter(&"floor1_room1"), s)
		CombatSim.run(state)
		for e in state.events:
			if e.kind == CG.EventKind.ACTION_FIRE:
				counts[e.action_id] = int(counts.get(e.action_id, 0)) + 1
	_fires_cache[strip_weapons] = counts
	return counts

## Measured on this branch over FIGHT_SEEDS seeds of `floor1_room1`:
const FIGHT_SEEDS := 12
const MIN_FIRES := {
	&"warrior_strike": 25,
	&"priest_bolt": 3,
	&"geyser_spout": 10,
	&"siege_master_shot": 5,
	# Issue 206: measured 34 in this fixture once the Abomination gained a plan
	# row telling it when to Claw. Floor at roughly a third, same as its
	# siblings.
	&"abomination_claw": 10,
}

## **`abomination_claw` fired zero times in every encounter in the game, and
## issue 206 is where that ended.** The cause was never the weapon: it was that
## the Abomination had no plan row saying when to use a free attack, and its two
## paid rows covered every tick. `ABOMINATION_CLAW_IS_DEAD` and the test guarding
## it are **deleted rather than loosened** -- they were a statement about a moment
## and the moment passed, which is exactly what they were written to announce.
func test_every_weapons_basic_attack_fires_in_a_real_fight() -> void:
	var counts := _basic_attack_fires(false)
	for cid in Registry.all_class_ids():
		var pawn := PawnFactory.make_starter_pawn(cid, cid, String(cid))
		var granted: StringName = pawn.weapon.granted_actions[0]
		if not MIN_FIRES.has(granted):
			continue
		assert_true(int(counts.get(granted, 0)) >= int(MIN_FIRES[granted]),
			"%s's %s grants %s and it fired %d times in %d real fights, under its floor of %d" % [
				cid, pawn.weapon.id, granted, int(counts.get(granted, 0)), FIGHT_SEEDS, int(MIN_FIRES[granted])])

## The unit-level half, kept now that the fight-level half passes too: with Rage
## drained and no plans, the Abomination must reach for the weapon's Claw rather
## than stand there. This is what proves the *grant* works independently of the
## plan row that makes it reachable in a real fight.
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
	unit.actions = Registry.actions_for_pawn(pawn)
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
	unit.actions = Registry.actions_for_pawn(pawn)
	var unarmed := DefaultBehavior.decide(state, unit)
	if unarmed.kind == CG.IntentKind.USE_ACTION:
		assert_true(Registry.get_action(unarmed.action_id).resource_cost > 0,
			"with the Sickle gone it found something free to swing after all")

## The negative half. The same five parties with empty hands must fire none of
## them -- otherwise the counts above prove only that the actions still exist
## somewhere, not that the weapon is what put them in the pawn's hand.
func test_stripping_the_weapons_stops_every_one_of_those_attacks() -> void:
	var counts := _basic_attack_fires(true)
	for cid in Registry.all_class_ids():
		var pawn := PawnFactory.make_starter_pawn(cid, cid, String(cid))
		var granted: StringName = pawn.weapon.granted_actions[0]
		assert_eq(int(counts.get(granted, 0)), 0,
			"an unarmed party still fired %s, so it does not come from the weapon" % granted)

func _block_of(kind: PlanBlock.Kind, op: StringName, args: Dictionary) -> PlanBlock:
	var b := PlanBlock.new()
	b.kind = kind
	b.op = op
	b.args = args
	return b

# ---------------------------------------------------------------------------
# Issue 160: the Directional Block reaches a real fight.

const BLOCK_SEEDS := 6
const BLOCK_ROOM := &"floor1_chokepoint"

## Floors at roughly a third of the measured counts on this room, which is
## announcement rule 4: an `> 0` on an emergent count cannot warn, only fail.
const MIN_BLOCK_CASTS := 10
const MIN_BLOCKED := 100

func _block_counts(strip_armor: bool) -> Dictionary:
	var casts := 0
	var shieldings := 0
	var blocked := 0
	for s in BLOCK_SEEDS:
		var party: Array[PawnData] = []
		for cid in Registry.all_class_ids():
			var p := PawnFactory.make_starter_pawn(cid, StringName("%s_%d" % [cid, party.size()]), String(cid))
			if strip_armor:
				p.armor = null
			party.append(p)
		var state := CombatSim.build(party, Registry.get_encounter(BLOCK_ROOM), s)
		CombatSim.run(state)
		for e in state.events:
			if e.kind == CG.EventKind.ACTION_FIRE and e.action_id == &"warrior_block":
				casts += 1
			elif e.kind == CG.EventKind.STATUS_APPLIED and e.status == CG.Status.SHIELDING:
				shieldings += 1
			elif e.kind == CG.EventKind.BLOCKED:
				blocked += 1
	return {"casts": casts, "shieldings": shieldings, "blocked": blocked}

func test_the_warrior_starts_wearing_the_plate_that_teaches_the_block() -> void:
	var w := _warrior()
	assert_not_null(w.armor, "a starter Warrior wears no armour, so nothing can grant it Block")
	assert_eq(w.armor.id, &"plate_mail")
	assert_true(w.armor.granted_actions.has(&"warrior_block"))

func test_the_block_is_cast_and_stops_real_shots_in_a_real_fight() -> void:
	var c := _block_counts(false)
	print("%s over %d seeds: block casts %d, SHIELDING %d, BLOCKED %d" % [
		BLOCK_ROOM, BLOCK_SEEDS, c["casts"], c["shieldings"], c["blocked"]])
	assert_true(int(c["casts"]) >= MIN_BLOCK_CASTS,
		"warrior_block fired %d times in %d fights, under its floor of %d" % [int(c["casts"]), BLOCK_SEEDS, MIN_BLOCK_CASTS])
	assert_true(int(c["blocked"]) >= MIN_BLOCKED,
		("the shield caught %d shots in %d fights, under its floor of %d. Casting is not the same as "
		+ "blocking: SHIELDING existed in the simulation for months with nothing ever passing through it.")
		% [int(c["blocked"]), BLOCK_SEEDS, MIN_BLOCKED])

## **The control, and the counts above are worth nothing without it.** Strip the
## armour and the same party in the same room on the same seeds must produce
## none of it -- otherwise the numbers prove only that Block exists somewhere,
## not that wearing plate is what put it in the fight. Same pairing as
## `test_stripping_the_weapons_stops_every_one_of_those_attacks` above.
func test_an_unarmoured_party_never_blocks_anything() -> void:
	var c := _block_counts(true)
	assert_eq(int(c["casts"]), 0, "an unarmoured Warrior still cast Block, so the plate is not what grants it")
	assert_eq(int(c["shieldings"]), 0, "SHIELDING was applied with no plate in the party")
	assert_eq(int(c["blocked"]), 0, "a shot was blocked with nobody wearing a shield")
