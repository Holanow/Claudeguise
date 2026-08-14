extends RefCounted

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")
const Intent := preload("res://Scripts/Core/Intent.gd")
const Plan := preload("res://Scripts/Core/Plan.gd")
const PlanBlock := preload("res://Scripts/Core/PlanBlock.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const Terrain := preload("res://Scripts/Core/Terrain.gd")

## Turns a pawn's plans into one Intent per tick.
##
## OWNER: teal. Files under Scripts/Plans/ and Scripts/Content/ are teal's.
##
## Called by CombatSim once per unit per tick, before anything resolves. It may
## read the state and it may write `unit.focus_id`. It may not write anything
## else on a unit: every other change goes through the Intent it returns.
##
## Per README.md, when several plans would fire on the same tick exactly one
## does, and it is the earliest one in `pawn.plans`. A unit with no plan that
## fires falls through to DefaultBehavior.
##
## A plan runs its blocks once, in order, entirely within one call to decide():
## a targeting block moves focus and an action block fires immediately after,
## so "focus nearest enemy, then attack" never re-targets between the two.
## There is no persistent per-plan progress stored anywhere (CombatUnit carries
## none), so a DURATION block is a structural marker only; the actual "how long
## does this repeat" is already governed by the fired action's own wind-up and
## recovery, since decide() is not called again until the unit is free.

## Whitelists, one per PlanBlock.Kind. An op not listed here is unknown and
## fails loudly rather than being silently skipped, per the issue: a skipped
## block reads to a player as the plan simply not working.
const CONDITION_OPS := [
	&"always",
	&"self_hp_below_fraction",
	&"ally_below_hp_fraction",
	&"self_resource_at_least",
	&"enemy_in_range",
	&"ally_has_harmful_status",
]
const TARGETING_OPS := [
	&"target_nearest_enemy",
	&"target_lowest_hp_fraction_ally",
	&"target_lowest_hp_fraction_enemy",
	&"target_self",
	&"target_ally_with_harmful_status",
]
const ACTION_OPS := [&"use_action"]
const DURATION_OPS := [&"once"]

## Issue 22: op -> {kind, key, default, [min, max, step]}, the argument shape
## each CONDITION op reads. `_eval_condition` above is the source of truth for
## which key an op reads out of `block.args` and what it does with it; this is
## that same fact, exposed as data instead of match-statement logic, for a
## screen (InspectPanel) that needs to build a value editor rather than
## evaluate a condition. Moved here from InspectPanel.gd itself, which carried
## its own copy pending this issue — see PR history for the "if the whitelist
## grows past its current five entries, it moves" call that opened it. "none"
## carries no value editor. "fraction" is edited as a 0-100 percent by the
## caller and rescaled to the 0.0-1.0 this interpreter actually reads.
const CONDITION_ARG_SHAPE := {
	&"always": {"kind": "none"},
	&"self_hp_below_fraction": {"kind": "fraction", "key": "fraction", "default": 0.5},
	&"ally_below_hp_fraction": {"kind": "fraction", "key": "fraction", "default": 0.5},
	&"self_resource_at_least": {"kind": "amount", "key": "amount", "min": 0, "max": 999, "step": 1, "default": 0},
	&"enemy_in_range": {"kind": "range", "key": "range", "min": 0, "max": 1000, "step": 10, "default": 100.0},
	&"ally_has_harmful_status": {"kind": "none"},
}

## push_error is the loud, real failure. This is a testable side channel: the
## test suite has no way to assert a push_error happened, so an unknown op also
## records here, naming the op and the plan, and a test can read and clear it.
## Cleared at the start of every decide()/condition_holds() call.
static var last_error: String = ""

static func decide(state: CombatState, unit: CombatUnit) -> Intent:
	last_error = ""
	if unit.pawn == null:
		return null
	for plan in unit.pawn.plans:
		if not condition_holds(state, unit, plan):
			continue
		var intent := _run_blocks(state, unit, plan)
		if intent != null:
			return intent
	return null

## True when the plan's condition holds for this unit right now. Split out
## because the battle view greys out plans that cannot fire, and because it is
## the piece worth testing on its own.
static func condition_holds(state: CombatState, unit: CombatUnit, plan: Plan) -> bool:
	if plan.condition == null:
		return true
	return _eval_condition(state, unit, plan, plan.condition)

# ---------------------------------------------------------------------------

static func _run_blocks(state: CombatState, unit: CombatUnit, plan: Plan) -> Intent:
	var action_id: StringName = &""
	for block in plan.blocks:
		match block.kind:
			PlanBlock.Kind.TARGETING:
				var target_id := _eval_targeting(state, unit, plan, block)
				if target_id != -1:
					unit.focus_id = target_id
			PlanBlock.Kind.ACTION:
				if not ACTION_OPS.has(block.op):
					_fail(plan, block)
					return null
				action_id = block.args.get("action_id", &"")
			PlanBlock.Kind.DURATION:
				if not DURATION_OPS.has(block.op):
					_fail(plan, block)
					return null
			PlanBlock.Kind.CONDITION:
				if not CONDITION_OPS.has(block.op):
					_fail(plan, block)
					return null
	if action_id == &"" or unit.focus_id == -1:
		return null
	if not _target_in_range(state, unit, action_id):
		return null
	if not _target_in_los(state, unit, action_id):
		return null
	if not _can_afford(state, unit, action_id):
		return null
	return Intent.use_action(action_id, unit.focus_id, plan.id)

## Issue 14a: a plan must not order a shot it already knows will miss. The
## focused target's distance is checked against the action's own range here,
## once, right before the intent is built — the one place both numbers are
## available together, regardless of which targeting op or condition (if any)
## picked the target. Out of range falls through (returns null from decide(),
## via _run_blocks) rather than trying to move into range itself:
## PlanInterpreter has never handled movement, that is DefaultBehavior's whole
## job, and a unit with no plan that fires already falls through to it. So an
## over-eager plan just steps aside for a tick instead of ordering a shot at
## nothing, and DefaultBehavior closes the distance the same way it always has.
static func _target_in_range(state: CombatState, unit: CombatUnit, action_id: StringName) -> bool:
	var action = Registry.get_action(action_id)
	if action == null:
		return true
	var target := state.unit(unit.focus_id)
	if target == null:
		return false
	return unit.position.distance_to(target.position) <= action.range_units

## Issue 34: not a duplicate of `ActionDef.requires_line_of_sight`'s resolve-time
## check -- the two answer different questions. This one asks "should I even aim
## at this?" *before* committing, so a unit with a blocked but in-range target
## has a reason to walk instead of freezing on a shot it can already see is
## hopeless. The resolve-time check still runs later on whatever this lets
## through, and still catches a target that steps behind cover mid-wind-up
## (issue 28's own case) -- restoring this does not touch that. Only actions
## that opted into `requires_line_of_sight` are gated; an unflagged action was
## never blocked by a wall and still is not.
static func _target_in_los(state: CombatState, unit: CombatUnit, action_id: StringName) -> bool:
	var action = Registry.get_action(action_id)
	if action == null or not action.requires_line_of_sight:
		return true
	var target := state.unit(unit.focus_id)
	if target == null:
		return false
	return not Terrain.line_is_blocked(state.terrain, unit.position, target.position)

## Issue 22: same shape as 14a's range check, same reasoning. A plan whose
## action the unit cannot actually pay for right now -- not enough resource,
## or still on cooldown -- must not commit CombatSim to refusing it and
## burning the tick. Falls through to the next plan (or DefaultBehavior)
## exactly like an out-of-range shot does, rather than special-casing Rage or
## rewriting the plan's own condition to route around the gap.
static func _can_afford(state: CombatState, unit: CombatUnit, action_id: StringName) -> bool:
	var action = Registry.get_action(action_id)
	if action == null:
		return true
	if unit.resource < action.resource_cost:
		return false
	if unit.cooldowns.has(action.id) and state.tick < int(unit.cooldowns[action.id]):
		return false
	return true

static func _eval_condition(state: CombatState, unit: CombatUnit, plan: Plan, block: PlanBlock) -> bool:
	if not CONDITION_OPS.has(block.op):
		_fail(plan, block)
		return false
	match block.op:
		&"always":
			return true
		&"self_hp_below_fraction":
			return unit.hp_fraction() < float(block.args.get("fraction", 1.0))
		&"ally_below_hp_fraction":
			var fraction := float(block.args.get("fraction", 1.0))
			for ally in state.living(unit.team):
				if ally.hp_fraction() < fraction:
					return true
			return false
		&"self_resource_at_least":
			return unit.resource >= int(block.args.get("amount", 0))
		&"enemy_in_range":
			var range_units := float(block.args.get("range", 0.0))
			var nearest := _nearest(state, unit, _enemy_team(unit.team))
			if nearest == null:
				return false
			return unit.position.distance_to(nearest.position) <= range_units
		&"ally_has_harmful_status":
			return _nearest_afflicted_ally(state, unit) != null
	return false

static func _eval_targeting(state: CombatState, unit: CombatUnit, plan: Plan, block: PlanBlock) -> int:
	if not TARGETING_OPS.has(block.op):
		_fail(plan, block)
		return -1
	match block.op:
		&"target_nearest_enemy":
			var n := _nearest(state, unit, _enemy_team(unit.team))
			return n.id if n != null else -1
		&"target_lowest_hp_fraction_ally":
			var a := _lowest_hp_fraction(state.living(unit.team))
			return a.id if a != null else -1
		&"target_lowest_hp_fraction_enemy":
			var e := _lowest_hp_fraction(state.living(_enemy_team(unit.team)))
			return e.id if e != null else -1
		&"target_self":
			return unit.id
		&"target_ally_with_harmful_status":
			var afflicted := _nearest_afflicted_ally(state, unit)
			return afflicted.id if afflicted != null else -1
	return -1

## Issue 21a: a human-readable fragment for one block, for the pawn-inspect
## screen. Display only — never called from decide()/condition_holds(), so a
## bad string here cannot affect a fight. An unknown op still names itself
## rather than going blank, since a player reading "??? " and a player reading
## "unknown op 'x'" are getting different amounts of information from the same
## bug.
static func describe_op(op: StringName, args: Dictionary) -> String:
	match op:
		&"always":
			return "always"
		&"self_hp_below_fraction":
			return "self hp below %d%%" % int(round(float(args.get("fraction", 1.0)) * 100.0))
		&"ally_below_hp_fraction":
			return "an ally's hp below %d%%" % int(round(float(args.get("fraction", 1.0)) * 100.0))
		&"self_resource_at_least":
			return "self resource at least %d" % int(args.get("amount", 0))
		&"enemy_in_range":
			return "an enemy within %d units" % int(args.get("range", 0.0))
		&"ally_has_harmful_status":
			return "an ally has a harmful status"
		&"target_nearest_enemy":
			return "the nearest enemy"
		&"target_lowest_hp_fraction_ally":
			return "the ally with the lowest hp"
		&"target_lowest_hp_fraction_enemy":
			return "the enemy with the lowest hp"
		&"target_self":
			return "self"
		&"target_ally_with_harmful_status":
			return "the nearest ally with a harmful status"
		&"use_action":
			var action_id: StringName = args.get("action_id", &"")
			var action := Registry.get_action(action_id)
			return "use %s" % (action.display_name if action != null else String(action_id))
		&"once":
			return "once"
	return "unknown op '%s'" % op

static func _fail(plan: Plan, block: PlanBlock) -> void:
	last_error = "unknown block op '%s' in plan '%s'" % [block.op, plan.id]
	push_error("PlanInterpreter: %s" % last_error)

static func _enemy_team(team: CG.Team) -> CG.Team:
	return CG.Team.ENEMY if team == CG.Team.PLAYER else CG.Team.PLAYER

static func _nearest(state: CombatState, unit: CombatUnit, team: CG.Team) -> CombatUnit:
	var best: CombatUnit = null
	var best_dist := INF
	for candidate in state.living(team):
		var d := unit.position.distance_to(candidate.position)
		if d < best_dist:
			best_dist = d
			best = candidate
	return best

## Issue 87: the nearest living ally carrying any status `CG.is_harmful`
## classifies as harmful, or null when nobody does. `unit` itself counts as an
## ally at distance 0, so a poisoned caster scrubs its own affliction first --
## a cleanse that cannot answer the one status the caster is standing in would
## be a strange ability, and `state.living(unit.team)` already includes it.
##
## Backs BOTH the `ally_has_harmful_status` condition and the
## `target_ally_with_harmful_status` targeting op, deliberately from one
## function rather than two similar ones: the two must agree exactly. If the
## condition could hold on an ally the targeting op then declines to pick,
## `_eval_targeting` returns -1, `_run_blocks` leaves `unit.focus_id` at
## whatever the previous tick left there -- which for this class is an *enemy*,
## from `geyser_blast_cluster`'s own targeting block -- and the plan would fire
## an ally-shaped action at an enemy. That is not hypothetical: it is the exact
## shape swift warned about in their #87 signature note, arriving through
## targeting rather than through `heals`.
##
## `CG.is_harmful` is the only thing consulted for what counts, the same single
## source `CombatSim._cleanse_harmful` and the status badges already use, so a
## plan that fires and a cleanse that strips cannot disagree about what a
## harmful status is.
##
## Nearest wins, ties broken by iteration order over `state.living`, which is
## `state.units` order and therefore fixed for a seed. No rng.
static func _nearest_afflicted_ally(state: CombatState, unit: CombatUnit) -> CombatUnit:
	var best: CombatUnit = null
	var best_dist := INF
	for ally in state.living(unit.team):
		if not _has_harmful_status(ally):
			continue
		var d := unit.position.distance_to(ally.position)
		if d < best_dist:
			best_dist = d
			best = ally
	return best

static func _has_harmful_status(u: CombatUnit) -> bool:
	for s in u.statuses.keys():
		if CG.is_harmful(s):
			return true
	return false

static func _lowest_hp_fraction(units: Array[CombatUnit]) -> CombatUnit:
	var best: CombatUnit = null
	var best_fraction := INF
	for u in units:
		var f := u.hp_fraction()
		if f < best_fraction:
			best_fraction = f
			best = u
	return best
