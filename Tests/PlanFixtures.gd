extends RefCounted
class_name PlanFixtures

## Builds one plan block from an op name and its operands, for the fixtures and
## instruments that were written when a block was `op` plus an `args` dictionary.
##
## Issue 640: production code constructs blocks by type and sets typed fields.
## This bridge exists so ~250 fixture call sites did not have to be rewritten by
## hand in the same commit that moved the vocabulary. It refuses an operand the
## block does not declare, so a renamed field fails here rather than being set
## on nothing and read as a default.
static func block(op: StringName, args: Dictionary = {}) -> PlanBlock:
	var made := _new_block(op)
	if made == null:
		push_error("PlanFixtures: no block op named '%s'" % op)
		return null
	## Issue 658: `UseActionBlock` now carries the `ActionDef` itself.
	## `action_id` survives as a fixture-only spelling, resolved here once,
	## so ~250 call sites written for the old field did not have to move.
	if op == &"use_action" and args.has("action_id"):
		args = args.duplicate()
		args["action"] = Registry.get_action(args["action_id"])
		args.erase("action_id")
	for key in args:
		if not _declares(made, key):
			push_error("PlanFixtures: '%s' has no operand '%s'" % [op, key])
			return null
		made.set(key, args[key])
	return made

static func plan(id: StringName, condition: PlanBlock, blocks: Array[PlanBlock]) -> Plan:
	var p := Plan.new()
	p.id = id
	p.condition = condition as ConditionBlock
	p.blocks = blocks
	return p

static func _new_block(op: StringName) -> PlanBlock:
	if op == &"use_action":
		return UseActionBlock.new()
	if op == &"once":
		return OnceBlock.new()
	if BlockCatalog.CONDITIONS.has(op):
		return BlockCatalog.condition(op)
	if BlockCatalog.TARGETING.has(op):
		return BlockCatalog.targeting(op)
	if BlockCatalog.MOVEMENT.has(op):
		return BlockCatalog.movement(op)
	return null

static func _declares(made: PlanBlock, key) -> bool:
	for p in made.operands():
		if p["name"] == StringName(key):
			return true
	return false
