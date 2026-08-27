extends "res://Tests/TestCase.gd"

## Issue 344. The simulation knows what ate a hit and must carry it: the middle
## figure that splits mitigation from overkill, and one name for the cause.

func _attack() -> ActionDef:
	var a := ActionDef.new()
	a.id = &"swing"
	a.targeting = ActionTargeting.new()
	a.targeting.range_units = 1000.0
	var hit := HitEffect.new()
	hit.damage_type = CG.DamageType.PHYSICAL
	a.effects = [hit] as Array[AbilityEffect]
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
	var unnamed := 0
	var cells := 0
	for con in [0, 5, 30]:
		for shield in [false, true]:
			for block in [false, true]:
				cells += 1
				var u := _pawn_with(con, shield, block)
				var cause: CG.MitigationCause = SimDeps._default_damage_reduction_cause(u)
				var with_it: float = SimDeps._default_damage_reduction(u)
				if cause == CG.MitigationCause.NONE:
					assert_eq(with_it, 0.0, "no cause was named, so nothing may be reduced")
					unnamed += 1
					continue
				var without := _pawn_with(
					0 if cause == CG.MitigationCause.TOUGHNESS else con,
					shield and cause != CG.MitigationCause.SHIELD,
					block and cause != CG.MitigationCause.BLOCK)
				var lost: float = SimDeps._default_damage_reduction(without)
				assert_true(lost < with_it,
					"cause %d was named but removing it left the reduction at %f" % [cause, with_it])
				checked += 1
	assert_eq(checked + unnamed, cells,
		"every cell of the matrix must land in one branch or the other, not fall through both")
	assert_eq(unnamed, 1,
		"only the bare pawn -- CON 0, no shield, no block -- may name nothing; %d cells did" % unnamed)

## An enemy's own toughness is its hide, and it must not be reported as armour
## a player could have taken off it.
func test_an_armoured_enemy_names_hide() -> void:
	var found := CG.MitigationCause.NONE
	for id in EnemyLibrary.all_ids():
		var d: EnemyDef = EnemyLibrary.get_enemy(id)
		if d == null or d.damage_reduction <= 0.0:
			continue
		var u := CombatUnit.new()
		u.enemy_id = id
		found = SimDeps._default_damage_reduction_cause(u)
		break
	assert_eq(found, CG.MitigationCause.HIDE, "no enemy in content has damage_reduction, or the cause is wrong")

# ---------------------------------------------------------------------------
# issue 364: statuses reach an enemy target
# ---------------------------------------------------------------------------

## The first enemy in content that has any hide to strip, so these cases test a
## real target rather than a hand-made one whose numbers I chose.
func _hided_enemy() -> CombatUnit:
	for id in EnemyLibrary.all_ids():
		var d: EnemyDef = EnemyLibrary.get_enemy(id)
		if d != null and d.damage_reduction > 0.0:
			var u := CombatUnit.new()
			u.enemy_id = id
			return u
	return null

func test_marking_an_enemy_strips_its_hide() -> void:
	var u := _hided_enemy()
	assert_not_null(u, "content has no enemy with damage_reduction")
	var before: float = SimDeps._default_damage_reduction(u)
	assert_true(before > 0.0, "the fixture enemy must start with some hide")
	u.statuses[CG.Status.MARKED] = 999
	var after: float = SimDeps._default_damage_reduction(u)
	assert_true(after < before,
		"MARKED did nothing to an enemy: %f before, %f after. This is issue 364." % [before, after])

## `spotter_mark` is the only thing in content that marks an enemy, and every
## enemy hide is under MARKED's vulnerability, so a mark removes all of it.
func test_a_marked_enemy_keeps_no_hide_at_all() -> void:
	var u := _hided_enemy()
	u.statuses[CG.Status.MARKED] = 999
	assert_eq(SimDeps._default_damage_reduction(u), 0.0)

## A cause naming something that removed nothing is the lie this seam exists to
## prevent, and MARKED is the one thing that can produce it.
func test_a_marked_enemy_is_given_no_cause() -> void:
	var u := _hided_enemy()
	assert_eq(SimDeps._default_damage_reduction_cause(u), CG.MitigationCause.HIDE, "unmarked")
	u.statuses[CG.Status.MARKED] = 999
	assert_eq(SimDeps._default_damage_reduction_cause(u), CG.MitigationCause.NONE,
		"the hide is gone, so naming it would be a lie")

## Nothing in content puts SHIELD or BLOCK on an enemy today, so this covers a
## path only the seam can reach. It is here because it was silently broken and
## the next action that buffs an enemy must not rediscover it.
func test_a_shielded_enemy_is_actually_shielded() -> void:
	var u := CombatUnit.new()
	u.enemy_id = EnemyLibrary.all_ids()[0]
	var bare: float = SimDeps._default_damage_reduction(u)
	u.statuses[CG.Status.SHIELD] = 999
	assert_almost_eq(SimDeps._default_damage_reduction(u), bare + StatusLibrary.of(CG.Status.SHIELD).damage_reduction)
	assert_eq(SimDeps._default_damage_reduction_cause(u), CG.MitigationCause.SHIELD)

func test_a_blocking_enemy_is_actually_blocking() -> void:
	var u := CombatUnit.new()
	u.enemy_id = EnemyLibrary.all_ids()[0]
	var bare: float = SimDeps._default_damage_reduction(u)
	u.statuses[CG.Status.BLOCK] = 999
	assert_almost_eq(SimDeps._default_damage_reduction(u), bare + StatusLibrary.of(CG.Status.BLOCK).damage_reduction)

## The seam and Balance must agree for every target, which is the property the
## old enemy short-circuit broke.
func test_the_seam_agrees_with_balance_for_every_enemy_in_content() -> void:
	var checked := 0
	for id in EnemyLibrary.all_ids():
		for marked in [false, true]:
			var u := CombatUnit.new()
			u.enemy_id = id
			if marked:
				u.statuses[CG.Status.MARKED] = 999
			assert_almost_eq(SimDeps._default_damage_reduction(u), Balance.damage_reduction(u),
				0.0001, "seam disagrees with Balance for %s (marked %s)" % [id, marked])
			checked += 1
	assert_eq(checked, EnemyLibrary.all_ids().size() * 2,
		"'every enemy in content' is the claim, so the count must be the roster, not a floor under it")

# ---------------------------------------------------------------------------
# issue 364: why ARMOR is never the cause
# ---------------------------------------------------------------------------

## The answer is not a wiring defect. Plate mail's 5% is real and is counted;
## it is simply always smaller than the Warrior's own toughness, and the cause
## names one contributor.
## Issue 489 took every number off plate, so the Warrior's mitigation is now
## entirely its own toughness and the named cause has to say so. Rewritten
## rather than deleted: what this always guarded is that the cause names the
## larger source, and CON is the source that still exists.
func test_the_warriors_mitigation_is_all_toughness_now() -> void:
	var pawn := PawnFactory.make_starter_pawn(&"warrior", &"w", "w")
	assert_not_null(pawn.armor, "the warrior must still start in armour")
	assert_eq(pawn.armor.damage_reduction, 0.0,
		"issue 489: plate grants Directional Block and absorbs nothing")
	var u := CombatUnit.new()
	u.pawn = pawn
	var with_plate: float = SimDeps._default_damage_reduction(u)
	pawn.armor = null
	var without: float = SimDeps._default_damage_reduction(u)
	assert_almost_eq(with_plate, without, 0.0001,
		"plate is still moving the number, so something numeric survived the ruling")
	assert_true(with_plate > 0.0, "a Warrior with 14 CON must still mitigate something")
	u.pawn = PawnFactory.make_starter_pawn(&"warrior", &"w", "w")
	assert_eq(SimDeps._default_damage_reduction_cause(u), CG.MitigationCause.TOUGHNESS)

## And the ARMOR branch is reachable, so the enum value is not dead: give a pawn
## armour heavier than its own toughness and the cause says so.
func test_armour_heavier_than_toughness_is_named() -> void:
	var pawn := PawnData.new()
	pawn.attribute_bonus[CG.Attribute.CON] = 2
	var heavy := EquipmentDef.new()
	heavy.damage_reduction = 0.4
	pawn.armor = heavy
	var u := CombatUnit.new()
	u.pawn = pawn
	assert_eq(SimDeps._default_damage_reduction_cause(u), CG.MitigationCause.ARMOR)
