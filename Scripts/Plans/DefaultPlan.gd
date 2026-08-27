extends RefCounted
class_name DefaultPlan


## What a unit does when no plan of its own fires, written as plans.
##
## Issue 641: the rows are derived from the unit's own actions and live here
## rather than in `pawn.plans`, because enemies have no pawn and because a row
## in `pawn.plans` would spend the WIS budget the player writes against.

## An action with more range than this is treated as ranged. Kept equal to
## `DefaultBehavior`'s own copy by `test_plans_default_is_a_plan.gd` for as long
## as both files exist.
const MELEE_RANGE_THRESHOLD := 60.0
const MELEE_COMMIT_FRACTION := 0.5
const RANGED_COMMIT_FRACTION := 0.85
const HEAL_THRESHOLD_FRACTION := 0.5

const HEAL_ROW := &"@default_heal"
const BUFF_ROW := &"@default_buff"
const ATTACK_ROW := &"@default_attack"

static func decide(state: CombatState, unit: CombatUnit) -> Intent:
	if state.living(PlanInterpreter.enemy_team(unit.team)).is_empty():
		return Intent.idle()
	if candidates(state, unit).is_empty():
		return Intent.idle()
	## Hold fire. Not `move_to`: the engine cannot move (move_speed 0.0).
	if attackable(state, unit).is_empty():
		return Intent.idle()
	for plan in rows_for(unit):
		if not PlanInterpreter.condition_holds(state, unit, plan):
			continue
		var intent := _run(state, unit, plan)
		if intent != null:
			return intent
	return Intent.idle()

## The same walk as `PlanInterpreter._run_blocks`, with one difference that is
## the whole reason it is a second function: it never writes `unit.focus_id`.
static func _run(state: CombatState, unit: CombatUnit, plan: Plan) -> Intent:
	var target_id := -1
	var action_block: UseActionBlock = null
	var movement: MovementBlock = null
	for block in plan.blocks:
		if block is TargetingBlock:
			var picked := (block as TargetingBlock).pick(state, unit)
			if picked != -1:
				target_id = picked
		elif block is UseActionBlock:
			action_block = block
		elif block is MovementBlock:
			movement = block
	var action: ActionDef = null if action_block == null else action_block.resolve(state, unit, target_id)
	if movement != null:
		return movement.aim(state, unit, target_id, action)
	if action == null or target_id == -1:
		return null
	return Intent.use_action(action.id, target_id)

# ---------------------------------------------------------------------------
# The rows.

## The rows this unit runs, in order. Structural: which rows exist depends on
## what the unit carries, never on what is happening this tick.
static func rows_for(unit: CombatUnit) -> Array[Plan]:
	var rows: Array[Plan] = []
	if first_heal(all_actions(unit)) != null:
		rows.append(_heal_row())
	## The self-buff row is an enemy's. A pawn writes its buffs itself, which is
	## what `unit.pawn == null` has always meant here.
	if unit.pawn == null:
		rows.append(_buff_row())
	rows.append(_attack_row(unit))
	return rows

static func _heal_row() -> Plan:
	var plan := Plan.new()
	plan.id = HEAL_ROW
	plan.display_name = "Heal whoever needs it"
	plan.condition = AllyNeedsHealBlock.new()
	plan.blocks = [
		TargetHealTargetBlock.new(),
		UseHealBlock.new(),
		MoveIntoRangeBlock.new(),
	] as Array[PlanBlock]
	return plan

static func _buff_row() -> Plan:
	var plan := Plan.new()
	plan.id = BUFF_ROW
	plan.display_name = "Buff myself once the fight is close"
	plan.condition = EnemyWithinBuffReachBlock.new()
	plan.blocks = [
		BlockCatalog.targeting(&"target_self"),
		UseSelfBuffBlock.new(),
	] as Array[PlanBlock]
	return plan

## Targeting runs last-wins, the same rule `_run_blocks` uses, so the list reads
## bottom-up as a precedence order: a taunt beats everything.
static func _attack_row(unit: CombatUnit) -> Plan:
	var plan := Plan.new()
	plan.id = ATTACK_ROW
	plan.display_name = "Attack"
	plan.condition = BlockCatalog.condition(&"always")
	var blocks: Array[PlanBlock] = [TargetNearestAttackableEnemyBlock.new()]
	if unit.pawn != null:
		blocks.append(BlockCatalog.targeting(&"target_focused_enemy"))
	else:
		blocks.append(TargetPileOnBlock.new())
	blocks.append(TargetTaunterBlock.new())
	blocks.append(UseBestAttackBlock.new())
	var close := CloseAndActBlock.new()
	close.melee_fraction = MELEE_COMMIT_FRACTION
	close.ranged_fraction = RANGED_COMMIT_FRACTION
	blocks.append(close)
	plan.blocks = blocks
	return plan

# ---------------------------------------------------------------------------
# The shared derivations. Every block above asks these rather than carrying its
# own copy, so a condition and the op it pairs with cannot disagree.

static func all_actions(unit: CombatUnit) -> Array[ActionDef]:
	var out: Array[ActionDef] = []
	for id in unit.actions:
		var a: ActionDef = ActionLibrary.get_action(id)
		if a != null:
			out.append(a)
	return out

## Issue 166: what the unit may reach for this tick. Everything it can pay for,
## widened to everything it carries when nothing payable heals or attacks.
static func candidates(state: CombatState, unit: CombatUnit) -> Array[ActionDef]:
	var affordable: Array[ActionDef] = []
	for a in all_actions(unit):
		if PlanInterpreter.can_afford(state, unit, a):
			affordable.append(a)
	if first_heal(affordable) == null and attacks(affordable).is_empty():
		return all_actions(unit)
	return affordable

## Issue 129: an action a unit attacks *with*.
static func attacks(actions: Array[ActionDef]) -> Array[ActionDef]:
	var out: Array[ActionDef] = []
	for a in actions:
		if a.heals or a.power_scale <= 0.0 or a.sustain_cost_per_tick > 0:
			continue
		out.append(a)
	return out

## Issue 87: `power_scale > 0.0` as well as `heals`, because an action that
## restores nothing is not a way to put health back into a hurt ally.
static func first_heal(actions: Array[ActionDef]) -> ActionDef:
	for a in actions:
		if a.heals and a.power_scale > 0.0:
			return a
	return null

## The heal this unit would reach for right now, or null.
static func heal_action(state: CombatState, unit: CombatUnit) -> ActionDef:
	return first_heal(candidates(state, unit))

## Issue 99: a heal with no reach is a heal a unit casts on itself, so the
## neediest-ally search is restricted to the caster.
static func heal_candidates(state: CombatState, unit: CombatUnit, heal: ActionDef) -> Array[CombatUnit]:
	if heal.range_units > 0.0:
		return state.living(unit.team)
	var out: Array[CombatUnit] = []
	if unit.alive:
		out.append(unit)
	return out

## Who the heal row aims at, or null.
static func heal_target(state: CombatState, unit: CombatUnit) -> CombatUnit:
	var heal := heal_action(state, unit)
	if heal == null:
		return null
	return PlanInterpreter.lowest_hp_fraction(heal_candidates(state, unit, heal))

## Issue 93: the enemies this unit is allowed to attack. Its whole arsenal being
## marked-only is the one case that narrows the set, and an empty answer is
## hold-fire rather than "no enemies".
static func attackable(state: CombatState, unit: CombatUnit) -> Array[CombatUnit]:
	var enemies := state.living(PlanInterpreter.enemy_team(unit.team))
	if not _every_attack_needs_a_mark(candidates(state, unit)):
		return enemies
	var out: Array[CombatUnit] = []
	for e in enemies:
		if e.has_status(CG.Status.MARKED):
			out.append(e)
	return out

## "Every", not "any", on purpose: a unit that also carries an ordinary weapon
## should use it on unmarked enemies rather than standing idle.
static func _every_attack_needs_a_mark(actions: Array[ActionDef]) -> bool:
	var found := false
	for a in attacks(actions):
		if not a.requires_marked_target:
			return false
		found = true
	return found

## The cheapest attack on one side of the melee/ranged split, ties by list
## order. Null when the unit owns none on that side.
static func side_attack(actions: Array[ActionDef], want_ranged: bool) -> ActionDef:
	var best: ActionDef = null
	for a in attacks(actions):
		if (a.range_units > MELEE_RANGE_THRESHOLD) != want_ranged:
			continue
		if best == null or a.resource_cost < best.resource_cost:
			best = a
	return best

## Issue 62: the attack whose own shape matches the target's current distance.
static func best_attack(state: CombatState, unit: CombatUnit, target: CombatUnit) -> ActionDef:
	if target == null:
		return null
	var actions := candidates(state, unit)
	var melee := side_attack(actions, false)
	var ranged := side_attack(actions, true)
	if melee == null:
		return ranged
	if ranged == null:
		return melee
	if unit.gap(target) <= melee.range_units * MELEE_COMMIT_FRACTION:
		return melee
	return ranged

## Issue 150: the first self-targeted action this unit could usefully cast right
## now, or null.
static func self_buff(state: CombatState, unit: CombatUnit) -> ActionDef:
	for a in all_actions(unit):
		if not a.targets_self:
			continue
		if a.heals or a.sustain_cost_per_tick > 0 or a.summons_unit_id != &"":
			continue
		if not PlanInterpreter.can_afford(state, unit, a):
			continue
		if _nearest_enemy_distance(state, unit) > _buff_reach(unit, a):
			continue
		return a
	return null

## How close the fight has to be before a self-buff is worth a cast.
static func _buff_reach(unit: CombatUnit, action: ActionDef) -> float:
	if action.taunt_radius > 0.0:
		return action.taunt_radius
	var longest := -1.0
	for a in attacks(all_actions(unit)):
		longest = maxf(longest, a.range_units)
	return longest if longest >= 0.0 else INF

static func _nearest_enemy_distance(state: CombatState, unit: CombatUnit) -> float:
	var best := INF
	for e in attackable(state, unit):
		best = minf(best, unit.position.distance_to(e.position))
	return best
