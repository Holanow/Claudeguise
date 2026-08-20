extends RefCounted
class_name Intent


## A script cannot name itself without `class_name`, and this project has none.
## `Self` is how a file refers to its own type in a return annotation or a
## constructor. Self-preload is legal and was measured working.
const Self := preload("res://Scripts/Core/Intent.gd")

## What a decision layer wants a unit to do on one tick. The plan interpreter
## and the default behaviour both produce these and neither may touch a
## CombatUnit directly.

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
