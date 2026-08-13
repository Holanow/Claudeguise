extends "res://Tests/TestCase.gd"

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")
const CombatEvent := preload("res://Scripts/Core/CombatEvent.gd")
const Intent := preload("res://Scripts/Core/Intent.gd")
const ActionDef := preload("res://Scripts/Core/ActionDef.gd")
const SimDeps := preload("res://Scripts/Combat/SimDeps.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")

## Covers issue 10's five acceptance criteria: BURN/POISON damage-over-time,
## HASTE, and the stun-interrupt decision (documented in
## Scripts/Combat/CombatSim.gd's _decide_phase: stun does not cancel an
## action already committed).

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

func test_stun_does_not_cancel_an_action_already_committed() -> void:
	# The decision, per Scripts/Combat/CombatSim.gd's _decide_phase: stun
	# blocks deciding, not acting. A unit mid-wind-up when stunned still
	# fires on schedule.
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

	for i in 4: # ticks 2-5: still winding up, then fires despite being stunned
		CombatSim.step(state, deps)

	var fired := false
	for e in state.events:
		if e.kind == CG.EventKind.ACTION_FIRE and e.source_id == 0:
			fired = true
	assert_true(fired, "an action committed before the stun landed must still fire")
	assert_eq(target.hp, target.hp_max - 10)

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
