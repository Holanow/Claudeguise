extends "res://Tests/TestCase.gd"


## Issue 747: a second MARTIAL off-hand weapon alternates the attacking hand,
## tracked as sim state so a seed reproduces it. `Tests/test_plans_default_plan.gd`
## covers `DefaultPlan.dual_wields` itself; this covers `CombatSim` actually
## using it.

func _caster(pawn: PawnData, action_id: StringName) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = 0
	u.team = CG.Team.PLAYER
	u.hp_max = 999999
	u.hp = u.hp_max
	u.resource_max = 999999
	u.resource = 999999
	u.pawn = pawn
	u.actions = [action_id]
	u.position = Vector2(-CG.ARENA_HALF_WIDTH + 40.0, 0.0)
	return u

func _target() -> CombatUnit:
	var t := CombatUnit.new()
	t.id = 1
	t.team = CG.Team.ENEMY
	t.hp_max = 999999999
	t.hp = t.hp_max
	t.resource_max = 999999
	t.resource = 999999
	t.position = Vector2(-CG.ARENA_HALF_WIDTH + 40.0 + 20.0, 0.0)
	return t

## Records `last_attack_hand` the instant each ACTION_START for `action_id`
## fires -- sampled live, mid-loop, never after `step()` returns, per
## ENGINEER.md's own warning about reading a transient field too late.
func _run_forcing_attacks(caster: CombatUnit, target: CombatUnit, action_id: StringName, ticks: int) -> Dictionary:
	caster.facing = (target.position - caster.position).normalized()
	var state := CombatState.new(1)
	state.units = [caster, target]
	var deps := SimDeps.new()
	deps.default_decide = func(_s: CombatState, u: CombatUnit) -> Intent:
		return Intent.use_action(action_id, target.id) if u.id == caster.id else null
	deps.attack_power = func(_u: CombatUnit, _a: ActionDef, _r: RandomNumberGenerator) -> float: return 5.0
	var hands: Array = []
	for _t in ticks:
		var before := state.events.size()
		CombatSim.step(state, deps)
		for i in range(before, state.events.size()):
			var e := state.events[i]
			if e.kind == CG.EventKind.ACTION_START and e.action_id == action_id and e.source_id == caster.id:
				hands.append(caster.last_attack_hand)
	return {"state": state, "hands": hands}

func test_single_weapon_pawn_never_sets_last_attack_hand() -> void:
	var pawn := PawnFactory.make_starter_pawn(&"warrior", &"w", "Warrior")
	## Issue 822: a starter Warrior now carries a shield, so the one-weapon
	## pawn this is about has to be built rather than assumed.
	pawn.off_hand = null
	var caster := _caster(pawn, &"warrior_strike")
	var target := _target()
	_run_forcing_attacks(caster, target, &"warrior_strike", 200)
	assert_eq(caster.last_attack_hand, -1,
		"a pawn with one weapon must be byte-identical -- nothing may touch this field")

func test_dual_wielder_alternates_starting_with_main_hand() -> void:
	var pawn := PawnFactory.make_starter_pawn(&"warrior", &"w", "Warrior")
	pawn.off_hand = ItemLibrary.get_equipment(&"wrench")
	assert_true(DefaultPlan.dual_wields(pawn))
	var caster := _caster(pawn, &"warrior_strike")
	var target := _target()
	var hands: Array = _run_forcing_attacks(caster, target, &"warrior_strike", 400)["hands"]

	assert_true(hands.size() >= 3, "expected several swings in 400 ticks, got %d" % hands.size())
	assert_eq(hands[0], EquipmentDef.Slot.MAIN_HAND, "the first swing leads with the main hand")
	for i in range(1, hands.size()):
		assert_ne(hands[i], hands[i - 1], "swing %d repeated the same hand as the one before it" % i)

func test_shield_in_off_hand_never_alternates() -> void:
	var pawn := PawnFactory.make_starter_pawn(&"warrior", &"w", "Warrior")
	pawn.off_hand = ItemLibrary.get_equipment(&"shield")
	var caster := _caster(pawn, &"warrior_strike")
	var target := _target()
	_run_forcing_attacks(caster, target, &"warrior_strike", 200)
	assert_eq(caster.last_attack_hand, -1, "a shield must not alternate anything")

func test_two_runs_of_one_seed_alternate_identically() -> void:
	var results: Array[Array] = []
	for _run in 2:
		var pawn := PawnFactory.make_starter_pawn(&"warrior", &"w", "Warrior")
		pawn.off_hand = ItemLibrary.get_equipment(&"wrench")
		var caster := _caster(pawn, &"warrior_strike")
		var target := _target()
		var hands: Array = _run_forcing_attacks(caster, target, &"warrior_strike", 400)["hands"]
		results.append(hands)
	assert_eq(results[0], results[1], "the same seed must alternate the same way every time")
