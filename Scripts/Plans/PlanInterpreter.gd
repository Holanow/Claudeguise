extends RefCounted

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")
const Intent := preload("res://Scripts/Core/Intent.gd")
const Plan := preload("res://Scripts/Core/Plan.gd")
const PlanBlock := preload("res://Scripts/Core/PlanBlock.gd")

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

static func decide(state: CombatState, unit: CombatUnit) -> Intent:
	push_error("PlanInterpreter.decide is not implemented yet (issue 2, owner teal)")
	return Intent.idle()

## True when the plan's condition holds for this unit right now. Split out
## because the battle view greys out plans that cannot fire, and because it is
## the piece worth testing on its own.
static func condition_holds(state: CombatState, unit: CombatUnit, plan: Plan) -> bool:
	push_error("PlanInterpreter.condition_holds is not implemented yet (issue 2, owner teal)")
	return false
