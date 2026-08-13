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
var radius: float = 12.0

var hp: int = 0
var hp_max: int = 0
var resource: int = 0
var resource_max: int = 0
var resource_kind: CG.ResourceKind = CG.ResourceKind.ENERGY

## World units per tick.
var move_speed: float = 0.0

var alive: bool = true

## Set by the decision layer, consumed by the simulation on the same tick.
var intent: Intent = null

## Unit id this pawn is currently focused on, or -1. Targeting blocks write
## this and it persists across ticks: a plan that says "focus nearest enemy,
## then attack" must not re-target between the two.
var focus_id: int = -1

## The action being performed, or &"" when free. While busy the unit's intent
## is not read.
var current_action: StringName = &""
var action_ticks_left: int = 0
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
