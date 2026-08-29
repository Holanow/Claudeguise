extends Resource
class_name Plan


## One plan of action: a trigger condition followed by an ordered list of
## blocks. Per README.md a plan is "when <condition>, do <blocks>", the number
## of rows a pawn may carry is capped flat, and only one plan fires per
## tick per pawn.

@export var id: StringName = &""
@export var display_name: String = ""

## Evaluated each tick against the pawn's view of the fight. Null means the plan
## always wants to fire, which is how a default behaviour is written.
@export var condition: ConditionBlock

## Targeting, action, duration and movement blocks in execution order.
@export var blocks: Array[PlanBlock] = []

func block_count() -> int:
	return blocks.size()
