extends "res://Tests/TestCase.gd"


## Issue 703: `ActionDef.beats` replaces a single instant resolution with
## several, each on its own tick, each re-resolving its own targets. Built on
## synthetic actions rather than `sellsword_crescent.tres` so these do not
## drift if the content file's numbers ever change.

func _unit(id: int, team: CG.Team, hp: int, pos: Vector2, actions: Array[StringName]) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.hp_max = hp
	u.hp = hp
	u.position = pos
	u.move_speed = 8.0
	u.radius = 0.0
	u.actions = actions
	return u

func _targeting(range_units: float, splash: float, arc: float) -> ActionTargeting:
	var t := ActionTargeting.new()
	t.range_units = range_units
	t.splash_radius = splash
	t.arc_degrees = arc
	return t

func _hit(power: float) -> HitEffect:
	var h := HitEffect.new()
	h.damage_type = CG.DamageType.PHYSICAL
	h.power_scale = power
	return h

func _beat(delay: int, targeting: ActionTargeting, effects: Array[AbilityEffect]) -> ActionBeat:
	var b := ActionBeat.new()
	b.delay_ticks = delay
	b.targeting = targeting
	b.effects = effects
	return b

## wind_up_ticks == 1: the action commits and fires on the same, single
## step() call, so beat 0 (delay 0) always resolves on that call.
func _combo(id: StringName, beats: Array[ActionBeat]) -> ActionDef:
	var a := ActionDef.new()
	a.id = id
	a.wind_up_ticks = 1
	a.recover_ticks = 2
	a.targeting = ActionTargeting.new()
	a.targeting.range_units = 999.0
	a.effects = [_hit(1.0)] as Array[AbilityEffect]
	a.beats = beats
	return a

## `power` multiplies whichever beat's own `HitEffect.power_scale` is firing --
## the exact seam that silently reads the wrong beat if a beat's effects are
## not threaded through as their own `ActionDef` view.
func _deps_with_action(action: ActionDef, power: float) -> SimDeps:
	var actions_by_id := {action.id: action}
	var deps := SimDeps.new()
	deps.action_lookup = func(id: StringName): return actions_by_id.get(id)
	deps.attack_power = func(_u: CombatUnit, a: ActionDef, _r = null) -> float: return power * a.power_scale
	deps.damage_reduction = func(_u: CombatUnit) -> float: return 0.0
	deps.wind_up_ticks = func(_u: CombatUnit, a: ActionDef) -> int: return a.wind_up_ticks
	deps.recover_ticks = func(_u: CombatUnit, a: ActionDef) -> int: return a.recover_ticks
	deps.default_decide = func(_s: CombatState, _u: CombatUnit) -> Intent: return Intent.idle()
	return deps

func _damage_events(state: CombatState, target_id: int) -> Array[CombatEvent]:
	var out: Array[CombatEvent] = []
	for e in state.events:
		if e.kind == CG.EventKind.DAMAGE and e.target_id == target_id:
			out.append(e)
	return out

# ---------------------------------------------------------------------------
# criterion: three beats fire in order, each with its own reach and power
# ---------------------------------------------------------------------------

func test_three_beats_each_land_with_their_own_reach_and_power() -> void:
	var beats: Array[ActionBeat] = [
		_beat(0, _targeting(999.0, 70.0, 45.0), [StepEffect.new(), _hit(0.8)] as Array[AbilityEffect]),
		_beat(9, _targeting(999.0, 150.0, 65.0), [_hit(3.25)] as Array[AbilityEffect]),
		_beat(18, _targeting(999.0, 200.0, 80.0), [_hit(4.0)] as Array[AbilityEffect]),
	]
	(beats[0].effects[0] as StepEffect).distance = -40.0
	var combo := _combo(&"combo", beats)
	var deps := _deps_with_action(combo, 10.0)

	var state := CombatState.new(703)
	var caster := _unit(0, CG.Team.PLAYER, 200, Vector2.ZERO, [combo.id])
	var target := _unit(1, CG.Team.ENEMY, 9999, Vector2(10, 0), [])
	state.units.append(caster)
	state.units.append(target)
	caster.intent = Intent.use_action(combo.id, target.id)

	for _i in 20:
		CombatSim.step(state, deps)

	var dmg := _damage_events(state, target.id)
	assert_eq(dmg.size(), 3, "all three beats must land as separate hits")
	assert_eq(dmg[0].amount, 8, "beat 1's own power_scale (0.8), not the action's")
	assert_eq(dmg[1].amount, 33, "beat 2's own power_scale (3.25 -> round(32.5))")
	assert_eq(dmg[2].amount, 40, "beat 3's own power_scale (4.0)")
	assert_almost_eq(caster.position.x, -40.0, 0.01, "beat 1's StepEffect steps the caster back")

# ---------------------------------------------------------------------------
# trap 1: a beat that reaches nothing MISSes; the remaining beats still fire
# ---------------------------------------------------------------------------

func test_a_beat_that_reaches_nothing_misses_and_the_rest_still_fire() -> void:
	var beats: Array[ActionBeat] = [
		_beat(0, _targeting(999.0, 70.0, 45.0), [StepEffect.new(), _hit(0.8)] as Array[AbilityEffect]),
		## range_units 40 is less than the 50-unit gap the step above opens, so
		## this beat's own primary-target gate fails and it must MISS.
		_beat(9, _targeting(40.0, 150.0, 65.0), [_hit(3.25)] as Array[AbilityEffect]),
		_beat(18, _targeting(999.0, 200.0, 80.0), [_hit(4.0)] as Array[AbilityEffect]),
	]
	(beats[0].effects[0] as StepEffect).distance = -40.0
	var combo := _combo(&"combo", beats)
	var deps := _deps_with_action(combo, 10.0)

	var state := CombatState.new(704)
	var caster := _unit(0, CG.Team.PLAYER, 200, Vector2.ZERO, [combo.id])
	var target := _unit(1, CG.Team.ENEMY, 9999, Vector2(10, 0), [])
	state.units.append(caster)
	state.units.append(target)
	caster.intent = Intent.use_action(combo.id, target.id)

	for _i in 20:
		CombatSim.step(state, deps)

	var dmg := _damage_events(state, target.id)
	assert_eq(dmg.size(), 2, "beats 1 and 3 land; beat 2 misses")

	var misses := 0
	var fires := 0
	for e in state.events:
		if e.action_id != combo.id:
			continue
		if e.kind == CG.EventKind.MISS:
			misses += 1
			assert_eq(e.beat_index, 1, "the miss must name beat 1 (the second beat)")
		elif e.kind == CG.EventKind.ACTION_FIRE:
			fires += 1
	assert_eq(misses, 1, "exactly one beat misses")
	assert_eq(fires, 3, "all three beats still fire, including the one after the miss")

# ---------------------------------------------------------------------------
# trap 2: a caster who dies mid-combo has pending beats dropped, not resolved
# ---------------------------------------------------------------------------

func test_a_dead_caster_drops_its_pending_beats_instead_of_resolving_them() -> void:
	var beats: Array[ActionBeat] = [
		_beat(0, _targeting(999.0, 70.0, 45.0), [_hit(0.8)] as Array[AbilityEffect]),
		_beat(9, _targeting(999.0, 150.0, 65.0), [_hit(3.25)] as Array[AbilityEffect]),
		_beat(18, _targeting(999.0, 200.0, 80.0), [_hit(4.0)] as Array[AbilityEffect]),
	]
	var combo := _combo(&"combo", beats)
	var deps := _deps_with_action(combo, 10.0)

	var state := CombatState.new(705)
	var caster := _unit(0, CG.Team.PLAYER, 200, Vector2.ZERO, [combo.id])
	var target := _unit(1, CG.Team.ENEMY, 9999, Vector2(10, 0), [])
	## A bystander on each side, so the fight is not decided the instant the
	## caster dies -- `step()` no-ops once `state.outcome` resolves, and a
	## queue nobody ever drains again would prove nothing about the drop.
	var ally := _unit(2, CG.Team.PLAYER, 50, Vector2(-200, 0), [])
	var foe := _unit(3, CG.Team.ENEMY, 50, Vector2(200, 0), [])
	state.units.append(caster)
	state.units.append(target)
	state.units.append(ally)
	state.units.append(foe)
	caster.intent = Intent.use_action(combo.id, target.id)

	CombatSim.step(state, deps) # commits and fires beat 0

	assert_eq(_damage_events(state, target.id).size(), 1, "sanity: beat 0 already landed")
	assert_false(state.pending_beats.is_empty(), "sanity: beats 1 and 2 are queued")

	caster.hp = 0
	caster.alive = false

	for _i in 20:
		CombatSim.step(state, deps)

	assert_true(state.pending_beats.is_empty(), "the dead caster's queue must drain, not linger")
	assert_eq(_damage_events(state, target.id).size(), 1, "no further beat may land from a corpse")
	for e in state.events:
		if e.action_id == combo.id:
			assert_true(e.beat_index <= 0, "no event may name beat 1 or 2: they were dropped, not resolved")

# ---------------------------------------------------------------------------
# trap 3: `_in_arc` reads caster.facing, and the backstep must not change it
# ---------------------------------------------------------------------------

func test_the_backstep_does_not_change_facing_so_later_beats_still_sweep_at_the_target() -> void:
	var beats: Array[ActionBeat] = [
		_beat(0, _targeting(999.0, 70.0, 45.0), [StepEffect.new(), _hit(0.8)] as Array[AbilityEffect]),
		_beat(9, _targeting(999.0, 150.0, 65.0), [_hit(3.25)] as Array[AbilityEffect]),
	]
	(beats[0].effects[0] as StepEffect).distance = -40.0
	var combo := _combo(&"combo", beats)
	var deps := _deps_with_action(combo, 10.0)

	var state := CombatState.new(706)
	var caster := _unit(0, CG.Team.PLAYER, 200, Vector2.ZERO, [combo.id])
	var target := _unit(1, CG.Team.ENEMY, 9999, Vector2(10, 0), [])
	state.units.append(caster)
	state.units.append(target)
	caster.intent = Intent.use_action(combo.id, target.id)

	CombatSim.step(state, deps) # commits, fires beat 0, steps back
	var facing_before := caster.facing
	assert_almost_eq(facing_before.x, 1.0, 0.01, "sanity: facing the target, not the step direction")

	for _i in 10:
		CombatSim.step(state, deps)

	assert_eq(caster.facing, facing_before, "a step must never change facing")
	assert_eq(_damage_events(state, target.id).size(), 2,
		"beat 2 must still sweep at what he is fighting, not at where he jumped from")
