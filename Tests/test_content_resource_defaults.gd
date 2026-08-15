extends "res://Tests/TestCase.gd"

const CG := preload("res://Scripts/Core/CG.gd")
const Balance := preload("res://Scripts/Content/Balance.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const Intent := preload("res://Scripts/Core/Intent.gd")
const SimDeps := preload("res://Scripts/Combat/SimDeps.gd")

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

## Wired at issue 164. This replaces `test_the_opening_pool_is_still_unwired`,
## whose own instruction was to delete it and assert the real thing the day it
## went red -- which it did the moment `CombatSim.build` started calling
## `Balance.starting_resource`.
func test_a_rage_pawn_opens_empty_and_a_mana_pawn_opens_full() -> void:
	for class_id in [&"warrior", &"abomination"]:
		var unit = _pawn_unit(_fresh_state(class_id))
		assert_not_null(unit, "no %s was built" % class_id)
		assert_true(unit.resource_max > 0,
			"a %s with no pool at all makes the next assertion vacuous" % class_id)
		assert_eq(unit.resource, 0, "%s must open with no Rage to spend" % class_id)

	var priest = _pawn_unit(_fresh_state(&"priest"))
	assert_not_null(priest, "no Priest was built")
	assert_true(priest.resource_max > 0, "a Priest with no Mana pool makes this vacuous")
	assert_eq(priest.resource, priest.resource_max,
		"a caster that cannot cast on tick one is not playing the first half of the fight")

## The enemy branch deliberately did NOT move, per rook: the ruling was about
## mana classes, and changing `_build_enemy_unit` because it is the same shape
## would be an unasked balance change while balance is frozen.
##
## **That decision cannot be observed in a fight today**, because no enemy in the
## game has a resource pool at all -- a test reading a spawned enemy's `resource`
## would compare 0 to 0 and pass whatever `CombatSim` did. So this asserts the
## reason instead, and goes red the day an enemy gets a pool, which is exactly
## when the ruling becomes checkable and someone should write the real assertion.
func test_no_enemy_has_a_resource_pool_so_the_enemy_branch_stays_unobservable() -> void:
	var with_pools: Array[StringName] = []
	for enemy_id in Registry.all_enemy_ids():
		var e = Registry.get_enemy(enemy_id)
		if e != null and e.resource_max > 0:
			with_pools.append(enemy_id)
	assert_eq(with_pools, [] as Array[StringName],
		("An enemy has a resource pool now, so rook's ruling that enemies still open FULL "
		+ "is finally observable. Delete this test and assert it directly on a spawned unit."))

## Wired at issue 165, replacing `test_the_mana_return_is_still_unwired`.
##
## That test read this file's source for the field name, because until it was
## wired there was no runtime observation separating a restore from mana regen.
## There is now, so these run a real fight instead -- and they turn off regen so
## the only thing that can move the pool is the Bolt.
##
## `priest_bolt` is a PROJECTILE, which is the whole point of issue 165: a
## restore wired into `_fire_action` rather than into the landing would pass a
## hand-written test and return nothing here.
func test_a_landed_bolt_returns_mana_and_a_miss_returns_none() -> void:
	var bolt = Registry.get_action(&"priest_bolt")
	assert_true(bolt.restores_resource > 0, "no restore authored, so this proves nothing")
	assert_true(bolt.projectile_speed > 0.0,
		"priest_bolt stopped being a projectile, so this no longer covers the landing path")

	var deps := _bolt_deps()

	var hit := _bolt_state()
	var caster = hit.unit(0)
	caster.resource = 0
	caster.focus_id = 1
	caster.intent = Intent.use_action(bolt.id, 1)
	for _i in 90:
		CombatSim.step(hit, deps)
		if caster.resource > 0:
			break
	assert_eq(caster.resource, bolt.restores_resource,
		"a landed Bolt returns exactly what it says it does")

	var missed := _bolt_state()
	var m = missed.unit(0)
	m.resource = 0
	m.focus_id = 1
	m.intent = Intent.use_action(bolt.id, 1)
	CombatSim.step(missed, deps)
	missed.unit(1).position = Vector2(9000.0, 9000.0)
	for _i in 90:
		CombatSim.step(missed, deps)
	assert_eq(m.resource, 0, "a Bolt that MISSES returns nothing")

func test_the_restore_never_passes_the_maximum() -> void:
	var bolt = Registry.get_action(&"priest_bolt")
	var deps := _bolt_deps()
	var state := _bolt_state()
	var caster = state.unit(0)
	caster.resource = caster.resource_max
	caster.focus_id = 1
	caster.intent = Intent.use_action(bolt.id, 1)
	for _i in 90:
		CombatSim.step(state, deps)
	assert_eq(caster.resource, caster.resource_max, "clamped, never over")

## Regen off, and the decision layer pinned to idle: the only thing that may
## move this pool is the hand-placed Bolt. Without the pin the Priest goes on
## casting Smite and Ward for the rest of the loop, and the clamp assertion
## measured its own spending instead of the restore.
func _bolt_deps() -> SimDeps:
	var deps := SimDeps.new()
	deps.resource_regen_per_tick = func(_u) -> float: return 0.0
	deps.plan_decide = func(_s, _u): return null
	deps.default_decide = func(_s, _u): return Intent.idle()
	return deps

## A Priest and exactly one living, distant target, so the only thing that can
## move the Priest's Mana is its own Bolt.
func _bolt_state() -> CombatState:
	var party: Array[PawnData] = [PawnFactory.make_starter_pawn(&"priest", &"p0", "Priest")]
	var state := CombatSim.build(party, Registry.get_encounter(&"floor1_room1"), 4)
	for u in state.units:
		if u.pawn == null:
			u.alive = u.id == 1
			u.position = Vector2(180.0, 0.0)
	state.units[0].position = Vector2.ZERO
	return state
