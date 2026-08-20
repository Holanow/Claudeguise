extends "res://Tests/TestCase.gd"

## Issue 344. The simulation knows what ate a hit and must carry it: the middle
## figure that splits mitigation from overkill, and one name for the cause.

func _attack() -> ActionDef:
	var a := ActionDef.new()
	a.id = &"swing"
	a.range_units = 1000.0
	a.damage_type = CG.DamageType.PHYSICAL
	return a

func _unit(id: int, team: CG.Team, hp: int) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.hp_max = maxi(hp, 1)
	u.hp = hp
	u.position = Vector2(float(id) * 10.0, 0.0)
	u.actions = [&"swing"]
	return u

## Fires one attack from unit 1 into unit 2 and returns the DAMAGE event.
func _one_hit(raw: float, reduction: float, target_hp: int) -> CombatEvent:
	var action := _attack()
	var deps := SimDeps.new()
	deps.action_lookup = func(_id: StringName): return action
	deps.attack_power = func(_u: CombatUnit, _a: ActionDef, _rng = null) -> float: return raw
	deps.damage_reduction = func(_u: CombatUnit) -> float: return reduction
	deps.wind_up_ticks = func(_u: CombatUnit, _a: ActionDef) -> int: return 0
	deps.recover_ticks = func(_u: CombatUnit, _a: ActionDef) -> int: return 0
	deps.default_decide = func(_s: CombatState, u: CombatUnit) -> Intent:
		if u.id != 1:
			return Intent.idle()
		return Intent.use_action(&"swing", 2)

	var state := CombatState.new(0)
	state.units = [_unit(0, CG.Team.PLAYER, 50), _unit(1, CG.Team.PLAYER, 50), _unit(2, CG.Team.ENEMY, target_hp)]
	for _i in 10:
		CombatSim.step(state, deps)
		for e in state.events:
			if e.kind == CG.EventKind.DAMAGE:
				return e
	return null

# ---------------------------------------------------------------------------
# the three figures
# ---------------------------------------------------------------------------

func test_a_clean_hit_carries_all_three_figures_equal() -> void:
	var e := _one_hit(20.0, 0.0, 100)
	assert_not_null(e, "the attack must land")
	assert_eq(e.amount_before_mitigation, 20, "raw roll")
	assert_eq(e.amount_after_mitigation, 20, "nothing reduced it")
	assert_eq(e.amount, 20, "nothing clamped it")

func test_a_reduced_hit_carries_the_middle_figure() -> void:
	var e := _one_hit(20.0, 0.5, 100)
	assert_eq(e.amount_before_mitigation, 20, "raw roll")
	assert_eq(e.amount_after_mitigation, 10, "half of it was mitigated")
	assert_eq(e.amount, 10, "the target had room for all of it")

## The line the blind playtester quoted: "1 Physical damage (29 before
## mitigation)". Nothing mitigated it. The target had 1 hp.
func test_a_killing_blow_is_overkill_and_not_mitigation() -> void:
	var e := _one_hit(29.0, 0.0, 1)
	assert_eq(e.amount_before_mitigation, 29, "raw roll")
	assert_eq(e.amount_after_mitigation, 29, "nothing was mitigated, and this is the whole finding")
	assert_eq(e.amount, 1, "only 1 hp was there to take")
	assert_eq(e.mitigation_cause, CG.MitigationCause.NONE, "naming a cause here would be a lie")

## Both at once, and the two gaps must stay separable.
func test_mitigation_and_overkill_are_separately_recoverable() -> void:
	var e := _one_hit(40.0, 0.5, 5)
	assert_eq(e.amount_before_mitigation - e.amount_after_mitigation, 20, "mitigated")
	assert_eq(e.amount_after_mitigation - e.amount, 15, "overkill")

## The whole gap was overkill for 13.4% of hits measured on real fights, so a
## reader deriving mitigation from `amount` alone gets a different number.
func test_the_old_two_field_reading_disagrees_with_the_new_one() -> void:
	var e := _one_hit(29.0, 0.0, 1)
	assert_eq(e.amount_before_mitigation - e.amount, 28, "what the log subtracts today")
	assert_eq(e.amount_before_mitigation - e.amount_after_mitigation, 0, "what was actually mitigated")

# ---------------------------------------------------------------------------
# the cause
# ---------------------------------------------------------------------------

func _pawn_with(con: int, shield: bool, block: bool) -> CombatUnit:
	# Built bare rather than through PawnFactory: a starter pawn carries a class
	# spread and gear, and this matrix needs CON to be exactly what it says.
	var pawn := PawnData.new()
	pawn.attribute_bonus[CG.Attribute.CON] = con
	var u := CombatUnit.new()
	u.id = 1
	u.pawn = pawn
	u.hp_max = 100
	u.hp = 100
	if shield:
		u.statuses[CG.Status.SHIELD] = 999
	if block:
		u.statuses[CG.Status.BLOCK] = 999
	return u

func test_low_toughness_alone_names_toughness() -> void:
	var u := _pawn_with(5, false, false)
	assert_eq(SimDeps._default_damage_reduction_cause(u), CG.MitigationCause.TOUGHNESS)

func test_a_shield_outweighs_low_toughness() -> void:
	var u := _pawn_with(5, true, false)
	assert_eq(SimDeps._default_damage_reduction_cause(u), CG.MitigationCause.SHIELD)

func test_high_toughness_outweighs_a_shield() -> void:
	# CON 30 is the natural cap, 0.30, against SHIELD's 0.25.
	var u := _pawn_with(30, true, false)
	assert_eq(SimDeps._default_damage_reduction_cause(u), CG.MitigationCause.TOUGHNESS)

func test_a_blocking_pawn_names_block() -> void:
	var u := _pawn_with(5, false, true)
	assert_eq(SimDeps._default_damage_reduction_cause(u), CG.MitigationCause.BLOCK)

func test_a_pawn_with_nothing_names_nothing() -> void:
	var u := _pawn_with(0, false, false)
	assert_eq(SimDeps._default_damage_reduction_cause(u), CG.MitigationCause.NONE,
		"a pawn that mitigates nothing must not be given a cause")

## The negative test the cause is most likely to fail: the name must belong to
## something that really moved the number. Every named cause is checked by
## taking it away and asserting the reduction drops.
func test_every_named_cause_really_lowers_the_reduction() -> void:
	var checked := 0
	for con in [0, 5, 30]:
		for shield in [false, true]:
			for block in [false, true]:
				var u := _pawn_with(con, shield, block)
				var cause: CG.MitigationCause = SimDeps._default_damage_reduction_cause(u)
				var with_it: float = SimDeps._default_damage_reduction(u)
				if cause == CG.MitigationCause.NONE:
					assert_eq(with_it, 0.0, "no cause was named, so nothing may be reduced")
					continue
				var without := _pawn_with(
					0 if cause == CG.MitigationCause.TOUGHNESS else con,
					shield and cause != CG.MitigationCause.SHIELD,
					block and cause != CG.MitigationCause.BLOCK)
				var lost: float = SimDeps._default_damage_reduction(without)
				assert_true(lost < with_it,
					"cause %d was named but removing it left the reduction at %f" % [cause, with_it])
				checked += 1
	assert_true(checked >= 8, "the matrix must actually reach the named-cause branch, got %d" % checked)

## An enemy's own toughness is its hide, and it must not be reported as armour
## a player could have taken off it.
func test_an_armoured_enemy_names_hide() -> void:
	var found := CG.MitigationCause.NONE
	for id in Registry.all_enemy_ids():
		var d: EnemyDef = Registry.get_enemy(id)
		if d == null or d.damage_reduction <= 0.0:
			continue
		var u := CombatUnit.new()
		u.enemy_id = id
		found = SimDeps._default_damage_reduction_cause(u)
		break
	assert_eq(found, CG.MitigationCause.HIDE, "no enemy in content has damage_reduction, or the cause is wrong")
