extends RefCounted

const CG := preload("res://Scripts/Core/CG.gd")
const Self := preload("res://Scripts/Core/CombatEvent.gd")

## Everything the simulation reports outwards. The battle view, the floating
## damage numbers and the combat log are all built from these and from nothing
## else.
##
## The reason for the rule: a view that polls CombatUnit.hp each frame can show
## a number changing but cannot say why it changed, and "that felt bad" then has
## no cause attached to it. Reading whether the combat is fun is the whole point
## of this slice.
##
## MANAGER-OWNED SHAPE.

var kind: CG.EventKind = CG.EventKind.DAMAGE
var tick: int = 0

## Unit ids, or -1 where not applicable.
var source_id: int = -1
var target_id: int = -1

## Damage dealt, healing done, or resource spent, after all modifiers. The
## number a player sees floating over a unit is this one.
var amount: int = 0

var damage_type: CG.DamageType = CG.DamageType.PHYSICAL
var action_id: StringName = &""
var status: CG.Status = CG.Status.SHIELD

## Set on DAMAGE when the raw roll was reduced, so the log can show mitigation
## rather than leaving a player to wonder why a hit landed small.
var amount_before_mitigation: int = 0

## Issue 155. Which plan row chose this, copied off `Intent.source_plan` at the
## moment the intent is consumed.
##
## `Intent.source_plan` has existed since the skeleton, with a doc comment saying
## it is "written into the combat log so a player can see which plan fired", and
## NOTHING HAS EVER READ IT. An intent is created and destroyed inside one
## `step()`, so the only way the field can reach a view is by riding on an event,
## and no event carried it. That is why the log has never been able to say why a
## pawn did anything: the answer was computed, stored, and thrown away every
## tick.
##
## Set on ACTION_START only. That is deliberate rather than incomplete — it is
## the one event that marks a *decision* rather than a consequence, so one tag
## per decision is the whole cost, and a DAMAGE line inherits its reason from the
## ACTION_START above it.
##
## Three meanings, and the log tells all three apart:
##   - a plan id      -> that row of the pawn's plans fired
##   - &""            -> nothing fired and DefaultBehavior chose (the fallback row)
##   - Intent.COMPELLED -> a taunt overrode whatever the plans wanted
var source_plan: StringName = &""

## Set on FIGHT_END only. See `CG.EndReason` for why the ending now needs a name.
##
## On the `source_plan` precedent directly above: a fact the simulation knows at
## the moment it decides, which the view cannot recover afterwards. By the time
## the banner draws, "the last enemy died" and "the last enemy became furniture"
## look identical from the outside — both leave a side that cannot fight.
var end_reason: CG.EndReason = CG.EndReason.UNSET

static func make(kind: CG.EventKind, tick: int) -> Self:
	var e := Self.new()
	e.kind = kind
	e.tick = tick
	return e
