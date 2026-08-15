extends RefCounted

const CG := preload("res://Scripts/Core/CG.gd")

## A script cannot name itself without `class_name`, and this project has none.
## `Self` is how a file refers to its own type in a return annotation or a
## constructor. Self-preload is legal and was measured working.
const Self := preload("res://Scripts/Core/Intent.gd")

## What a decision layer wants a unit to do on one tick. The plan interpreter
## and the default behaviour both produce these and neither may touch a
## CombatUnit directly.
##
## The split exists so that "the pawn decided badly" and "the simulation
## resolved badly" stay separable. When a fight reads wrong, the combat log
## shows which one it was.
##
## MANAGER-OWNED SHAPE.

var kind: CG.IntentKind = CG.IntentKind.IDLE

## MOVE_TO only.
var destination: Vector2 = Vector2.ZERO

## USE_ACTION only.
var action_id: StringName = &""

## Unit id the intent is aimed at, or -1. For USE_ACTION this is normally the
## unit's focus_id, but a targeting block may aim a single action elsewhere.
var target_id: int = -1

## Which plan produced this, or &"" for the default behaviour. Written into the
## combat log so a player can see which plan fired.
var source_plan: StringName = &""

## Issue 155. The reserved `source_plan` for an intent NO decision layer chose:
## the taunt compulsion in `CombatSim._compelled_intent`, which beats a stated
## plan on purpose.
##
## It needs its own value because it is a third thing, not a shade of the other
## two. Left at &"" it reads as "the fallback decided", which is wrong in the one
## case a player is most likely to be confused by — their pawn abandoning the row
## they wrote. Issue 98's principle is exactly this: a pawn doing something that
## is in no plan the player can see.
##
## The `@` prefix cannot collide with a real plan id: `Plan.id` values are
## authored as identifiers in `PresetPlans`.
const COMPELLED := &"@taunted"

static func idle(plan: StringName = &"") -> Self:
	var i := Self.new()
	i.kind = CG.IntentKind.IDLE
	i.source_plan = plan
	return i

static func move_to(dest: Vector2, plan: StringName = &"") -> Self:
	var i := Self.new()
	i.kind = CG.IntentKind.MOVE_TO
	i.destination = dest
	i.source_plan = plan
	return i

static func use_action(action_id: StringName, target_id: int, plan: StringName = &"") -> Self:
	var i := Self.new()
	i.kind = CG.IntentKind.USE_ACTION
	i.action_id = action_id
	i.target_id = target_id
	i.source_plan = plan
	return i
