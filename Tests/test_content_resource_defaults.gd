extends "res://Tests/TestCase.gd"

const CG := preload("res://Scripts/Core/CG.gd")
const Balance := preload("res://Scripts/Content/Balance.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")

## Issue 132's content half: what a fight starts with, and the magic default
## attack that returns mana.
##
## **Both halves need a `Scripts/Combat` call site that does not exist yet, and
## this file is honest about which of its assertions therefore prove anything.**
## `Balance.starting_resource` is called by nothing and
## `ActionDef.restores_resource` is read by nothing -- swift owns both wirings and
## they are filed. So the declaration tests below are declarations, and the two
## `..._is_still_unwired` tests are the ones that matter: they assert the gap is
## still there and **go red the day it closes**, naming the end-to-end test that
## should replace them.
##
## That pattern is deliberate and it is the one rook asked for after
## `abomination_claw`. A comment explaining a gap rots the day the gap closes and
## nobody deletes it; an assertion cannot.

func _fresh_state(class_id: StringName) -> CombatState:
	var party: Array[PawnData] = [PawnFactory.make_starter_pawn(class_id, &"p0", String(class_id))]
	return CombatSim.build(party, Registry.get_encounter(&"floor1_room1"), 0)

func _pawn_unit(state: CombatState):
	for u in state.units:
		if u.pawn != null:
			return u
	return null

# ---------------------------------------------------------------------------
# the numbers themselves
# ---------------------------------------------------------------------------

func test_mana_starts_full_and_rage_and_energy_start_empty() -> void:
	assert_eq(Balance.starting_resource(CG.ResourceKind.MANA, 100), 100,
		"a caster that cannot cast on tick one is not playing the first half of the fight")
	assert_eq(Balance.starting_resource(CG.ResourceKind.RAGE, 100), 0,
		"Rage is earned inside a fight -- the player's own ruling")
	assert_eq(Balance.starting_resource(CG.ResourceKind.ENERGY, 100), 0,
		"Energy is earned inside a fight -- the player's own ruling")

## The pool size is not this function's business, and a version that returned a
## constant would pass the test above.
func test_a_full_pool_means_that_pawns_own_maximum() -> void:
	for max_resource in [1, 37, 250]:
		assert_eq(Balance.starting_resource(CG.ResourceKind.MANA, max_resource), max_resource)

## Every class in the game gets an answer, so no future resource kind falls
## through to a default nobody chose.
func test_every_class_has_a_defined_opening_pool() -> void:
	for cid in Registry.all_class_ids():
		var pawn := PawnFactory.make_starter_pawn(cid, cid, String(cid))
		var max_resource := Balance.max_resource(pawn)
		var start := Balance.starting_resource(pawn.pawn_class.resource_kind, max_resource)
		assert_true(start == 0 or start == max_resource,
			"%s opens on %d of %d, which is neither empty nor full -- issue 132 defines only those two" % [cid, start, max_resource])

# ---------------------------------------------------------------------------
# the magic default attack
# ---------------------------------------------------------------------------

## The two MAGICAL classes' basic attacks return mana, and the MARTIAL one's does
## not. Asserted through the weapon that grants it, because since issue 129 the
## basic attack is a property of what a pawn is holding.
func test_only_the_magic_basic_attacks_return_mana() -> void:
	var expected := {
		&"geysermancer": true,
		&"priest": true,
		&"siege_master": false,
		&"warrior": false,
		&"abomination": false,
	}
	for cid in Registry.all_class_ids():
		var pawn := PawnFactory.make_starter_pawn(cid, cid, String(cid))
		assert_not_null(pawn.weapon, "%s starts unarmed" % cid)
		var action = Registry.get_action(pawn.weapon.granted_actions[0])
		var restores: int = action.restores_resource
		if bool(expected.get(cid, false)):
			assert_true(restores > 0,
				"%s is a magic class and its default attack returns nothing" % cid)
		else:
			assert_eq(restores, 0,
				("%s's default attack returns %d resource. Only MAGICAL classes should -- the "
				+ "Siege Master is a Mana class but a MARTIAL one, which is the distinction this "
				+ "per-action field exists to express.") % [cid, restores])

## Five basic attacks buy one spell. The ratio is the reasoning behind the
## number, so it is the thing worth asserting -- a bare `== 3` would pass on a
## number nobody could justify.
func test_a_magic_basic_attack_is_worth_about_a_fifth_of_a_spell() -> void:
	var bolt := Registry.get_action(&"priest_bolt")
	var smite := Registry.get_action(&"priest_smite")
	assert_true(bolt.restores_resource > 0)
	var per_spell := float(smite.resource_cost) / float(bolt.restores_resource)
	assert_true(per_spell >= 3.0 and per_spell <= 8.0,
		("%d basic attacks now pay for one Smite. Under three and the caster never runs dry; "
		+ "over eight and the restore is decoration.") % int(round(per_spell)))

## No action pays for itself. A basic attack that returned more than it cost
## would be an infinite-resource loop, and the two carrying this today are free.
func test_no_action_returns_more_resource_than_it_costs() -> void:
	for action_id in Registry.all_action_ids():
		var a = Registry.get_action(action_id)
		if a.restores_resource <= 0:
			continue
		assert_true(a.resource_cost == 0,
			"%s both costs %d and returns %d; a paid action that refunds itself is a loop" % [action_id, a.resource_cost, a.restores_resource])

# ---------------------------------------------------------------------------
# what is NOT wired yet, asserted rather than commented
# ---------------------------------------------------------------------------

## **Delete this test when it fails.** `CombatSim.build` still opens every unit at
## `resource = resource_max`, so `Balance.starting_resource` is called by nothing
## and every number above is a declaration. swift owns the two wiring lines.
func test_the_opening_pool_is_still_unwired() -> void:
	var state := _fresh_state(&"warrior")
	var unit = _pawn_unit(state)
	assert_not_null(unit, "no Warrior was built")
	# Without this the assertion below reads 0 == 0 on a pawn with no pool and
	# passes whatever CombatSim does -- rule 2, and this file is about detectors.
	assert_true(unit.resource_max > 0,
		"a Warrior with no Rage pool at all makes the next assertion vacuous")
	assert_eq(unit.resource, unit.resource_max,
		("A Warrior no longer opens at full Rage, so CombatSim is calling starting_resource. "
		+ "Good -- now delete this test and assert the real thing: a Warrior opens at 0 Rage, "
		+ "an Abomination too, and a Priest at full Mana. See also "
		+ "test_content_equipment_grants.gd, whose abomination_claw exception this closes."))

## **Delete this test when it fails.** Nothing reads `restores_resource`:
## `CombatSim._on_hit_landed` returns early for anything that is not a RAGE pawn,
## and both actions carrying the field are projectiles, so the projectile path is
## the one that must carry it.
##
## **Structural, and the first version of this test was not, which is why this
## comment exists.** I wrote it as "drain a Priest, step, and see whether Mana
## climbs faster than regen explains". It passed, and it was worthless: mana regen
## alone raises the pool on the very first tick, so the loop's own exit condition
## fired immediately and the assertion never reached a state that could
## distinguish a restore from regen. Announcement rule 2 is mine and it caught me
## with the same shape a second time -- "X does not happen" passed by "X cannot
## be observed."
##
## There is no way to observe the absence of this wiring at runtime, because the
## quantity it would move is the quantity regen already moves. So this reads the
## simulation's own source for the field name. It stands for exactly one claim --
## **no code in `CombatSim` mentions `restores_resource`** -- and it cannot be
## vacuous, because the negative half below proves the file was really read.
func test_the_mana_return_is_still_unwired() -> void:
	var source := FileAccess.get_file_as_string("res://Scripts/Combat/CombatSim.gd")
	assert_true(source.contains("_on_hit_landed"),
		"could not read CombatSim.gd, so this check proves nothing about it")
	assert_false(source.contains("restores_resource"),
		("CombatSim now mentions restores_resource, so swift has wired it. Delete this test and "
		+ "assert the real thing through a fight: a landed Bolt returns exactly %d Mana, a Bolt "
		+ "that MISSES returns none, and the pool never passes its maximum.") % Registry.get_action(&"priest_bolt").restores_resource)
