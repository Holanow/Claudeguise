extends "res://Tests/TestCase.gd"

## Issue 931: README's four verbs, each measured for what it actually returns
## rather than for the percentage it is authored with.
##
## Two of the four reuse a seam that already existed -- cooldown recovery is the
## Book's, and an on-hit trigger is `AbilityModifiers.added_statuses`. Leech and
## resource-on-kill fire on events the simulation already emits.

func _affix(effect: AffixDef.Effect, value: float) -> AffixRoll:
	var a := AffixDef.new()
	a.id = &"probe_verb"
	a.display_name = "Probe"
	a.kind = AffixDef.Kind.VERB
	a.effect = effect
	var r := AffixRoll.new()
	r.affix = a
	r.value = value
	return r

func _item(roll: AffixRoll) -> EquipmentDef:
	var e := EquipmentDef.new()
	e.id = &"probe_item"
	e.display_name = "Probe Blade"
	e.affixes = [roll] as Array[AffixRoll]
	return e

func _action() -> ActionDef:
	var h := HitEffect.new()
	h.damage_type = CG.DamageType.PHYSICAL
	h.power_scale = 1.0
	var a := ActionDef.new()
	a.id = &"probe_swing"
	a.display_name = "Probe Swing"
	a.effects = [h] as Array[AbilityEffect]
	a.targeting = ActionTargeting.new()
	a.targeting.range_units = 40.0
	return a

## Every draw comes from `state.rng`, so the fixture fixes the seed and nothing
## reads the global stream.
func _deps(power: float) -> SimDeps:
	var d := SimDeps.new()
	d.attack_power = func(_u: CombatUnit, _a: ActionDef, _r: RandomNumberGenerator = null) -> float:
		return power
	d.damage_reduction = func(_u: CombatUnit) -> float:
		return 0.0
	return d

func _unit(id: int, team: CG.Team, hp: int, roll: AffixRoll) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.display_name = "Unit %d" % id
	u.hp = hp
	u.hp_max = hp
	u.resource = 0
	u.resource_max = 100
	u.resource_kind = CG.ResourceKind.ENERGY
	if roll != null:
		u.pawn = PawnData.new()
		u.pawn.main_hand = _item(roll)
	return u

func _state(attacker: CombatUnit, target: CombatUnit, seed_value: int) -> CombatState:
	var s := CombatState.new(seed_value)
	s.units.append(attacker)
	s.units.append(target)
	return s

func _events(state: CombatState, kind: CG.EventKind) -> Array:
	var out: Array = []
	for e in state.events:
		if e.kind == kind:
			out.append(e)
	return out

# ---------------------------------------------------------------------------
# Leech
# ---------------------------------------------------------------------------

func test_leech_returns_health_and_says_which_piece_did_it() -> void:
	var attacker := _unit(0, CG.Team.PLAYER, 100, _affix(AffixDef.Effect.LIFE_LEECH, 0.5))
	attacker.hp = 50
	var target := _unit(1, CG.Team.ENEMY, 100, null)
	var state := _state(attacker, target, 931)
	CombatSim._apply_damage(state, attacker, target, _action(), 0.0, _deps(20.0))
	assert_eq(attacker.hp, 60, "half of a 20 damage hit is 10 health back")
	var leeched := _events(state, CG.EventKind.LEECHED)
	assert_eq(leeched.size(), 1, "the log has to be able to see it")
	assert_eq(leeched[0].amount, 10)
	var view := CombatLogView.new()
	assert_eq(view.line_for_event(state, leeched[0]),
		"Unit 0 leeches [color=%s]10[/color] health [color=%s][Probe Blade: Probe][/color]" % [
			Palette.HP_FULL.to_html(), Palette.INK_DIM.to_html()],
		"a proc the player cannot attribute is a hidden number, which is the defect")
	view.free()

## The measurement #925 asks for: 5% of a 7 damage hit is 0.35 of a point, and
## `round` would return nothing at all. `_stochastic_round` pays it as a 35%
## chance of one point, which is the honest rate and is drawn from `state.rng`.
func test_a_few_percent_of_a_small_hit_is_not_rounded_away() -> void:
	var healed := 0
	for i in 2000:
		var attacker := _unit(0, CG.Team.PLAYER, 100, _affix(AffixDef.Effect.LIFE_LEECH, 0.05))
		attacker.hp = 50
		var target := _unit(1, CG.Team.ENEMY, 100, null)
		var state := _state(attacker, target, i)
		CombatSim._apply_damage(state, attacker, target, _action(), 0.0, _deps(7.0))
		healed += attacker.hp - 50
	assert_almost_eq(float(healed) / 2000.0, 0.35, 0.04,
		"5% of 7 damage has to pay 0.35 a hit on average, not 0")

## Taken off what the attack actually removed, so a killing blow on a target
## with 2 health left leeches off 2 and not off the whole swing.
func test_leech_reads_applied_damage_rather_than_overkill() -> void:
	var attacker := _unit(0, CG.Team.PLAYER, 100, _affix(AffixDef.Effect.LIFE_LEECH, 1.0))
	attacker.hp = 50
	var target := _unit(1, CG.Team.ENEMY, 2, null)
	var state := _state(attacker, target, 4)
	CombatSim._apply_damage(state, attacker, target, _action(), 0.0, _deps(40.0))
	assert_eq(attacker.hp, 52, "the health the hit removed is the health it can return")

func test_a_pawn_with_no_leech_draws_nothing() -> void:
	var attacker := _unit(0, CG.Team.PLAYER, 100, null)
	var target := _unit(1, CG.Team.ENEMY, 100, null)
	var state := _state(attacker, target, 7)
	var before := state.rng.state
	CombatSim._apply_damage(state, attacker, target, _action(), 0.0, _deps(20.0))
	assert_eq(state.rng.state, before, "an absent verb must not move the stream")
	assert_eq(_events(state, CG.EventKind.LEECHED).size(), 0)

# ---------------------------------------------------------------------------
# Resource on kill
# ---------------------------------------------------------------------------

func test_a_kill_refunds_a_share_of_the_killers_own_pool() -> void:
	var killer := _unit(0, CG.Team.PLAYER, 100, _affix(AffixDef.Effect.RESOURCE_ON_KILL, 0.25))
	var target := _unit(1, CG.Team.ENEMY, 10, null)
	var state := _state(killer, target, 931)
	target.hp = 0
	CombatSim._kill_if_dead(state, target, killer.id, &"probe_swing")
	assert_eq(killer.resource, 25, "a quarter of a pool of 100")
	var gained := _events(state, CG.EventKind.RESOURCE_GAINED)
	assert_eq(gained.size(), 1)
	var view := CombatLogView.new()
	assert_eq(view.line_for_event(state, gained[0]),
		"Unit 0 gains 25 Energy from the kill [color=%s][Probe Blade: Probe][/color]"
			% Palette.INK_DIM.to_html())
	view.free()

## `_kill_summons_of` names the summoner as the source of its own summons'
## deaths, and `_pay_sustain_with_health` is a unit killing itself. Neither is a
## kill, and both would pay a verb that only checked for a source id.
func test_a_unit_is_never_paid_for_its_own_side_dying() -> void:
	var killer := _unit(0, CG.Team.PLAYER, 100, _affix(AffixDef.Effect.RESOURCE_ON_KILL, 0.25))
	var ally := _unit(1, CG.Team.PLAYER, 10, null)
	var state := _state(killer, ally, 3)
	ally.hp = 0
	CombatSim._kill_if_dead(state, ally, killer.id, &"")
	assert_eq(killer.resource, 0, "a summon dying with its summoner is not a kill")
	killer.hp = 0
	CombatSim._kill_if_dead(state, killer, killer.id, &"")
	assert_eq(killer.resource, 0, "nor is killing yourself")

# ---------------------------------------------------------------------------
# Cooldown recovery -- the Book's seam, in the units an affix rolls in
# ---------------------------------------------------------------------------

func test_cooldown_recovery_adds_to_the_books_own_points() -> void:
	var pawn := PawnData.new()
	pawn.main_hand = _item(_affix(AffixDef.Effect.COOLDOWN_RECOVERY, 0.10))
	var book := EquipmentDef.new()
	book.id = &"probe_book"
	book.display_name = "Probe Book"
	book.cooldown_reduction_percent = 20.0
	pawn.off_hand = book
	assert_almost_eq(pawn.gear_cooldown_reduction(), 0.30, 0.0001,
		"20 percentage points and a rolled 0.10 are one number to the wearer")
	var u := CombatUnit.new()
	u.pawn = pawn
	assert_eq(CombatSim.geared_cooldown_ticks(u, 200), 140)

## Issue 851 spent three issues making a cooldown legible; the chip divides by
## the wait this unit actually has, or the bar starts part-full and the sentence
## names a total nobody waits.
func test_the_cooldown_chip_divides_by_the_wait_the_pawn_actually_has() -> void:
	var pawn := PawnData.new()
	pawn.main_hand = _item(_affix(AffixDef.Effect.COOLDOWN_RECOVERY, 0.50))
	var u := CombatUnit.new()
	u.id = 0
	u.team = CG.Team.PLAYER
	u.pawn = pawn
	u.actions = [&"warrior_block"] as Array[StringName]
	var action := ActionLibrary.get_action(&"warrior_block")
	var whole := CombatSim.geared_cooldown_ticks(u, action.cooldown_ticks)
	assert_eq(whole, int(round(float(action.cooldown_ticks) * 0.5)))
	var state := CombatState.new(1)
	state.units.append(u)
	u.cooldowns[&"warrior_block"] = whole
	var entry: Dictionary = TeamStatusView.cooldowns_for(state, u)[0]
	assert_almost_eq(float(entry["fraction"]), 1.0, 0.0001,
		"a cooldown that just started is a full bar")
	assert_true(String(entry["wait_text"]).contains(TeamStatusView.seconds_text(whole)),
		"the sentence names the wait: %s" % entry["wait_text"])

# ---------------------------------------------------------------------------
# On-hit trigger -- the seam #632 already built
# ---------------------------------------------------------------------------

func _bleed_affix(chance: float) -> AffixRoll:
	var r := _affix(AffixDef.Effect.ON_HIT_STATUS, chance)
	r.affix.display_name = "Serrated"
	r.affix.status = CG.Status.BLEED
	r.affix.status_ticks = 30
	return r

func test_an_on_hit_affix_reaches_the_same_list_a_modifier_does() -> void:
	var attacker := _unit(0, CG.Team.PLAYER, 100, _bleed_affix(1.0))
	var extras := AbilityModifiers.added_statuses(attacker, _action())
	assert_eq(extras.size(), 1)
	assert_eq(int(extras[0]["status"]), int(CG.Status.BLEED))
	assert_eq(int(extras[0]["ticks"]), 30)
	assert_almost_eq(float(extras[0]["chance"]), 1.0, 0.0001)
	assert_eq(String(extras[0]["source"]), "Probe Blade: Serrated")

func test_the_log_names_the_piece_that_procced() -> void:
	var attacker := _unit(0, CG.Team.PLAYER, 100, _bleed_affix(1.0))
	var target := _unit(1, CG.Team.ENEMY, 100, null)
	var state := _state(attacker, target, 931)
	var action := _action()
	CombatSim._apply_action_effect(state, attacker, target, action, _deps(20.0))
	var applied := _events(state, CG.EventKind.STATUS_APPLIED)
	assert_eq(applied.size(), 1, "a certain proc lands on every hit that dealt damage")
	assert_true(target.has_status(CG.Status.BLEED), "and the target really is bleeding")
	## Against a registered attack whose own effects never apply Bleed, so the
	## tag can only have come from the gear. `proc_source_text` reads the same
	## list the simulation drew the chance from.
	var e := CombatEvent.make(CG.EventKind.STATUS_APPLIED, 1)
	e.source_id = 0
	e.target_id = 1
	e.action_id = &"warrior_strike"
	e.status = CG.Status.BLEED
	assert_false(CombatLogView._action_applies(ActionLibrary.get_action(&"warrior_strike"), CG.Status.BLEED),
		"the fixture only means anything if the attack itself does not bleed")
	assert_eq(CombatLogView.proc_source_text(attacker, e), "Probe Blade: Serrated")

## Measured rather than assumed: a 20% chance draws once per landed hit, from
## `state.rng`, and lands about a fifth of the time.
func test_a_rolled_chance_lands_at_the_rate_it_says() -> void:
	var landed := 0
	for i in 2000:
		var attacker := _unit(0, CG.Team.PLAYER, 100, _bleed_affix(0.20))
		var target := _unit(1, CG.Team.ENEMY, 500, null)
		var state := _state(attacker, target, i)
		CombatSim._apply_action_effect(state, attacker, target, _action(), _deps(20.0))
		if target.has_status(CG.Status.BLEED):
			landed += 1
	assert_almost_eq(float(landed) / 2000.0, 0.20, 0.03, "a fifth of landed hits bleed")
