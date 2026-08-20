extends Resource
class_name PlanBlock

## One block inside a plan. The kind is not decoration: CONDITION gates the
## plan, TARGETING resolves instantly and moves the pawn's focus, ACTION is the
## only kind that takes time, DURATION says how long the action repeats.

## Append only, never insert. Plans are authored data, and a reordered enum
## silently reinterprets every plan that already exists.
enum Kind { CONDITION, TARGETING, ACTION, DURATION, MOVEMENT }

## Which selector or predicate this block runs. An unknown id must fail loudly
## rather than be skipped: a silently ignored block reads to a player as the
## plan simply not working.
@export var op: StringName = &""
@export var kind: Kind = Kind.ACTION

## Operands. Shape depends on op and is documented beside each op in Scripts/Plans/.
@export var args: Dictionary = {}
