extends RefCounted
class_name CombatEvent

const Self := preload("res://Scripts/Core/CombatEvent.gd")

## Everything the simulation reports outwards. The battle view, the floating
## numbers and the combat log are built from these and from nothing else.

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

## Set on DAMAGE. What mitigation left, before the remaining-health clamp, so
## the gap the raw roll opens can be split into what was mitigated and what was
## overkill on a target already dying.
var amount_after_mitigation: int = 0

## Set on DAMAGE when mitigation took something off the raw roll. It names the
## cause of the DAMAGE-REDUCTION share only, never the shield-pool share.
var mitigation_cause: CG.MitigationCause = CG.MitigationCause.NONE

## Issue 593. Set on DAMAGE for the part of the gap a raised block's health pool
## soaked, which damage reduction did not cause and must not be credited with.
var amount_absorbed: int = 0

## Issue 766. Set on DAMAGE when `mitigation_cause` is SHIELD or BLOCK: the
## action id of the cast that raised the status doing the mitigating, so the
## prevented amount can be attributed to that cast rather than only to a cause.
var mitigation_source_action: StringName = &""

## Issue 155. Which plan row chose this, copied off `Intent.source_plan` as the
## intent is consumed. **Set on ACTION_START only** -- the one event marking a
## decision rather than a consequence; a DAMAGE line inherits its reason from the
## ACTION_START above it. Three meanings:
var source_plan: StringName = &""

## Set on FIGHT_END only; see `CG.EndReason`. A fact the simulation knows as it
## decides and the view cannot recover after: by the time the banner draws, "the
## last enemy died" and "the last enemy became furniture" look identical.
var end_reason: CG.EndReason = CG.EndReason.UNSET

## Set on TERRAIN_ADDED and TERRAIN_REMOVED. Issue 492: the view may not learn
## about a pool by reading `state.terrain`, so the shape and the reason travel
## on the event and the terrain is reconstructible from the stream alone.
var terrain_kind: Terrain.Kind = Terrain.Kind.WALL
var terrain_rect: Rect2 = Rect2()
var terrain_change: CG.TerrainChange = CG.TerrainChange.CAST

## Set on ACTION_FIRE and MISS for an action with `beats`: which entry in
## `ActionDef.beats` produced this event. -1 for every other action.
var beat_index: int = -1

static func make(kind: CG.EventKind, tick: int) -> Self:
	var e := Self.new()
	e.kind = kind
	e.tick = tick
	return e
