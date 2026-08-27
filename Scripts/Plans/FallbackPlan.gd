extends RefCounted
class_name FallbackPlan

## Issue 641: what a unit does when no plan fires, AS PLAN ROWS the player can
## read. The rows are the policy; everything `decide` does around them is rule
## or mechanism and is deliberately not offered as a row -- see the sorting on
## the issue.

## The reserved ids. These are player-facing: they are written into every
## fallback intent's `source_plan` and printed in the combat log, so they read
## as sentences rather than as symbols.
const HEAL_ROW := &"default: heal the hurt"
const STEADY_ROW := &"default: steady myself"
const ENGAGE_ROW := &"default: engage"

## The rows, in the order `decide` evaluates them. Order is priority and it is
## the same order the old procedure had.
static func rows_for(unit: CombatUnit) -> Array[Plan]:
	var out: Array[Plan] = []
	out.append(_row(HEAL_ROW, "Heal the hurt", AllyNeedsHealBlock.new(),
		[TargetNeediestAllyBlock.new(), ApproachThenHealBlock.new()]))
	## Gated on `unit.pawn == null` in the old procedure, so a party pawn never
	## buffs itself from the fallback. Kept exactly, and it is why the row is
	## absent rather than merely never firing: a row a pawn cannot run should
	## not be on the pawn's screen.
	if unit == null or unit.pawn == null:
		out.append(_row(STEADY_ROW, "Steady myself", SelfBuffReadyBlock.new(),
			[TargetSelfBlock.new(), UseSelfBuffBlock.new()]))
	out.append(_row(ENGAGE_ROW, "Engage", AlwaysBlock.new(),
		[FallbackTargetBlock.new(), EngageBlock.new()]))
	return out

static func _row(id: StringName, name: String, condition: ConditionBlock,
		blocks: Array[PlanBlock]) -> Plan:
	var p := Plan.new()
	p.id = id
	p.display_name = name
	p.condition = condition
	p.blocks = blocks
	return p

## The fallback, run off its own rows. The structure around them is the rule and
## mechanism half of the sorting: no enemies, nothing affordable, and issue 93's
## mark filter all decide before any row is consulted.
static func decide(state: CombatState, unit: CombatUnit) -> Intent:
	var enemies := state.living(CG.Team.ENEMY if unit.team == CG.Team.PLAYER else CG.Team.PLAYER)
	if enemies.is_empty():
		return Intent.idle()
	if DefaultBehavior.candidates_for(state, unit).is_empty():
		return Intent.idle()
	if DefaultBehavior.legal_enemies(state, unit).is_empty():
		return Intent.idle()

	for plan in rows_for(unit):
		if not plan.condition.holds(state, unit):
			continue
		var intent := _run(state, unit, plan)
		if intent != null:
			return intent
	return Intent.idle()

## The fallback mode's own block walker. It is not `_run_blocks`: that writes
## `unit.focus_id` at decide time and the fallback never has, and its action
## gates are the six-gate set rather than this one's.
static func _run(state: CombatState, unit: CombatUnit, plan: Plan) -> Intent:
	var subject: CombatUnit = null
	for block in plan.blocks:
		if block is TargetingBlock:
			subject = state.unit((block as TargetingBlock).pick(state, unit))
		elif block is ApproachThenHealBlock:
			return (block as ApproachThenHealBlock).run(state, unit, plan, subject)
		elif block is UseSelfBuffBlock:
			var buff := (block as UseSelfBuffBlock).action_for(state, unit)
			return null if buff == null else Intent.use_action(buff.id, unit.id, plan.id)
		elif block is EngageBlock:
			return (block as EngageBlock).run(state, unit, plan, subject)
	return null
