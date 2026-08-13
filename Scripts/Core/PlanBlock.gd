extends Resource

## One block inside a plan. README.md names four kinds and they behave
## differently enough that the kind is not decoration: a CONDITION gates the
## plan, a TARGETING block resolves instantly and moves the pawn's focus, an
## ACTION block is the only kind that takes time, and a DURATION block says how
## long the preceding action repeats.
##
## MANAGER-OWNED SHAPE. Concrete block behaviour lives in Scripts/Plans/ and
## belongs to the content session.

enum Kind { CONDITION, TARGETING, ACTION, DURATION }

## Which selector or predicate this block runs. The interpreter maps this to an
## implementation; unknown ids must fail loudly rather than be skipped, because
## a silently ignored block reads to a player as the plan simply not working.
@export var op: StringName = &""
@export var kind: Kind = Kind.ACTION

## Operands. Shape depends on op and is documented next to each op in
## Scripts/Plans/. Kept as a Dictionary so adding a block type needs no change
## to this file, which every session would otherwise have to edit.
@export var args: Dictionary = {}
