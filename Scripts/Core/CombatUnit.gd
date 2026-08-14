extends RefCounted

const CG := preload("res://Scripts/Core/CG.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const Intent := preload("res://Scripts/Core/Intent.gd")

## One combatant's live state inside a fight. Built once from a PawnData or an
## enemy definition and mutated only by the simulation.
##
## MANAGER-OWNED SHAPE. The combat session fills in behaviour, the view reads
## these fields, and nobody outside Scripts/Combat/ writes to one.
##
## Every field here is either an integer, a float, or a container of them. There
## are no node references and no timers. That is what lets a fight be saved as a
## seed and replayed.

## Stable within one fight. Index into CombatState.units.
var id: int = -1

var team: CG.Team = CG.Team.PLAYER
var display_name: String = ""

## The pawn this was built from. Null for enemies, which have no PawnData.
var pawn: PawnData = null

## Content id of the enemy definition, or &"" for player pawns. Lets the view
## pick a sprite without knowing anything about enemy internals.
var enemy_id: StringName = &""

var position: Vector2 = Vector2.ZERO
## Drawing only. Verified 2026-08-12: nothing in Scripts/Combat, Scripts/Plans
## or Scripts/Floor reads this for range, movement or collision, so changing it
## cannot disturb anyone's tuning. Raised from 12.0 for legibility at phone size.
var radius: float = 22.0

var hp: int = 0
var hp_max: int = 0
var resource: int = 0
var resource_max: int = 0
var resource_kind: CG.ResourceKind = CG.ResourceKind.ENERGY

## World units per tick.
var move_speed: float = 0.0

var alive: bool = true

## Set by the decision layer, consumed by the simulation on the same tick.
##
## The seam between the two halves of a tick, and it is deliberate. The
## simulation only asks the decision layer for an intent when this is null, and
## it clears the field once it has resolved it. So a test can put an intent here
## by hand and drive the simulation with no plans, no default behaviour and no
## content of any kind, which is what lets the simulation and the decision layer
## be built at the same time by two sessions who cannot run each other's code.
var intent: Intent = null

## Unit id this pawn is currently focused on, or -1. Targeting blocks write
## this and it persists across ticks: a plan that says "focus nearest enemy,
## then attack" must not re-target between the two.
var focus_id: int = -1

## Which way this unit is looking, as a unit vector. Zero means "no facing yet",
## which is every unit before anything sets it.
##
## The simulation has never needed this: `_resolve_targets` resolves a shot
## instantly at fire time, so nothing has ever cared where a unit was pointed.
## The UI derives a `facing_left` flag for drawing and that is all.
##
## It exists now because the Warrior is getting a guard that stops ranged
## attacks crossing its front, and "its front" has to be a real quantity the
## simulation agrees on rather than something the renderer guessed.
var facing: Vector2 = Vector2.ZERO

## How far this unit's TAUNTING reaches while the status holds, copied from the
## action that applied it. 0.0 when not taunting.
##
## Stored here rather than looked up through the action each tick, matching the
## rest of the derived-at-apply-time state on this shape.
var taunt_radius: float = 0.0

## Issue 61. The sustained action this unit is currently holding, or &"" when it
## is holding nothing -- which is every unit in every fight until content
## authors an action with `sustain_cost_per_tick > 0`.
##
## Stored here rather than derived, on exactly the `taunt_radius` precedent: a
## status the rest of the game can see (CG.Status.SUSTAINING) with its magnitude
## -- here, *which* action -- kept on the unit beside it. CombatSim is the only
## writer and sets both in the same two places, so the pair cannot drift.
var sustaining: StringName = &""

## The tick the current channel began, or -1 when nothing is held. Carried into
## SUSTAIN_END.amount so a log line can say how long a pawn held it, which is
## otherwise unrecoverable after the fact for the same reason
## `action_ticks_total` had to exist.
var sustain_started_tick: int = -1

## The action being performed, or &"" when free. While busy the unit's intent
## is not read.
var current_action: StringName = &""
var action_ticks_left: int = 0

## What `action_ticks_left` started at for the action currently being performed.
## 0 when the unit is free.
##
## Exists so a wind-up can be drawn as a **countdown** rather than a fixed ring:
## progress is `1.0 - action_ticks_left / action_ticks_total`, and there is no
## way to recover the denominator after the fact. `wind_up_ticks` on the action
## is not it -- `_apply_haste` scales the real value at commit time, so a hasted
## unit's ring would run at the wrong rate against the raw number.
##
## Requested by wren with an exact signature rather than worked around in the
## UI, after sable built the countdown art. Written once beside
## `action_ticks_left` in `CombatSim`; nothing else should set it.
var action_ticks_total: int = 0
var recover_ticks_left: int = 0

## Keyed by action id, value is the tick the cooldown ends.
var cooldowns: Dictionary = {}

## Keyed by CG.Status, value is the tick the status expires.
var statuses: Dictionary = {}

## Action ids available to this unit, from class, equipment and enemy
## definition combined at build time.
var actions: Array[StringName] = []

func is_busy() -> bool:
	return action_ticks_left > 0 or recover_ticks_left > 0

func has_status(s: CG.Status) -> bool:
	return statuses.has(s)

func hp_fraction() -> float:
	if hp_max <= 0:
		return 0.0
	return float(hp) / float(hp_max)
