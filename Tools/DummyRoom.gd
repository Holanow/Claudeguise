extends SceneTree

## Issue 667. For every action in `ActionLibrary.PATHS`: one caster, one dummy
## target, forced to fire once, then checks from `state.events` (and unit
## state, where an effect leaves no event) that it did what its own `effects`
## array declares. Expectations are read off each effect's own fields, never a
## hand-written table.
##
## Forces the shot via `SimDeps.default_decide`, on a caster with no `pawn` so
## the plan layer is never reached. Touches nothing under `Scripts/`.

## Long enough for the slowest action in the game (`build_siege_engine`,
## wind-up 90 + recover 20) plus a pull's own 7 drag ticks, with margin.
const RUN_TICKS := 250

## How far apart the pair may be placed. `range_units` runs to ARENA_SPAN for
## the siege bolt, which is wider than the arena; `gap` subtracts both radii, so
## a nearer target satisfies reach just as well and stays in bounds.
const _MAX_PLACE := 800.0

class ForceOnce:
	var caster_id: int
	var action_id: StringName
	var target_id: int
	var used := false

	func decide(_state: CombatState, unit: CombatUnit) -> Intent:
		if unit.id == caster_id and not used:
			used = true
			return Intent.use_action(action_id, target_id)
		return null

func _say(line: String = "") -> void:
	print(line)

func _init() -> void:
	var failures := 0
	for path in ActionLibrary.PATHS:
		var action: ActionDef = load(path)
		var problems := _check_action(action)
		if problems.is_empty():
			_say("%-24s OK" % String(action.id))
		else:
			failures += 1
			_say("%-24s FAIL" % String(action.id))
			for p in problems:
				_say("    " + p)
	_say("")
	_say("%d / %d actions did what they declared" % [
		ActionLibrary.PATHS.size() - failures, ActionLibrary.PATHS.size(),
	])
	quit(1 if failures > 0 else 0)

## Builds a caster and a dummy, forces the action once, runs it out, and
## returns one string per effect that did not do what it declared. Empty means
## every effect the action lists fired.
func _check_action(action: ActionDef) -> Array[String]:
	var problems: Array[String] = []
	var is_sustain := action.sustain != null
	var self_targeted := not is_sustain and action.targeting != null and action.targeting.targets_self
	var hit := action.hit()
	var restore := action.restore_effect()

	var caster := CombatUnit.new()
	caster.id = 0
	caster.team = CG.Team.PLAYER
	caster.hp_max = 999999
	caster.hp = caster.hp_max
	caster.actions = [action.id]
	## Inside the arena, on the left. (500, 500) was OUTSIDE it: the sim clamps
	## positions into bounds, both units collapsed toward the same corner, and
	## the target ended up BEHIND the caster. Only an arc action noticed, because
	## it is the only kind that asks which way the caster is pointing.
	caster.position = Vector2(-CG.ARENA_HALF_WIDTH + 40.0, 0.0)
	if restore != null:
		## Not at the ceiling and not below the cost, so a gain is visible and
		## paying for the action does not refuse it.
		caster.resource_max = maxi(action.resource_cost, 1) + 1000
		caster.resource = action.resource_cost
	else:
		caster.resource_max = 999999
		caster.resource = 999999

	var target := CombatUnit.new()
	target.id = 1
	target.hp_max = 999999
	target.hp = target.hp_max
	target.resource_max = 999999
	target.resource = 999999
	if is_sustain:
		## `_tick_sustain` reads `_sustain_targets`, which never consults
		## `targets_self` or `focus_id` -- only radius and team.
		target.team = caster.team if (hit != null and hit.heals) else _enemy_team(caster.team)
		var d: float = clampf(action.sustain.radius - 1.0, 0.0, _MAX_PLACE)
		target.position = caster.position + Vector2(d, 0.0)
	else:
		target.team = _enemy_team(caster.team)
		var d: float = clampf(action.range_units - 1.0, 0.0, _MAX_PLACE)
		target.position = caster.position + Vector2(d, 0.0)

	## A real caster faces what it swings at, and `_in_arc` hits nobody when
	## facing is ZERO. Without this an arc action reports declaring damage and
	## landing none, which is a fixture that never turned round, not a defect.
	caster.facing = (target.position - caster.position).normalized()

	var hit_target_id := caster.id if self_targeted else target.id
	var status_target_id := caster.id if (self_targeted or action.covers_target) else target.id
	if hit != null and hit.heals:
		var wounded := caster if self_targeted else target
		wounded.hp = int(wounded.hp_max / 2)
	if action.has_cleanse():
		target.statuses[CG.Status.BURN] = 999999
		target.status_magnitude[CG.Status.BURN] = 10.0

	var pull_start := target.position

	var state := CombatState.new(1)
	var units: Array[CombatUnit] = [caster, target]
	state.units = units

	var rig := ForceOnce.new()
	rig.caster_id = caster.id
	rig.action_id = action.id
	rig.target_id = caster.id if self_targeted else target.id

	var deps := SimDeps.new()
	deps.default_decide = Callable(rig, "decide")
	## `SimDeps._default_attack_power` derives its number from `unit.pawn` or
	## `EnemyLibrary.get_enemy(unit.enemy_id)`, both null on a bare dummy, which
	## would silently floor every hit at 0 regardless of what the action
	## declares. Fixed and independent of `Balance.gd`, on purpose: this rig
	## is testing whether an effect fires, not what it is tuned to.
	deps.attack_power = Callable(self, "_attack_power")

	for _t in RUN_TICKS:
		CombatSim.step(state, deps)

	for fx in action.effects:
		if fx is HitEffect:
			problems.append_array(_check_hit(fx, state, caster, hit_target_id, action.covers_target))
		elif fx is StatusEffect:
			problems.append_array(_check_status(fx, state, status_target_id))
		elif fx is RestoreEffect:
			if caster.resource <= 0:
				problems.append("RestoreEffect declared amount %d but the caster's resource never rose" % fx.amount)
		elif fx is SummonEffect:
			if not _has_event(state, CG.EventKind.SUMMONED, caster.id, -1):
				problems.append("SummonEffect declared '%s' but no SUMMONED event fired" % fx.unit_id)
		elif fx is PoolEffect:
			if state.grid.is_empty():
				problems.append("PoolEffect declared radius %.1f but no terrain was added" % fx.radius)
		elif fx is PullEffect:
			if target.position.distance_to(pull_start) < 0.01:
				problems.append("PullEffect declared distance %.1f but the target never moved" % fx.distance)
		elif fx is CleanseEffect:
			if target.statuses.has(CG.Status.BURN):
				problems.append("CleanseEffect declared but the harmful status stayed on the target")
	return problems

func _check_hit(fx: HitEffect, state: CombatState, caster: CombatUnit, target_id: int, covers_target: bool) -> Array[String]:
	## Issue 621's own routing rule: `heals and power_scale > 0.0` is what
	## makes a hit do anything visible. `covers_target` suppresses the event
	## outright by design (issue 593) -- the ally is where the caster looks,
	## not something it hits.
	if covers_target or fx.power_scale <= 0.0:
		return []
	var kind := CG.EventKind.HEAL if fx.heals else CG.EventKind.DAMAGE
	if _has_event(state, kind, caster.id, target_id):
		return []
	var verb := "heal" if fx.heals else "damage"
	return ["HitEffect declared %s (power_scale %.2f) but no %s > 0 landed on the target" % [
		verb, fx.power_scale, kind_name(kind),
	]]

func _check_status(fx: StatusEffect, state: CombatState, target_id: int) -> Array[String]:
	for e in state.events:
		if e.kind == CG.EventKind.STATUS_APPLIED and e.target_id == target_id and e.status == fx.status:
			return []
	return ["StatusEffect declared status %s but it was never applied" % CG.Status.keys()[fx.status]]

## `source_id` or `target_id` of -1 means "any". A DAMAGE or HEAL match must
## also carry amount > 0 -- an event that fired for zero is not a hit landing.
func _has_event(state: CombatState, kind: CG.EventKind, source_id: int, target_id: int) -> bool:
	for e in state.events:
		if e.kind != kind:
			continue
		if source_id != -1 and e.source_id != source_id:
			continue
		if target_id != -1 and e.target_id != target_id:
			continue
		if (kind == CG.EventKind.DAMAGE or kind == CG.EventKind.HEAL) and e.amount <= 0:
			continue
		return true
	return false

func kind_name(kind: CG.EventKind) -> String:
	return CG.EventKind.keys()[kind]

func _enemy_team(team: CG.Team) -> CG.Team:
	return CG.Team.ENEMY if team == CG.Team.PLAYER else CG.Team.PLAYER

func _attack_power(_unit: CombatUnit, action: ActionDef, _rng: RandomNumberGenerator = null) -> float:
	return 100.0 * action.power_scale
