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

static func make(kind: CG.EventKind, tick: int) -> Self:
	var e := Self.new()
	e.kind = kind
	e.tick = tick
	return e
