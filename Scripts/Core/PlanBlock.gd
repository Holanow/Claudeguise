extends Resource

## One block inside a plan. README.md names four kinds and they behave
## differently enough that the kind is not decoration: a CONDITION gates the
## plan, a TARGETING block resolves instantly and moves the pawn's focus, an
## ACTION block is the only kind that takes time, and a DURATION block says how
## long the preceding action repeats.
##
## MANAGER-OWNED SHAPE. Concrete block behaviour lives in Scripts/Plans/ and
## belongs to the content session.

## MOVEMENT is appended, never inserted: a plan's blocks are authored data and
## a reordered enum silently reinterprets every one that already exists.
##
## It exists because `PlanInterpreter` has never been able to produce a
## movement intent -- its own comment says so -- so **where a pawn stands has
## always been decided somewhere the player cannot see or change.** That is the
## principle in issue 98, and kiting was its most visible symptom: a pawn
## backing away from a fight the player told it to join.
##
## heron measured the size of the gap before this was added, and the number
## worth remembering is not about kiting: **only 14-50% of a player pawn's
## decisions come from its plans at all.** The rest is `DefaultBehavior`.
## Movement is the first of those to become authorable, and it is a small slice
## -- action choice and target choice are the large ones.
enum Kind { CONDITION, TARGETING, ACTION, DURATION, MOVEMENT }

## Which selector or predicate this block runs. The interpreter maps this to an
## implementation; unknown ids must fail loudly rather than be skipped, because
## a silently ignored block reads to a player as the plan simply not working.
@export var op: StringName = &""
@export var kind: Kind = Kind.ACTION

## Operands. Shape depends on op and is documented next to each op in
## Scripts/Plans/. Kept as a Dictionary so adding a block type needs no change
## to this file, which every session would otherwise have to edit.
@export var args: Dictionary = {}
