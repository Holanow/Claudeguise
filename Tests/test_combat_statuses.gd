extends "res://Tests/TestCase.gd"


## Covers issue 10's five acceptance criteria: BURN/POISON damage-over-time,
## HASTE, and the stun-interrupt decision.
##
## **That last one was overturned by the player in #121: a stun now DOES cancel
## an action already committed.** The wind-up is lost, the resource is not
## refunded, and CombatSim emits INTERRUPTED. The criterion-5 section below was
## inverted rather than rewritten from scratch, so the same fixture that used to
## prove the action fired now proves it does not.

func _unit(id: int, team: CG.Team, hp: int, pos: Vector2, actions: Array[StringName]) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.hp_max = hp
	u.hp = hp
	u.position = pos
	u.move_speed = 8.0
	u.actions = actions
	return u

func _idle_deps() -> SimDeps:
	var deps := SimDeps.new()
	deps.default_decide = func(_s: CombatState, _u: CombatUnit) -> Intent: return Intent.idle()
	return deps

## Same reasoning as the terrain tests: a fight with only one team ends
## PLAYER_WIN after tick one and every later step() no-ops, which looks
## exactly like a frozen simulation and is not one.
func _dummy_enemy(id: int) -> CombatUnit:
	return _unit(id, CG.Team.ENEMY, 10, Vector2(100000, 100000), [])

func _melee(id: StringName, wind_up: int, recover: int, range_units: float) -> ActionDef:
	var a := ActionDef.new()
	a.id = id
	a.wind_up_ticks = wind_up
	a.recover_ticks = recover
	a.range_units = range_units
	a.damage_type = CG.DamageType.PHYSICAL
	return a

# ---------------------------------------------------------------------------
# criterion 1: a DOT status damages, and stops
# ---------------------------------------------------------------------------

func test_burn_damages_each_tick_and_stops_the_tick_after_it_expires() -> void:
	var deps := _idle_deps()
	deps.status_damage_per_tick = func(_u: CombatUnit, _s: CG.Status) -> float: return 4.0

	var state := CombatState.new(80)
	var unit := _unit(0, CG.Team.PLAYER, 30, Vector2.ZERO, [])
	unit.statuses[CG.Status.BURN] = 3 # expires once state.tick >= 3
	state.units.append(unit)
	state.units.append(_dummy_enemy(1))

	CombatSim.step(state, deps) # tick 1: burning
	assert_eq(unit.hp, 26)
	CombatSim.step(state, deps) # tick 2: burning
	assert_eq(unit.hp, 22)
	CombatSim.step(state, deps) # tick 3: still burns on the expiry tick itself
	assert_eq(unit.hp, 18)
	assert_false(unit.has_status(CG.Status.BURN), "BURN must actually be gone once expired")

	CombatSim.step(state, deps) # tick 4: expired, no more damage
	assert_eq(unit.hp, 18, "no damage the tick after BURN expires")

func test_poison_also_damages_and_uses_its_own_damage_type() -> void:
	var deps := _idle_deps()
	deps.status_damage_per_tick = func(_u: CombatUnit, _s: CG.Status) -> float: return 3.0

	var state := CombatState.new(81)
	var unit := _unit(0, CG.Team.PLAYER, 30, Vector2.ZERO, [])
	unit.statuses[CG.Status.POISON] = 2
	state.units.append(unit)
	state.units.append(_dummy_enemy(1))

	CombatSim.step(state, deps)
	CombatSim.step(state, deps)
	assert_eq(unit.hp, 24)

	var found_profane := false
	for e in state.events:
		if e.kind == CG.EventKind.DAMAGE and e.target_id == 0 and e.damage_type == CG.DamageType.PROFANE:
			found_profane = true
	assert_true(found_profane, "poison damage should be tagged PROFANE per README's damage-type pairing")

# ---------------------------------------------------------------------------
# criterion 2: visible in the event stream (issue 1's replay invariant)
# ---------------------------------------------------------------------------

func test_replaying_events_reaches_the_same_hp_with_dot_in_play() -> void:
	var deps := _idle_deps()
	deps.status_damage_per_tick = func(_u: CombatUnit, _s: CG.Status) -> float: return 5.0

	var state := CombatState.new(82)
	var unit := _unit(0, CG.Team.PLAYER, 30, Vector2.ZERO, [])
	unit.statuses[CG.Status.BURN] = 4
	state.units.append(unit)
	state.units.append(_dummy_enemy(1))

	for i in 5:
		CombatSim.step(state, deps)

	var replayed := 30
	for e in state.events:
		if e.kind == CG.EventKind.DAMAGE:
			replayed -= e.amount
		elif e.kind == CG.EventKind.HEAL:
			replayed += e.amount
	assert_eq(replayed, unit.hp, "DOT damage must be reachable purely from the event stream")

# ---------------------------------------------------------------------------
# criterion 3: HASTE speeds a unit up, measurably
# ---------------------------------------------------------------------------

func test_haste_reduces_ticks_to_complete_an_action_and_a_unit_without_it_is_unaffected() -> void:
	var atk := _melee(&"atk", 10, 6, 999.0)
	var actions_by_id := {atk.id: atk}
	var deps := SimDeps.new()
	deps.action_lookup = func(id: StringName): return actions_by_id.get(id)
	deps.attack_power = func(_u, _a, _r=null) -> float: return 0.0
	deps.damage_reduction = func(_u) -> float: return 0.0
	deps.wind_up_ticks = func(_u, a: ActionDef) -> int: return a.wind_up_ticks
	deps.recover_ticks = func(_u, a: ActionDef) -> int: return a.recover_ticks
	deps.haste_tick_scale = func(_u: CombatUnit) -> float: return 0.5
	deps.default_decide = func(_s, _u): return Intent.idle()

	# Hasted: committed action should take half as many ticks to fire.
	var state_a := CombatState.new(83)
	var hasted := _unit(0, CG.Team.PLAYER, 30, Vector2.ZERO, [atk.id])
	hasted.statuses[CG.Status.HASTE] = 999
	var target_a := _unit(1, CG.Team.ENEMY, 30, Vector2(1, 0), [])
	state_a.units.append(hasted)
	state_a.units.append(target_a)
	hasted.intent = Intent.use_action(atk.id, target_a.id)

	var fired_tick_hasted := -1
	for i in 20:
		CombatSim.step(state_a, deps)
		for e in state_a.events:
			if e.kind == CG.EventKind.ACTION_FIRE and e.source_id == 0 and fired_tick_hasted == -1:
				fired_tick_hasted = state_a.tick

	# Not hasted: same action, same wind-up, no status.
	var state_b := CombatState.new(84)
	var plain := _unit(0, CG.Team.PLAYER, 30, Vector2.ZERO, [atk.id])
	var target_b := _unit(1, CG.Team.ENEMY, 30, Vector2(1, 0), [])
	state_b.units.append(plain)
	state_b.units.append(target_b)
	plain.intent = Intent.use_action(atk.id, target_b.id)

	var fired_tick_plain := -1
	for i in 20:
		CombatSim.step(state_b, deps)
		for e in state_b.events:
			if e.kind == CG.EventKind.ACTION_FIRE and e.source_id == 0 and fired_tick_plain == -1:
				fired_tick_plain = state_b.tick

	print("issue 10: haste wind-up ticks-to-fire: hasted=%d plain=%d (base wind_up=%d)" % [fired_tick_hasted, fired_tick_plain, atk.wind_up_ticks])
	assert_eq(fired_tick_plain, atk.wind_up_ticks, "an unhasted unit must be unaffected: fires exactly on the base wind-up")
	assert_true(fired_tick_hasted < fired_tick_plain, "a hasted unit must fire sooner than an identical unhasted one")
	assert_eq(fired_tick_hasted, int(round(float(atk.wind_up_ticks) * 0.5)))

# ---------------------------------------------------------------------------
# criterion 4: determinism survives with DOT and haste in play
# ---------------------------------------------------------------------------

func test_determinism_holds_with_dot_and_haste_in_play() -> void:
	var atk := _melee(&"atk", 4, 1, 999.0)
	var actions_by_id := {atk.id: atk}

	var make_deps := func() -> SimDeps:
		var d := SimDeps.new()
		d.action_lookup = func(id: StringName): return actions_by_id.get(id)
		d.attack_power = func(_u, _a, _r=null) -> float: return 6.0
		d.damage_reduction = func(_u) -> float: return 0.0
		d.wind_up_ticks = func(_u, a: ActionDef) -> int: return a.wind_up_ticks
		d.recover_ticks = func(_u, a: ActionDef) -> int: return a.recover_ticks
		d.haste_tick_scale = func(_u: CombatUnit) -> float: return 0.7
		d.status_damage_per_tick = func(_u: CombatUnit, _s: CG.Status) -> float: return 1.3 # fractional: forces stochastic rounding
		d.default_decide = func(_s, _u): return Intent.idle()
		return d

	var make_state := func(seed: int) -> CombatState:
		var s := CombatState.new(seed)
		var a := _unit(0, CG.Team.PLAYER, 30, Vector2.ZERO, [atk.id])
		a.statuses[CG.Status.HASTE] = 999
		a.statuses[CG.Status.BURN] = 30
		var b := _unit(1, CG.Team.ENEMY, 30, Vector2(1, 0), [])
		s.units.append(a)
		s.units.append(b)
		a.intent = Intent.use_action(atk.id, b.id)
		return s

	var state_a: CombatState = make_state.call(85)
	var state_b: CombatState = make_state.call(85)
	var deps_a: SimDeps = make_deps.call()
	var deps_b: SimDeps = make_deps.call()
	for i in 20:
		CombatSim.step(state_a, deps_a)
		CombatSim.step(state_b, deps_b)

	assert_eq(state_a.events.size(), state_b.events.size(), "same seed, same DOT/haste, same event count")
	for i in state_a.events.size():
		var ea: CombatEvent = state_a.events[i]
		var eb: CombatEvent = state_b.events[i]
		assert_eq(ea.kind, eb.kind, "event %d kind diverged" % i)
		assert_eq(ea.amount, eb.amount, "event %d amount diverged" % i)
	assert_eq(state_a.units[0].hp, state_b.units[0].hp)

# ---------------------------------------------------------------------------
# criterion 5: the interrupt decision, documented and tested
# ---------------------------------------------------------------------------

## ISSUE 10'S DECISION WAS OVERTURNED BY THE PLAYER (#121): *"Stun should very
## much interrupt actions in progress"*. This test used to be
## `test_stun_does_not_cancel_an_action_already_committed` and asserted the
## opposite of what it asserts now. It is inverted rather than deleted, and it
## is the same fixture, so the two behaviours are directly comparable: an
## identical setup that used to end with the target at 20 hp now ends with it
## untouched.
##
## Rewriting somebody else's assertion to go green is forbidden here. This one is
## mine (`Tests/test_combat_*` is this session's), it encodes a decision the
## player has since reversed rather than a property that still holds, and the PR
## says so plainly.
func test_stun_cancels_an_action_already_committed() -> void:
	var atk := _melee(&"atk", 5, 1, 999.0)
	var actions_by_id := {atk.id: atk}
	var deps := SimDeps.new()
	deps.action_lookup = func(id: StringName): return actions_by_id.get(id)
	deps.attack_power = func(_u, _a, _r=null) -> float: return 10.0
	deps.damage_reduction = func(_u) -> float: return 0.0
	deps.wind_up_ticks = func(_u, a: ActionDef) -> int: return a.wind_up_ticks
	deps.recover_ticks = func(_u, a: ActionDef) -> int: return a.recover_ticks
	deps.default_decide = func(_s, _u): return Intent.idle()

	var state := CombatState.new(86)
	var attacker := _unit(0, CG.Team.PLAYER, 30, Vector2.ZERO, [atk.id])
	var target := _unit(1, CG.Team.ENEMY, 30, Vector2(1, 0), [])
	state.units.append(attacker)
	state.units.append(target)

	attacker.intent = Intent.use_action(atk.id, target.id)
	CombatSim.step(state, deps) # tick 1: commits, action_ticks_left = 5 -> 4

	attacker.statuses[CG.Status.STUN] = 999 # stunned mid-wind-up

	for _i in 4: # ticks 2-5: the wind-up would have completed inside this window
		CombatSim.step(state, deps)

	assert_eq(_count(state, CG.EventKind.ACTION_FIRE), 0, "the committed action must never fire")
	assert_eq(target.hp, target.hp_max, "and therefore must land nothing")
	assert_eq(attacker.action_ticks_left, 0, "the wind-up is gone")
	assert_eq(attacker.action_ticks_total, 0, "and so is its denominator, so no ring is drawn")
	assert_eq(attacker.current_action, &"", "the unit is holding nothing")

	assert_eq(_count(state, CG.EventKind.INTERRUPTED), 1, "said so exactly once")
	var e := _first(state, CG.EventKind.INTERRUPTED)
	assert_eq(e.source_id, 0, "the subject is the unit that lost the action, not the interrupter")
	assert_eq(e.target_id, -1, "nothing is aimed at")
	assert_eq(e.action_id, atk.id, "and it names what was lost")
	assert_eq(e.amount, 1, "one tick of the five-tick wind-up had been invested and is thrown away")

## The wind-up is LOST, not resumed. Once the stun ends the unit has to commit
## again from scratch -- with a decision layer that never asks for the action
## again, nothing ever fires. A resumed wind-up would be nearly invisible to
## somebody watching, which is what makes this the player's call rather than a
## detail.
func test_the_interrupted_wind_up_is_not_resumed_when_the_stun_ends() -> void:
	var atk := _melee(&"atk", 5, 1, 999.0)
	var actions_by_id := {atk.id: atk}
	var deps := SimDeps.new()
	deps.action_lookup = func(id: StringName): return actions_by_id.get(id)
	deps.attack_power = func(_u, _a, _r=null) -> float: return 10.0
	deps.damage_reduction = func(_u) -> float: return 0.0
	deps.wind_up_ticks = func(_u, a: ActionDef) -> int: return a.wind_up_ticks
	deps.recover_ticks = func(_u, a: ActionDef) -> int: return a.recover_ticks
	deps.default_decide = func(_s, _u): return Intent.idle()

	var state := CombatState.new(88)
	var attacker := _unit(0, CG.Team.PLAYER, 30, Vector2.ZERO, [atk.id])
	var target := _unit(1, CG.Team.ENEMY, 30, Vector2(1, 0), [])
	state.units.append(attacker)
	state.units.append(target)

	attacker.intent = Intent.use_action(atk.id, target.id)
	CombatSim.step(state, deps)
	attacker.statuses[CG.Status.STUN] = 3 # expires once state.tick >= 3

	for _i in 20:
		CombatSim.step(state, deps)

	assert_false(attacker.has_status(CG.Status.STUN), "the stun really did wear off")
	assert_eq(_count(state, CG.EventKind.ACTION_FIRE), 0, "and the lost wind-up did not pick itself back up")
	assert_eq(target.hp, target.hp_max)

## The resource is NOT refunded, the player's ruling and the harshest half of it.
## RESOURCE_SPENT fired at commit and nothing reverses it.
func test_an_interrupt_does_not_refund_the_resource() -> void:
	var atk := _melee(&"atk", 5, 1, 999.0)
	atk.resource_cost = 7
	var actions_by_id := {atk.id: atk}
	var deps := SimDeps.new()
	deps.action_lookup = func(id: StringName): return actions_by_id.get(id)
	deps.attack_power = func(_u, _a, _r=null) -> float: return 10.0
	deps.damage_reduction = func(_u) -> float: return 0.0
	deps.wind_up_ticks = func(_u, a: ActionDef) -> int: return a.wind_up_ticks
	deps.recover_ticks = func(_u, a: ActionDef) -> int: return a.recover_ticks
	deps.resource_regen_per_tick = func(_u) -> float: return 0.0
	deps.default_decide = func(_s, _u): return Intent.idle()

	var state := CombatState.new(89)
	var attacker := _unit(0, CG.Team.PLAYER, 30, Vector2.ZERO, [atk.id])
	attacker.resource_kind = CG.ResourceKind.MANA
	attacker.resource_max = 20
	attacker.resource = 20
	var target := _unit(1, CG.Team.ENEMY, 30, Vector2(1, 0), [])
	state.units.append(attacker)
	state.units.append(target)

	attacker.intent = Intent.use_action(atk.id, target.id)
	CombatSim.step(state, deps)
	assert_eq(attacker.resource, 13, "charged at commit, as it always was")

	attacker.statuses[CG.Status.STUN] = 999
	for _i in 5:
		CombatSim.step(state, deps)

	assert_eq(attacker.resource, 13, "and never given back")
	assert_eq(_count(state, CG.EventKind.RESOURCE_SPENT), 1, "no negative event either")

## One event per interrupted action, not one per stunned tick. A stun that
## outlasts the cast finds nothing left to cancel on its second tick.
func test_a_long_stun_interrupts_once_and_not_once_per_tick() -> void:
	var atk := _melee(&"atk", 5, 1, 999.0)
	var actions_by_id := {atk.id: atk}
	var deps := SimDeps.new()
	deps.action_lookup = func(id: StringName): return actions_by_id.get(id)
	deps.attack_power = func(_u, _a, _r=null) -> float: return 10.0
	deps.damage_reduction = func(_u) -> float: return 0.0
	deps.wind_up_ticks = func(_u, a: ActionDef) -> int: return a.wind_up_ticks
	deps.recover_ticks = func(_u, a: ActionDef) -> int: return a.recover_ticks
	deps.default_decide = func(_s, _u): return Intent.idle()

	var state := CombatState.new(90)
	var attacker := _unit(0, CG.Team.PLAYER, 30, Vector2.ZERO, [atk.id])
	var target := _unit(1, CG.Team.ENEMY, 30, Vector2(1, 0), [])
	state.units.append(attacker)
	state.units.append(target)

	attacker.intent = Intent.use_action(atk.id, target.id)
	CombatSim.step(state, deps)
	attacker.statuses[CG.Status.STUN] = 999
	for _i in 30:
		CombatSim.step(state, deps)

	assert_eq(_count(state, CG.EventKind.INTERRUPTED), 1, "thirty stunned ticks, one interrupt")

## THE NEGATIVE TEST, and the one this mechanism most needs. A detector that
## fires on healthy input becomes furniture: a stun landing on a unit that was
## not committed to anything has taken nothing away, and must say nothing.
func test_a_stun_on_a_free_unit_interrupts_nothing() -> void:
	var deps := _idle_deps()
	var state := CombatState.new(91)
	var unit := _unit(0, CG.Team.PLAYER, 30, Vector2.ZERO, [])
	unit.statuses[CG.Status.STUN] = 999
	state.units.append(unit)
	state.units.append(_dummy_enemy(1))

	for _i in 10:
		CombatSim.step(state, deps)

	assert_eq(_count(state, CG.EventKind.INTERRUPTED), 0, "nothing was committed, so nothing was lost")

## The other half of the same worry: a fight with no stun in it at all must
## produce no interrupts, however many actions are committed and fired.
func test_a_fight_with_no_stun_emits_no_interrupt() -> void:
	var atk := _melee(&"atk", 3, 2, 999.0)
	var actions_by_id := {atk.id: atk}
	var deps := SimDeps.new()
	deps.action_lookup = func(id: StringName): return actions_by_id.get(id)
	deps.attack_power = func(_u, _a, _r=null) -> float: return 2.0
	deps.damage_reduction = func(_u) -> float: return 0.0
	deps.wind_up_ticks = func(_u, a: ActionDef) -> int: return a.wind_up_ticks
	deps.recover_ticks = func(_u, a: ActionDef) -> int: return a.recover_ticks
	deps.default_decide = func(_s: CombatState, u: CombatUnit) -> Intent:
		return Intent.use_action(atk.id, 1 if u.id == 0 else 0)

	var state := CombatState.new(92)
	state.units.append(_unit(0, CG.Team.PLAYER, 30, Vector2.ZERO, [atk.id]))
	state.units.append(_unit(1, CG.Team.ENEMY, 30, Vector2(1, 0), [atk.id]))
	CombatSim.run(state, deps)

	assert_ne(_count(state, CG.EventKind.ACTION_FIRE), 0, "the fixture really did fight")
	assert_eq(_count(state, CG.EventKind.INTERRUPTED), 0, "and nothing was ever interrupted")

## Recovery is deliberately NOT cancelled. Cancelling it would let a stunned
## unit come out free to act instead of finishing what it owed, which is an
## interrupt that rewards its victim.
func test_a_stun_does_not_cancel_recovery() -> void:
	var atk := _melee(&"atk", 1, 10, 999.0)
	var actions_by_id := {atk.id: atk}
	var deps := SimDeps.new()
	deps.action_lookup = func(id: StringName): return actions_by_id.get(id)
	deps.attack_power = func(_u, _a, _r=null) -> float: return 1.0
	deps.damage_reduction = func(_u) -> float: return 0.0
	deps.wind_up_ticks = func(_u, a: ActionDef) -> int: return a.wind_up_ticks
	deps.recover_ticks = func(_u, a: ActionDef) -> int: return a.recover_ticks
	deps.default_decide = func(_s, _u): return Intent.idle()

	var state := CombatState.new(93)
	var attacker := _unit(0, CG.Team.PLAYER, 30, Vector2.ZERO, [atk.id])
	var target := _unit(1, CG.Team.ENEMY, 30, Vector2(1, 0), [])
	state.units.append(attacker)
	state.units.append(target)

	attacker.intent = Intent.use_action(atk.id, target.id)
	CombatSim.step(state, deps) # commits and fires: wind_up 1
	CombatSim.step(state, deps)
	assert_ne(attacker.recover_ticks_left, 0, "it is recovering")

	var before := attacker.recover_ticks_left
	attacker.statuses[CG.Status.STUN] = 999
	CombatSim.step(state, deps)

	assert_eq(attacker.recover_ticks_left, before - 1, "recovery keeps running through a stun")
	assert_eq(_count(state, CG.EventKind.INTERRUPTED), 0, "and recovery is not an interruptible commitment")

## A stunned unit neither decides NOR acts, which now includes an intent placed
## before the stun landed. Previously such an intent was still resolved, because
## the stun branch sat behind a guard that skipped any unit already carrying one.
func test_a_stunned_unit_drops_an_intent_it_was_already_holding() -> void:
	var atk := _melee(&"atk", 0, 0, 999.0)
	var actions_by_id := {atk.id: atk}
	var deps := SimDeps.new()
	deps.action_lookup = func(id: StringName): return actions_by_id.get(id)
	deps.attack_power = func(_u, _a, _r=null) -> float: return 10.0
	deps.damage_reduction = func(_u) -> float: return 0.0
	deps.wind_up_ticks = func(_u, a: ActionDef) -> int: return a.wind_up_ticks
	deps.recover_ticks = func(_u, a: ActionDef) -> int: return a.recover_ticks
	deps.default_decide = func(_s, _u): return Intent.idle()

	var state := CombatState.new(94)
	var attacker := _unit(0, CG.Team.PLAYER, 30, Vector2.ZERO, [atk.id])
	var target := _unit(1, CG.Team.ENEMY, 30, Vector2(1, 0), [])
	state.units.append(attacker)
	state.units.append(target)

	attacker.statuses[CG.Status.STUN] = 999
	attacker.intent = Intent.use_action(atk.id, target.id)
	CombatSim.step(state, deps)

	assert_eq(attacker.intent, null, "the intent is dropped")
	assert_eq(target.hp, target.hp_max, "and never resolved")
	assert_eq(_count(state, CG.EventKind.INTERRUPTED), 0, "nothing was committed, so nothing is reported lost")

func _count(state: CombatState, kind: CG.EventKind) -> int:
	var n := 0
	for e in state.events:
		if e.kind == kind:
			n += 1
	return n

func _first(state: CombatState, kind: CG.EventKind) -> CombatEvent:
	for e in state.events:
		if e.kind == kind:
			return e
	return null

func test_stun_does_prevent_a_new_decision() -> void:
	# The other half: a unit that has NOT committed anything and gets
	# stunned issues no intent while stunned, per issue 4's original
	# criterion, unchanged by issue 10's decision.
	var deps := SimDeps.new()
	deps.default_decide = func(_s: CombatState, _u: CombatUnit) -> Intent: return Intent.idle()

	var state := CombatState.new(87)
	var unit := _unit(0, CG.Team.PLAYER, 30, Vector2.ZERO, [])
	unit.statuses[CG.Status.STUN] = 999
	state.units.append(unit)
	state.units.append(_dummy_enemy(1))

	CombatSim.step(state, deps)
	assert_eq(unit.intent, null, "a stunned, uncommitted unit must not receive a fresh intent")
