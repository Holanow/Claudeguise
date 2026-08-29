extends RefCounted
class_name DefaultPlan


## What a unit does when no plan of its own fires, written as a plan. Issue
## 719: two rules and nothing else -- move toward the nearest enemy, attack
## one in range with the weapon's basic attack. Hazard avoidance needs no code
## here: every `MOVE_TO` already rides `CombatSim._avoid_hazard` (issue 163).

const MELEE_RANGE_THRESHOLD := 60.0
const MELEE_COMMIT_FRACTION := 0.5
const RANGED_COMMIT_FRACTION := 0.85

const ATTACK_ROW := &"@default_attack"

static func decide(state: CombatState, unit: CombatUnit) -> Intent:
	if state.living(PlanInterpreter.enemy_team(unit.team)).is_empty():
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
	## Issue 650: gated the same way an authored row's action is. Null, not
	## idle -- `decide` tries the next candidate row rather than spending
	## the tick on an action it already knows CombatSim would refuse.
	if not PlanInterpreter.action_can_fire(state, unit, action, target_id):
		return null
	return Intent.use_action(action.id, target_id)

# ---------------------------------------------------------------------------
# The one row.

## Structural: which action the row carries depends on what the unit's
## weapon grants, never on what is happening this tick.
static func rows_for(unit: CombatUnit) -> Array[Plan]:
	var plan := Plan.new()
	plan.id = ATTACK_ROW
	plan.display_name = "Attack"
	plan.condition = BlockCatalog.condition(&"always")
	var use := UseActionBlock.new()
	use.action = weapon_attack(unit)
	var close := CloseAndActBlock.new()
	close.melee_fraction = MELEE_COMMIT_FRACTION
	close.ranged_fraction = RANGED_COMMIT_FRACTION
	plan.blocks = [
		TargetNearestAttackableEnemyBlock.new(),
		use,
		close,
	] as Array[PlanBlock]
	return [plan] as Array[Plan]

## Issue 719: the weapon's basic attack, specifically -- not the cheapest
## affordable action and not a class ability. A pawn's weapon grants exactly
## the action it fights with; an enemy has no weapon, so its basic attack is
## the first attack-shaped action in its own list.
static func weapon_attack(unit: CombatUnit) -> ActionDef:
	var ids: Array[StringName] = []
	if unit.pawn != null:
		if unit.pawn.main_hand != null:
			ids = unit.pawn.main_hand.granted_actions
	else:
		ids = unit.actions
	var actions: Array[ActionDef] = []
	for id in ids:
		var a: ActionDef = ActionLibrary.get_action(id)
		if a != null:
			actions.append(a)
	var attack_shaped := PlanInterpreter.attacks(actions)
	return attack_shaped[0] if not attack_shaped.is_empty() else null

## Issue 747: whether `off_hand` is a second weapon that alternates the attack,
## rather than a shield, a focus or a quiver. MARTIAL, per the player's own
## words, and `required_tags` is where that lives on an item (#131) -- every
## weapon in the game already requires it, and no shield/focus/quiver does not
## also grant an attack, so the two checks together are exactly "a weapon".
static func dual_wields(pawn: PawnData) -> bool:
	if pawn == null or pawn.off_hand == null:
		return false
	if not pawn.off_hand.required_tags.has(CG.Tag.MARTIAL):
		return false
	var actions: Array[ActionDef] = []
	for id in pawn.off_hand.granted_actions:
		var a: ActionDef = ActionLibrary.get_action(id)
		if a != null:
			actions.append(a)
	return not PlanInterpreter.attacks(actions).is_empty()
