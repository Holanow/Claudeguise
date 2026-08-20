extends RefCounted

const CG := preload("res://Scripts/Core/CG.gd")
const Self := preload("res://Scripts/Core/CombatEvent.gd")

## Everything the simulation reports outwards. The battle view, the floating
## numbers and the combat log are built from these and from nothing else.
##
## A view that polls `CombatUnit.hp` each frame can show a number change but
## cannot say why, and "that felt bad" then has no cause attached to it.
##
## MANAGER-OWNED SHAPE.

var kind: CG.EventKind = CG.EventKind.DAMAGE
var tick: int = 0

## Unit ids, or -1 where not applicable.
var source_id: int = -1
var target_id: int = -1

## Damage, healing or resource spent, after all modifiers. The number the player
## sees floating over a unit.
var amount: int = 0

var damage_type: CG.DamageType = CG.DamageType.PHYSICAL
var action_id: StringName = &""
var status: CG.Status = CG.Status.SHIELD

## Set on DAMAGE when the raw roll was reduced, so the log can show mitigation
## rather than leaving the player wondering why a hit landed small.
var amount_before_mitigation: int = 0

## Issue 155. Which plan row chose this, copied off `Intent.source_plan` as the
## intent is consumed. **Set on ACTION_START only** -- the one event marking a
## decision rather than a consequence; a DAMAGE line inherits its reason from the
## ACTION_START above it. Three meanings:
##   - a plan id        -> that row of the pawn's plans fired
##   - &""              -> nothing fired, DefaultBehavior chose
##   - Intent.COMPELLED -> a taunt overrode what the plans wanted
var source_plan: StringName = &""

## Set on FIGHT_END only; see `CG.EndReason`. A fact the simulation knows as it
## decides and the view cannot recover after: by the time the banner draws, "the
## last enemy died" and "the last enemy became furniture" look identical.
var end_reason: CG.EndReason = CG.EndReason.UNSET

static func make(kind: CG.EventKind, tick: int) -> Self:
	var e := Self.new()
	e.kind = kind
	e.tick = tick
	return e
