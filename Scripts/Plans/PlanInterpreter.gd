extends RefCounted
class_name PlanInterpreter


## Turns a pawn's plans into one Intent per tick.
##
## Issue 640: the op vocabulary is not here any more. One `Resource` subclass
## per op under `Scripts/Plans/Blocks/` carries its own arguments and its own
## evaluator, `BlockCatalog` maps a name to a script, and an invalid block is
## unrepresentable rather than caught by a whitelist.

## Issue 316: how far behind a piece of cover a pawn stands, in world units.
const COVER_STANDOFF := 20.0

## Issue 420: how far a pawn will look for ground that does not hurt it. 240 is
## wider than the widest authored hazard band (200, the Burn Pit), so a pawn
## standing in the middle of one can always see out of it.
const SAFE_GROUND_REACH := 240.0

## The radius and angle granularity of that search, in world units and in
## directions around the pawn.
const SAFE_GROUND_STEP := 20.0
const SAFE_GROUND_DIRECTIONS := 16

## How close to the requested distance counts as arrived, in world units.
const KEEP_DISTANCE_BAND := 15.0

## Issue 269: how many of a pawn's plans it can actually pay for, and **the one
## place that question is answered.**
##
## `InspectPanel` dims every row from index `active_plan_count(pawn)` down and
## writes "Inert" on it; `decide()` below stops iterating at the same index. Two
## implementations of this rule would drift, and the drift is precisely the
## defect it was written to fix: a row the screen calls inert that the pawn
## fires anyway.
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

## Issue 671: a pawn spends its WIS budget on its rows; an enemy has none and
## every row in `unit.enemy_plans` is active. Two sources, one walk.
static func decide(state: CombatState, unit: CombatUnit) -> Intent:
	var plans: Array[Plan] = unit.pawn.plans if unit.pawn != null else unit.enemy_plans
	var active := active_plan_count(unit.pawn) if unit.pawn != null else plans.size()
	for i in active:
		var plan: Plan = plans[i]
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
	return plan.condition.holds(state, unit)

# ---------------------------------------------------------------------------

## Blocks run in list order, and that order is load-bearing: every TARGETING
## block writes `unit.focus_id` as it goes, so a later one overrules an earlier.
static func _run_blocks(state: CombatState, unit: CombatUnit, plan: Plan) -> Intent:
	var action_block: UseActionBlock = null
	var movement: MovementBlock = null
	for block in plan.blocks:
		if block is TargetingBlock:
			var target_id := (block as TargetingBlock).pick(state, unit)
			if target_id != -1:
				unit.focus_id = target_id
		elif block is UseActionBlock:
			action_block = block
		elif block is MovementBlock:
			movement = block
	## Asked after the walk, not during it: a derived action reads the target,
	## and a targeting block later in the list can still move it.
	var action: ActionDef = null if action_block == null else action_block.resolve(state, unit, unit.focus_id)
	if movement != null:
		return movement.run(state, unit, plan, action)
	if action == null or unit.focus_id == -1:
		return null
	if not action_can_fire(state, unit, action, unit.focus_id):
		return null
	return Intent.use_action(action.id, action_target_id(unit, action, unit.focus_id), plan.id)

## Issue 424: the point on the band the row sends the pawn to, and it is the
## nearest one that does not harm. Distance from the target is exactly `wanted`
## on every bearing, so the row keeps the promise it makes; only which side of
## the target it holds from moves. Null when the whole band burns or is walled.
static func kite_anchor(state: CombatState, unit: CombatUnit, centre: Vector2, bearing: Vector2, wanted: float):
	var step := TAU / float(SAFE_GROUND_DIRECTIONS)
	for i in SAFE_GROUND_DIRECTIONS / 2 + 1:
		for turn in ([0.0] if i == 0 else [step * float(i), -step * float(i)]):
			var spot := centre + bearing.rotated(turn) * wanted
			spot = Vector2(
				clampf(spot.x, -CG.ARENA_HALF_WIDTH, CG.ARENA_HALF_WIDTH),
				clampf(spot.y, -CG.ARENA_HALF_HEIGHT, CG.ARENA_HALF_HEIGHT))
			if state.grid.move_blocked(spot, unit.radius):
				continue
			if CombatSim.standing_harms(state, spot):
				continue
			return spot
	return null

## Issue 97: who the action is aimed at, which is not always who the plan is
## focused on -- a self-targeted action is cast on the caster whatever the
## targeting block picked, so a MOVEMENT block can measure its distance from an
## enemy while the buff inside it still lands on the pawn.
static func action_target_id(unit: CombatUnit, action: ActionDef, target_id: int) -> int:
	return unit.id if action != null and action.targets_self else target_id

## The nearest standing spot within `SAFE_GROUND_REACH` that does not harm, or
## null when everything in reach does. Deterministic: radius outward, then a
## fixed ring of directions, first match wins.
static func safe_spot(state: CombatState, unit: CombatUnit):
	var radius := SAFE_GROUND_STEP
	while radius <= SAFE_GROUND_REACH:
		for i in SAFE_GROUND_DIRECTIONS:
			var angle := TAU * float(i) / float(SAFE_GROUND_DIRECTIONS)
			var spot := unit.position + Vector2.RIGHT.rotated(angle) * radius
			spot = Vector2(
				clampf(spot.x, -CG.ARENA_HALF_WIDTH, CG.ARENA_HALF_WIDTH),
				clampf(spot.y, -CG.ARENA_HALF_HEIGHT, CG.ARENA_HALF_HEIGHT))
			if state.grid.move_blocked(spot, unit.radius):
				continue
			if CombatSim.standing_harms(state, spot):
				continue
			return spot
		radius += SAFE_GROUND_STEP
	return null

## True when the action can only be used with a clear line to its target.
static func action_needs_line_of_sight(action: ActionDef) -> bool:
	return action != null and action.requires_line_of_sight

## Whether a shot from `threat` at `pos` would be stopped by terrain or by an
## ally's raised shield. The shield half is `CombatSim`'s own interception test,
## called rather than copied, so the plan layer and the projectile cannot
## disagree about what counts as cover.
static func in_cover_from(state: CombatState, unit: CombatUnit, pos: Vector2, threat: CombatUnit) -> bool:
	if state.grid.sight_blocked(threat.position, pos):
		return true
	return CombatSim.shot_would_be_shielded(state, unit.team, threat.team, threat.position, pos)

## Whether the pawn stands in cover from its own focus right now. No focus, or a
## dead one, is not cover: `SelfInCoverBlock` and `SelfNotInCoverBlock` stay a
## strict complement, so a plan that starts "not in cover" starts true.
static func unit_in_cover(state: CombatState, unit: CombatUnit) -> bool:
	var threat := state.unit(unit.focus_id)
	if threat == null or not threat.alive:
		return false
	return in_cover_from(state, unit, unit.position, threat)

## The nearest standing spot that is in cover from `threat`, or null when the
## room offers none. Deterministic: fixed iteration order and a strict
## improvement test, so ties go to the earlier candidate rather than the rng.
static func cover_spot(state: CombatState, unit: CombatUnit, threat: CombatUnit):
	var best = null
	var best_dist := INF
	for c in state.grid.sight_blocking_cells():
		var centre: Vector2 = TerrainGrid.rect_of(c).get_center()
		var away := centre - threat.position
		if away.length() < 0.0001:
			continue
		var spot := centre + away.normalized() * (TerrainGrid.CELL * 0.5 + COVER_STANDOFF)
		var d := unit.position.distance_to(spot)
		if d >= best_dist:
			continue
		if state.grid.move_blocked(spot, unit.radius):
			continue
		if not state.grid.sight_blocked(threat.position, spot):
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
		if state.grid.move_blocked(spot2, unit.radius):
			continue
		if not CombatSim.shot_would_be_shielded(state, unit.team, threat.team, threat.position, spot2):
			continue
		best_dist = d2
		best = spot2
	return best

## Every gate `_run_blocks` applies to an action, asked as one question. Issue
## 650: `target_id` is explicit rather than read off `unit.focus_id`, because
## `DefaultPlan`'s rows deliberately never write it and gating them against
## the wrong target would be worse than not gating them at all.
static func action_can_fire(state: CombatState, unit: CombatUnit, action: ActionDef, target_id: int) -> bool:
	return _unit_has_action(unit, action) \
		and _target_in_range(state, unit, action, target_id) \
		and _target_in_los(state, unit, action, target_id) \
		and can_afford(state, unit, action) \
		and _summon_slot_free(state, unit, action) \
		and _target_is_marked(state, unit, action, target_id)

## Issue 100: a plan may only fire an action the unit actually has.
static func _unit_has_action(unit: CombatUnit, action: ActionDef) -> bool:
	if unit.actions.is_empty():
		return true
	return unit.actions.has(action.id)

## Issue 14a: a plan must not order a shot it already knows will miss. The
## focused target's distance is checked against the action's own range here,
## once, right before the intent is built -- the one place both numbers are
## available together. Out of range falls through rather than trying to move
## into range itself.
static func _target_in_range(state: CombatState, unit: CombatUnit, action: ActionDef, target_id: int) -> bool:
	if action == null:
		return true
	var target := state.unit(action_target_id(unit, action, target_id))
	if target == null:
		return false
	return unit.gap(target) <= action.range_units

## Issue 34: not a duplicate of the resolve-time line-of-sight check -- this one
## asks "should I even aim at this?" before committing, so a unit with a blocked
## but in-range target has a reason to walk instead of freezing on a shot it can
## already see is hopeless.
static func _target_in_los(state: CombatState, unit: CombatUnit, action: ActionDef, target_id: int) -> bool:
	if action == null or not action.requires_line_of_sight:
		return true
	var target := state.unit(action_target_id(unit, action, target_id))
	if target == null:
		return false
	return not state.grid.sight_blocked(unit.position, target.position)

## Issue 22: same shape as 14a's range check, same reasoning. A plan whose
## action the unit cannot actually pay for right now -- not enough resource, or
## still on cooldown -- must not commit CombatSim to refusing it and burning the
## tick.
static func can_afford(state: CombatState, unit: CombatUnit, action: ActionDef) -> bool:
	if action == null:
		return true
	if unit.resource < action.resource_cost:
		return false
	if unit.cooldowns.has(action.id) and state.tick < int(unit.cooldowns[action.id]):
		return false
	return true

## Issue 93: the summon cap, and it is a gate on *choosing* the action rather
## than a refusal at spawn time. Same shape and same reasoning as `can_afford`.
static func _summon_slot_free(state: CombatState, unit: CombatUnit, action: ActionDef) -> bool:
	if action == null or action.max_active_summons <= 0 or action.summons_unit_id == &"":
		return true
	var live := 0
	for u in state.living(unit.team):
		if u.enemy_id == action.summons_unit_id:
			live += 1
	return live < action.max_active_summons

## Issue 93: an action that may only be aimed at an enemy carrying MARKED. Same
## fall-through shape as the range and line-of-sight checks above.
static func _target_is_marked(state: CombatState, unit: CombatUnit, action: ActionDef, target_id: int) -> bool:
	if action == null or not action.requires_marked_target:
		return true
	var target := state.unit(action_target_id(unit, action, target_id))
	return target != null and target.has_status(CG.Status.MARKED)

# ---------------------------------------------------------------------------
# The shared searches. Blocks call these rather than each carrying their own,
# so a condition and the targeting op that pairs with it cannot disagree about
# which unit qualifies.

static func enemy_team(team: CG.Team) -> CG.Team:
	return CG.Team.ENEMY if team == CG.Team.PLAYER else CG.Team.PLAYER

static func nearest(state: CombatState, unit: CombatUnit, team: CG.Team) -> CombatUnit:
	var best: CombatUnit = null
	var best_dist := INF
	for candidate in state.living(team):
		var d := unit.position.distance_to(candidate.position)
		if d < best_dist:
			best_dist = d
			best = candidate
	return best

static func nearest_enemy_with_status(state: CombatState, unit: CombatUnit, status: CG.Status) -> CombatUnit:
	var best: CombatUnit = null
	var best_dist := INF
	for foe in state.living(enemy_team(unit.team)):
		if not foe.has_status(status):
			continue
		var d := unit.position.distance_to(foe.position)
		if d < best_dist:
			best_dist = d
			best = foe
	return best

## Issue 206: the complement of `nearest_enemy_with_status`, so the two ops
## cannot disagree about which enemy qualifies.
static func nearest_enemy_without_status(state: CombatState, unit: CombatUnit, status: CG.Status) -> CombatUnit:
	var best: CombatUnit = null
	var best_dist := INF
	for foe in state.living(enemy_team(unit.team)):
		if foe.has_status(status):
			continue
		var d := unit.position.distance_to(foe.position)
		if d < best_dist:
			best_dist = d
			best = foe
	return best

## The nearest living ally carrying any status `CG.is_harmful` classifies as
## harmful, or null. `unit` counts as an ally at distance 0, so a poisoned
## caster scrubs itself first.
static func nearest_afflicted_ally(state: CombatState, unit: CombatUnit) -> CombatUnit:
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

static func lowest_hp_fraction(units: Array[CombatUnit]) -> CombatUnit:
	var best: CombatUnit = null
	var best_fraction := INF
	for u in units:
		var f := u.hp_fraction()
		if f < best_fraction:
			best_fraction = f
			best = u
	return best

## Player-facing name for a status, for the plan sentences.
static func status_word(status: int) -> String:
	return String(CG.Status.keys()[status]).capitalize()
