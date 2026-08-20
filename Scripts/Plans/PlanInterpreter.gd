extends RefCounted
class_name PlanInterpreter


## Turns a pawn's plans into one Intent per tick.

## Whitelists, one per PlanBlock.Kind. An op not listed here is unknown and
## fails loudly rather than being silently skipped, per the issue: a skipped
## block reads to a player as the plan simply not working.
const CONDITION_OPS := [
	&"always",
	&"self_hp_below_fraction",
	&"ally_below_hp_fraction",
	&"self_resource_at_least",
	&"self_resource_below",
	&"enemy_in_range",
	&"ally_has_harmful_status",
	&"enemy_has_status",
	&"enemy_lacks_status",
]
const TARGETING_OPS := [
	&"target_nearest_enemy",
	&"target_lowest_hp_fraction_ally",
	&"target_lowest_hp_fraction_enemy",
	&"target_self",
	&"target_ally_with_harmful_status",
	&"target_enemy_with_status",
	&"target_enemy_without_status",
]
const ACTION_OPS := [&"use_action"]
const DURATION_OPS := [&"once"]

## Issue 97. One op, not three.
const MOVEMENT_OPS := [&"keep_distance", &"move_into_cover"]

## Issue 316: how far behind a piece of cover a pawn stands, in world units.
const COVER_STANDOFF := 20.0

## How close to the requested distance counts as arrived, in world units.
const KEEP_DISTANCE_BAND := 15.0

## Issue 22: op -> {kind, key, default, [min, max, step]}, the argument shape
## each CONDITION op reads. `_eval_condition` above is the source of truth for
## which key an op reads out of `block.args` and what it does with it; this is
## that same fact, exposed as data instead of match-statement logic, for a
## screen (InspectPanel) that needs to build a value editor rather than
## evaluate a condition. Moved here from InspectPanel.gd itself, which carried
## its own copy pending this issue -- see PR history for the "if the whitelist
## grows past its current five entries, it moves" call that opened it. "none"
const CONDITION_ARG_SHAPE := {
	&"always": {"kind": "none"},
	&"self_hp_below_fraction": {"kind": "fraction", "key": "fraction", "default": 0.5},
	&"ally_below_hp_fraction": {"kind": "fraction", "key": "fraction", "default": 0.5},
	&"self_resource_at_least": {"kind": "amount", "key": "amount", "min": 0, "max": 999, "step": 1, "default": 0},
	&"self_resource_below": {"kind": "amount", "key": "amount", "min": 0, "max": 999, "step": 1, "default": 0},
	## **`step` 5, not 10, and a rendered screen is what found it.** A `SpinBox`
	&"enemy_in_range": {"kind": "range", "key": "range", "min": 0, "max": 1000, "step": 5, "default": 100.0},
	&"ally_has_harmful_status": {"kind": "none"},
	&"enemy_has_status": {"kind": "status", "key": "status", "default": 0},
	&"enemy_lacks_status": {"kind": "status", "key": "status", "default": 0},
}

## Issue 97: the same shape `CONDITION_ARG_SHAPE` carries, for the MOVEMENT ops,
## so the plan editor can build a value editor for the distance a block holds.
const MOVEMENT_ARG_SHAPE := {
	&"keep_distance": {"kind": "range", "key": "range", "min": 0, "max": 1000, "step": 5, "default": 120.0},
	&"move_into_cover": {"kind": "none"},
}

## push_error is the loud, real failure. This is a testable side channel: the
## test suite has no way to assert a push_error happened, so an unknown op also
## records here, naming the op and the plan, and a test can read and clear it.
static var last_error: String = ""

## Issue 269: how many of a pawn's plans it can actually pay for, and **the one
## place that question is answered.**
##
## `InspectPanel` dims every row from index `active_plan_count(pawn)` down and
## writes "Inert" on it; `decide()` below stops iterating at the same index. Two
## implementations of this rule would drift, and the drift is precisely the
## defect it was written to fix: a row the screen calls inert that the pawn fires
## anyway, which is the pawn-behaviour principle inverted -- the player can see
## the mark and the pawn ignores it.
static func active_plan_count(pawn: PawnData) -> int:
	if pawn == null:
		return 0
	var budget := Balance.plan_block_budget(pawn)
	var spent := 0
	var count := 0
	for plan in pawn.plans:
		spent += plan.block_count()
		if spent > budget:
			break
		count += 1
	return count

static func decide(state: CombatState, unit: CombatUnit) -> Intent:
	last_error = ""
	if unit.pawn == null:
		return null
	var active := active_plan_count(unit.pawn)
	for i in active:
		var plan: Plan = unit.pawn.plans[i]
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
	var movement: PlanBlock = null
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
			PlanBlock.Kind.MOVEMENT:
				if not MOVEMENT_OPS.has(block.op):
					_fail(plan, block)
					return null
				movement = block
	if movement != null:
		if movement.op == &"move_into_cover":
			return _run_into_cover(state, unit, plan, action_id)
		return _run_movement(state, unit, plan, movement, action_id)
	if action_id == &"" or unit.focus_id == -1:
		return null
	if not _action_can_fire(state, unit, action_id):
		return null
	return Intent.use_action(action_id, action_target_id(unit, action_id), plan.id)

## Issue 97: **the first time the plan layer decides where a pawn stands.**
##
## Everything above this function either fires an action or returns null, and
## null means `DefaultBehavior` decides -- including all movement. This file's
## own comment on `_target_in_range` said so plainly: *"PlanInterpreter has
## never handled movement, that is DefaultBehavior's whole job."* So where a
## pawn stood was never visible in a plan, which is issue 98's principle, and
## kiting was its loudest symptom: a pawn backing out of a fight the player told
## it to join, with nowhere to go and change it.
static func _run_movement(state: CombatState, unit: CombatUnit, plan: Plan, block: PlanBlock, action_id: StringName) -> Intent:
	var target := state.unit(unit.focus_id)
	if target == null or not target.alive:
		return null

	var wanted := float(block.args.get("range", 0.0))
	var dist := unit.position.distance_to(target.position)
	var away := unit.position - target.position
	if away.length() < 0.0001:
		away = Vector2(1.0, 0.0)

	if dist < wanted - KEEP_DISTANCE_BAND:
		return Intent.move_to(unit.position + away.normalized() * (wanted - dist), plan.id)
	if dist > wanted + KEEP_DISTANCE_BAND:
		return Intent.move_to(target.position + away.normalized() * wanted, plan.id)

	if action_id == &"" or not _action_can_fire(state, unit, action_id):
		return Intent.idle(plan.id)
	return Intent.use_action(action_id, action_target_id(unit, action_id), plan.id)

## Issue 97: who the action is aimed at, which is not always who the plan is
## focused on -- a self-targeted action is cast on the caster whatever the
## targeting block picked, so a MOVEMENT block can measure its distance from an
## enemy while the buff inside it still lands on the pawn.
static func action_target_id(unit: CombatUnit, action_id: StringName) -> int:
	var action = Registry.get_action(action_id)
	return unit.id if action != null and action.targets_self else unit.focus_id

## Issue 316: put something solid between this pawn and the enemy the plan is
## aimed at, then act from there.
##
## Cover from the FOCUS, not from everyone: the targeting block above already
## decided which enemy matters, so the player picks it in the same row they can
## see. Being in cover from every archer at once is usually not a position that
## exists.
static func _run_into_cover(state: CombatState, unit: CombatUnit, plan: Plan, action_id: StringName) -> Intent:
	var threat := state.unit(unit.focus_id)
	if threat == null or not threat.alive:
		return null
	## Cover from the target is also cover from your own shot: this game's cover
	## is binary line of sight, with no peeking out. Measured before it was
	## written -- "take cover, then Scald" held 54.6% cover and 10/20 wins
	## against 20/20, because the pawn stood behind a pillar it could not shoot
	## past until the tick limit. The pairing has no satisfying position, so the
	## row steps aside for the next one rather than idling out the fight.
	if _action_needs_line_of_sight(action_id):
		return null
	if in_cover_from(state, unit, unit.position, threat):
		if action_id == &"" or not _action_can_fire(state, unit, action_id):
			return Intent.idle(plan.id)
		return Intent.use_action(action_id, action_target_id(unit, action_id), plan.id)
	var spot = _cover_spot(state, unit, threat)
	if spot == null:
		return null
	return Intent.move_to(spot, plan.id)

## True when the action can only be used with a clear line to its target.
static func _action_needs_line_of_sight(action_id: StringName) -> bool:
	if action_id == &"":
		return false
	var action = Registry.get_action(action_id)
	return action != null and action.requires_line_of_sight

## Whether a shot from `threat` at `pos` would be stopped by terrain or by an
## ally's raised shield. The shield half is `CombatSim`'s own interception test,
## called rather than copied, so the plan layer and the projectile cannot
## disagree about what counts as cover.
static func in_cover_from(state: CombatState, unit: CombatUnit, pos: Vector2, threat: CombatUnit) -> bool:
	if Terrain.line_is_blocked(state.terrain, threat.position, pos):
		return true
	return CombatSim.shot_would_be_shielded(state, unit.team, threat.team, threat.position, pos)

## The nearest standing spot that is in cover from `threat`, or null when the
## room offers none. Deterministic: fixed iteration order and a strict
## improvement test, so ties go to the earlier candidate rather than the rng.
static func _cover_spot(state: CombatState, unit: CombatUnit, threat: CombatUnit):
	var best = null
	var best_dist := INF
	for f in state.terrain:
		if not f.blocks_sight():
			continue
		var centre: Vector2 = f.rect.get_center()
		var away := centre - threat.position
		if away.length() < 0.0001:
			continue
		var extent := 0.5 * maxf(f.rect.size.x, f.rect.size.y)
		var spot := centre + away.normalized() * (extent + COVER_STANDOFF)
		var d := unit.position.distance_to(spot)
		if d >= best_dist:
			continue
		if Terrain.point_is_blocked(state.terrain, spot, unit.radius):
			continue
		if not Terrain.line_is_blocked(state.terrain, threat.position, spot):
			continue
		best_dist = d
		best = spot
	for ally in state.living(unit.team):
		if ally.id == unit.id or not ally.has_status(CG.Status.SHIELDING):
			continue
		var away2 := ally.position - threat.position
		if away2.length() < 0.0001:
			continue
		var spot2 := ally.position + away2.normalized() * COVER_STANDOFF
		var d2 := unit.position.distance_to(spot2)
		if d2 >= best_dist:
			continue
		if Terrain.point_is_blocked(state.terrain, spot2, unit.radius):
			continue
		if not CombatSim.shot_would_be_shielded(state, unit.team, threat.team, threat.position, spot2):
			continue
		best_dist = d2
		best = spot2
	return best

## Every gate `_run_blocks` applies to an action, asked as one question.
static func _action_can_fire(state: CombatState, unit: CombatUnit, action_id: StringName) -> bool:
	return _unit_has_action(unit, action_id) \
		and _target_in_range(state, unit, action_id) \
		and _target_in_los(state, unit, action_id) \
		and can_afford(state, unit, action_id) \
		and _summon_slot_free(state, unit, action_id) \
		and _target_is_marked(state, unit, action_id)

## Issue 100: a plan may only fire an action the unit actually has.
static func _unit_has_action(unit: CombatUnit, action_id: StringName) -> bool:
	if unit.actions.is_empty():
		return true
	return unit.actions.has(action_id)

## Issue 14a: a plan must not order a shot it already knows will miss. The
## focused target's distance is checked against the action's own range here,
## once, right before the intent is built -- the one place both numbers are
## available together, regardless of which targeting op or condition (if any)
## picked the target. Out of range falls through (returns null from decide(),
## via _run_blocks) rather than trying to move into range itself:
static func _target_in_range(state: CombatState, unit: CombatUnit, action_id: StringName) -> bool:
	var action = Registry.get_action(action_id)
	if action == null:
		return true
	var target := state.unit(action_target_id(unit, action_id))
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
	var target := state.unit(action_target_id(unit, action_id))
	if target == null:
		return false
	return not Terrain.line_is_blocked(state.terrain, unit.position, target.position)

## Issue 22: same shape as 14a's range check, same reasoning. A plan whose
## action the unit cannot actually pay for right now -- not enough resource,
## or still on cooldown -- must not commit CombatSim to refusing it and
## burning the tick. Falls through to the next plan (or DefaultBehavior)
## exactly like an out-of-range shot does, rather than special-casing Rage or
## rewriting the plan's own condition to route around the gap.
static func can_afford(state: CombatState, unit: CombatUnit, action_id: StringName) -> bool:
	var action = Registry.get_action(action_id)
	if action == null:
		return true
	if unit.resource < action.resource_cost:
		return false
	if unit.cooldowns.has(action.id) and state.tick < int(unit.cooldowns[action.id]):
		return false
	return true

## Issue 93: the summon cap, and it is a gate on *choosing* the action rather
## than a refusal at spawn time. Same shape and same reasoning as `can_afford`
static func _summon_slot_free(state: CombatState, unit: CombatUnit, action_id: StringName) -> bool:
	var action = Registry.get_action(action_id)
	if action == null or action.max_active_summons <= 0 or action.summons_unit_id == &"":
		return true
	var live := 0
	for u in state.living(unit.team):
		if u.enemy_id == action.summons_unit_id:
			live += 1
	return live < action.max_active_summons

## Issue 93: an action that may only be aimed at an enemy carrying MARKED. Same
## fall-through shape as the range and line-of-sight checks above: a plan aiming
## an engine at an unmarked target steps aside rather than ordering a shot the
## engine is not allowed to take.
static func _target_is_marked(state: CombatState, unit: CombatUnit, action_id: StringName) -> bool:
	var action = Registry.get_action(action_id)
	if action == null or not action.requires_marked_target:
		return true
	var target := state.unit(unit.focus_id)
	return target != null and target.has_status(CG.Status.MARKED)

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
		&"self_resource_below":
			return unit.resource < int(block.args.get("amount", 0))
		&"enemy_in_range":
			var range_units := float(block.args.get("range", 0.0))
			var nearest := _nearest(state, unit, _enemy_team(unit.team))
			if nearest == null:
				return false
			return unit.position.distance_to(nearest.position) <= range_units
		&"ally_has_harmful_status":
			return _nearest_afflicted_ally(state, unit) != null
		&"enemy_has_status":
			return _nearest_enemy_with_status(state, unit, _status_arg(block)) != null
		&"enemy_lacks_status":
			return _nearest_enemy_without_status(state, unit, _status_arg(block)) != null
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
		&"target_enemy_with_status":
			var marked := _nearest_enemy_with_status(state, unit, _status_arg(block))
			return marked.id if marked != null else -1
		&"target_enemy_without_status":
			var clean := _nearest_enemy_without_status(state, unit, _status_arg(block))
			return clean.id if clean != null else -1
	return -1

## Issue 21a: a human-readable fragment for one block, for the pawn-inspect
## screen. Display only -- never called from decide()/condition_holds(), so a
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
		&"self_resource_below":
			return "self resource below %d" % int(args.get("amount", 0))
		&"enemy_in_range":
			return "an enemy within %d units" % int(args.get("range", 0.0))
		&"ally_has_harmful_status":
			return "an ally has a harmful status"
		&"enemy_has_status":
			return "an enemy has %s" % _status_word(int(args.get("status", 0)))
		&"enemy_lacks_status":
			return "an enemy has no %s" % _status_word(int(args.get("status", 0)))
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
		&"target_enemy_with_status":
			return "the nearest enemy with %s" % _status_word(int(args.get("status", 0)))
		&"target_enemy_without_status":
			return "the nearest enemy without %s" % _status_word(int(args.get("status", 0)))
		&"use_action":
			var action_id: StringName = args.get("action_id", &"")
			var action := Registry.get_action(action_id)
			return "use %s" % (action.display_name if action != null else String(action_id))
		&"once":
			return "once"
		&"keep_distance":
			var wanted := int(args.get("range", 0.0))
			return "close to the target" if wanted <= 0 else "hold %d units from the target" % wanted
		&"move_into_cover":
			return "move into cover from the target"
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

## The nearest living ally carrying any status `CG.is_harmful` classifies as
## harmful, or null. `unit` counts as an ally at distance 0, so a poisoned
## caster scrubs itself first.
static func _nearest_enemy_with_status(state: CombatState, unit: CombatUnit, status: CG.Status) -> CombatUnit:
	var best: CombatUnit = null
	var best_dist := INF
	for foe in state.living(_enemy_team(unit.team)):
		if not foe.has_status(status):
			continue
		var d := unit.position.distance_to(foe.position)
		if d < best_dist:
			best_dist = d
			best = foe
	return best

## Issue 206: the complement of `_nearest_enemy_with_status`, and the same
## condition/targeting pair discipline -- one function so the two ops cannot
## disagree about which enemy qualifies.
static func _nearest_enemy_without_status(state: CombatState, unit: CombatUnit, status: CG.Status) -> CombatUnit:
	var best: CombatUnit = null
	var best_dist := INF
	for foe in state.living(_enemy_team(unit.team)):
		if foe.has_status(status):
			continue
		var d := unit.position.distance_to(foe.position)
		if d < best_dist:
			best_dist = d
			best = foe
	return best

## The status a block names. Defaults to `CG.Status.SHIELD` (0) rather than
## erroring, matching how every other arg here reads a missing key -- and a plan
## asking about SHIELD on an enemy simply never holds, which is a visible no-op
## rather than a crash.
static func _status_arg(block: PlanBlock) -> CG.Status:
	return int(block.args.get("status", 0)) as CG.Status

## Player-facing name for a status, for the plan sentences.
static func _status_word(status: int) -> String:
	return String(CG.Status.keys()[status]).capitalize()

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
