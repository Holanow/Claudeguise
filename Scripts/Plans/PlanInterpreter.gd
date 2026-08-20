extends RefCounted
class_name PlanInterpreter


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
##
## `keep_distance{range: float}` covers every case the issue lists, because all
## of them are a distance the pawn wants to hold relative to its focus:
##
##   "keep 120 units away"  ->  keep_distance{range: 120}   (kite)
##   "close to melee"       ->  keep_distance{range: 0}     (charge)
##
## The player's other suggestion -- *"move 25 units left and 25 units up"* --
## is deliberately not built. An absolute vector does not know where the enemy
## is, so the same block reads as a retreat or as a charge depending on which
## side the enemy happens to be standing, and the arena has no fixed facing to
## reason from. A distance from the target works from every side.
##
## "Hold position" is genuinely not a distance and is genuinely not here.
## Nothing needs it yet; it is a second op when something does.
const MOVEMENT_OPS := [&"keep_distance"]

## How close to the requested distance counts as arrived, in world units.
##
## **This is hysteresis and it is load-bearing, not a tolerance.** Without a
## band, a pawn that overshoots by a single tick's movement is now on the wrong
## side of the threshold and turns around, forever -- which is not a
## hypothetical. Measured on issue 94: a pawn resting where two rules disagreed
## alternated between them on a **two-tick cycle** for 2400 ticks and never
## fired a shot, positions exactly period-2 at ticks 2000/2001/2002.
##
## 15 units, against a fastest pawn move of 6.25 units per tick (the
## Abomination; the other four are 4.70 to 5.45, from `Balance.move_speed` on
## real starter pawns). So the band is wider than two ticks of travel for every
## pawn in the game, and a unit that steps into it stays in it.
const KEEP_DISTANCE_BAND := 15.0

## Issue 22: op -> {kind, key, default, [min, max, step]}, the argument shape
## each CONDITION op reads. `_eval_condition` above is the source of truth for
## which key an op reads out of `block.args` and what it does with it; this is
## that same fact, exposed as data instead of match-statement logic, for a
## screen (InspectPanel) that needs to build a value editor rather than
## evaluate a condition. Moved here from InspectPanel.gd itself, which carried
## its own copy pending this issue â€” see PR history for the "if the whitelist
## grows past its current five entries, it moves" call that opened it. "none"
## carries no value editor. "fraction" is edited as a 0-100 percent by the
## caller and rescaled to the 0.0-1.0 this interpreter actually reads.
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

## push_error is the loud, real failure. This is a testable side channel: the
## test suite has no way to assert a push_error happened, so an unknown op also
## records here, naming the op and the plan, and a test can read and clear it.
## Cleared at the start of every decide()/condition_holds() call.
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
##
## The rule: rows are paid for in priority order, so the surplus is always at the
## bottom. Walk the list adding each row's own `block_count()`, and the first row
## whose running total passes `Balance.plan_block_budget` is where the pawn runs
## out. That row and every row under it is inert. `spent` never decreases, so
## stopping at the first overrun and marking everything after it inert are the
## same thing -- a cheap row below an expensive one does not sneak back in.
##
## Guarding here rather than in the editor is deliberate. The editor already
## refuses to *add* a row past the budget, and that was the whole enforcement:
## the budget can also *shrink* under a plan the player already wrote, by taking
## WIS armour off mid-floor, and `EquipPanel` offers every registered item today.
## So the route is reachable now, not hypothetically.
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
		return _run_movement(state, unit, plan, movement, action_id)
	if action_id == &"" or unit.focus_id == -1:
		return null
	if not _unit_has_action(unit, action_id):
		return null
	if not _target_in_range(state, unit, action_id):
		return null
	if not _target_in_los(state, unit, action_id):
		return null
	if not can_afford(state, unit, action_id):
		return null
	if not _summon_slot_free(state, unit, action_id):
		return null
	if not _target_is_marked(state, unit, action_id):
		return null
	return Intent.use_action(action_id, unit.focus_id, plan.id)

## Issue 97: **the first time the plan layer decides where a pawn stands.**
##
## Everything above this function either fires an action or returns null, and
## null means `DefaultBehavior` decides â€” including all movement. This file's
## own comment on `_target_in_range` said so plainly: *"PlanInterpreter has
## never handled movement, that is DefaultBehavior's whole job."* So where a
## pawn stood was never visible in a plan, which is issue 98's principle, and
## kiting was its loudest symptom: a pawn backing out of a fight the player told
## it to join, with nowhere to go and change it.
##
## **A plan carrying a MOVEMENT block never falls through to
## `DefaultBehavior`.** That is the whole point rather than a detail. A block
## whose effect can be silently overruled by hidden code is not control, and
## building it any other way would recreate issue 98 inside the fix for it.
##
## The one exception, and it is not a fall-through in spirit: **no focus at
## all.** "Keep 120 units away" is relative to something, and with no target
## there is nothing to be 120 units from. That happens only when the plan's
## targeting found no enemy, which means the fight is over, so this returns null
## and lets the ordinary path handle it rather than freezing the pawn at a
## distance from nobody.
static func _run_movement(state: CombatState, unit: CombatUnit, plan: Plan, block: PlanBlock, action_id: StringName) -> Intent:
	var target := state.unit(unit.focus_id)
	if target == null or not target.alive:
		return null

	var wanted := float(block.args.get("range", 0.0))
	var dist := unit.position.distance_to(target.position)
	var away := unit.position - target.position
	if away.length() < 0.0001:
		# Standing exactly on the target. Any direction is "away"; pick one
		away = Vector2(1.0, 0.0)

	if dist < wanted - KEEP_DISTANCE_BAND:
		return Intent.move_to(unit.position + away.normalized() * (wanted - dist), plan.id)
	if dist > wanted + KEEP_DISTANCE_BAND:
		return Intent.move_to(target.position + away.normalized() * wanted, plan.id)

	# Standing where the player asked. Fire if there is an action and it can
	if action_id == &"" or not _action_can_fire(state, unit, action_id):
		return Intent.idle(plan.id)
	return Intent.use_action(action_id, unit.focus_id, plan.id)

## Every gate `_run_blocks` applies to an action, asked as one question.
##
## Extracted rather than duplicated: a movement block has to know whether the
## action would fire in order to decide between firing and holding, and two
## copies of a seven-clause list is how the two paths drift apart.
static func _action_can_fire(state: CombatState, unit: CombatUnit, action_id: StringName) -> bool:
	return _unit_has_action(unit, action_id) \
		and _target_in_range(state, unit, action_id) \
		and _target_in_los(state, unit, action_id) \
		and can_afford(state, unit, action_id) \
		and _summon_slot_free(state, unit, action_id) \
		and _target_is_marked(state, unit, action_id)

## Issue 100: a plan may only fire an action the unit actually has.
##
## **Nothing anywhere checked this before, and it is what made `granted_actions`
## meaningless.** `PlanInterpreter` resolved an action straight out of `Registry`
## and `CombatSim._resolve_use_action` did the same, so any plan could fire any
## action in the game regardless of whether the pawn owned it. A Warrior with no
## Plate Mail and a Warrior wearing one would both have cast Directional Block,
## which makes equipping the item worth nothing and makes the whole equipment
## feature impossible to test: there is no observable difference between granted
## and not granted.
##
## It is also the reverse of issue 98's principle -- *"pawns should never do
## anything the player cannot see in the plans of action"* -- because a pawn
## firing an ability it does not own is the same class of surprise seen from the
## other side.
##
## `unit.actions` is the right list to read: `CombatSim._collect_player_actions`
## builds it as the class's `starting_actions` plus every equipped piece's
## `granted_actions`, so it is already the exact union of "everything this pawn
## can do", equipment included, and it is what the plan editor should show.
##
## An empty `actions` list means "not a real unit yet", which several tests build
## deliberately, so it is allowed through rather than treated as owning nothing.
## Narrowing that is a change to fixtures other sessions own, and this gate is
## about equipment rather than about test hygiene.
static func _unit_has_action(unit: CombatUnit, action_id: StringName) -> bool:
	if unit.actions.is_empty():
		return true
	return unit.actions.has(action_id)

## Issue 14a: a plan must not order a shot it already knows will miss. The
## focused target's distance is checked against the action's own range here,
## once, right before the intent is built â€” the one place both numbers are
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
## **Public since issue 214, on `DefaultBehavior.default_attack_action`'s
## precedent: one definition, two callers.** `DefaultBehavior` needs exactly this
## question and did not ask it, which is how `stalker_dart` reached the trunk
## having never fired once -- `stalker_mark` was chosen on all 60 ticks of its own
## cooldown and `CombatSim` spent the tick refusing it. A second copy of a
## four-line gate is how the plan path and the fallback path drift into
## disagreeing about what a unit can do.
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
## directly above -- a plan whose action cannot do anything right now must fall
## through to the next plan instead of committing the unit to a wasted tick.
##
## Where this runs is the whole design, not an implementation detail. Refusing
## inside `CombatSim._spawn_summon` would let a Siege Master pay 20 Mana and
## stand through a 90-tick wind-up to produce nothing, on every tick it is
## capped -- which would make `spotter_mark` rarer, and the engines now depend
## entirely on `spotter_mark`. Falling through here is what turns "capped" into
## "mark something instead", and it is why the cap and the marked-only gate are
## one change rather than two.
##
## Counts live summons by `EnemyDef` id on the caster's own team, not by who
## cast what: a second Siege Master's engines occupy the same field the first one
## is looking at, and two players' worth of engines is exactly what the cap
## exists to prevent. `max_active_summons` 0 means uncapped, which is every
## action but one, so this returns true immediately for all of them.
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
##
## Checked against the *focused* target rather than "is anything marked
## anywhere". A plan that chose its own target must not get to fire at that
## target on the strength of some other enemy being marked somewhere else.
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
		## Issue 206: the mirror of the op above, and it exists because a Rage
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
## screen. Display only â€” never called from decide()/condition_holds(), so a
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
## Issue 181: the nearest living enemy carrying `status`, or null.
##
## **Backs BOTH `enemy_has_status` and `target_enemy_with_status`, from one
## function, for the reason `_nearest_afflicted_ally` records below and paid for
## on #87: if the condition can hold on a unit the targeting op then declines,
## `_run_blocks` leaves `focus_id` at whatever the previous tick set** -- which
## for this class is another enemy from `geyser_blast_cluster` -- **and the plan
## fires at the wrong target.** Two similar functions are how that comes back.
##
## Nearest wins, ties by iteration order over `state.living`, which is fixed for
## a seed. No rng.
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
##
## **Capitalised as a noun, and the first version was lowercase because I wrote
## the sentence without reading it on the screen.** The plan editor rendered *"An
## enemy is not poison"*, which is not English. Read as a noun -- "an enemy has
## no Poison", "the nearest enemy without Poison" -- it needs no adjective table
## and it matches what the badge and the glossary call the same thing.
##
## `CG.Status.keys()` is the same source `CombatLogView._status_name` uses, so
## the plan editor and the combat log cannot call one status two different
## things.
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
