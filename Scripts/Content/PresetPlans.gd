extends RefCounted
class_name PresetPlans

## The library of plan rows a player can add. Issue 399: a class ships with no
## rows, so nothing here is on a pawn until the player puts it there.


## Issue 138: the Mana a Priest's lower plans must leave standing, so the heal
## above them can still be paid for. `priest_heal` costs 25 and Ward, Haste and
## Smite each cost 15, so 40 is "my own cost, plus the heal's, or I do not cast".
const PRIEST_SPENDER_RESERVE := 40

## Issue 166: the Mana below which a Channel is worth standing still for. It is
## the Channel's own restore, so a Channel never overfills and is never wasted.
const CHANNEL_WHEN_BELOW := 25

## Issue 433: the hp share at which the Priest's and the Warrior's heal rows
## fire, and **both must stay above `DefaultBehavior.HEAL_THRESHOLD_FRACTION`.**
## `_first_heal` runs for pawns, so at or below that share the fallback is
## already casting the same heal at the same target and the row restates it.
const HEAL_ABOVE_FALLBACK := 0.85
const SECOND_WIND_ABOVE_FALLBACK := 0.7

## Issue 433: how close an enemy must be before the Warrior's Taunt row fires.
## It is `warrior_taunt`'s own `taunt_radius`, so the row cannot order a shout
## that reaches nobody.
const TAUNT_AT_RADIUS := 350.0

## Issue 592: how far the Geysermancer's Scald row and the Siege Master's Mark
## row look for a target. It is `CoreActions.CASTER_REACH`, so neither row can
## gate a cast at 200 while the spell it orders reaches 350.
const CASTER_REACH := 350.0

## Condition and targeting ops that need a status to already be on somebody.
## Only the positive ones: `enemy_lacks_status` is satisfied by an untouched
## enemy, so it is not a dependency.
const STATUS_REQUIRING_OPS := [&"enemy_has_status", &"target_enemy_with_status"]

## What a library row needs before it can do anything, and which rows in the
## same library supply it. Issue 434: the content already knows "Blast the
## burning" is inert until something applies BURN and nothing says so.
##
## Derived from the rows rather than authored beside them, so it cannot fall
## out of step with them. An empty `supplied_by` means the row still has a
## dependency and no row in this class satisfies it -- the fight does.
static func row_dependencies(class_id: StringName) -> Dictionary:
	var library := for_class(class_id)
	var out := {}
	for plan in library:
		var status := required_status(plan)
		if status < 0:
			continue
		var suppliers: Array[StringName] = []
		for other in library:
			if other.id != plan.id and applied_statuses(other).has(status):
				suppliers.append(other.id)
		out[plan.id] = {"status": status, "supplied_by": suppliers}
	return out

## The `CG.Status` this row's condition or targeting demands, or -1.
static func required_status(plan: Plan) -> int:
	var blocks: Array[PlanBlock] = []
	if plan.condition != null:
		blocks.append(plan.condition)
	blocks.append_array(plan.blocks)
	for b in blocks:
		if STATUS_REQUIRING_OPS.has(b.op) and b.args.has("status"):
			return int(b.args["status"])
	return -1

## Every `CG.Status` this row's own actions put on somebody.
static func applied_statuses(plan: Plan) -> Array[int]:
	var out: Array[int] = []
	for b in plan.blocks:
		if b.kind != PlanBlock.Kind.ACTION:
			continue
		var action: ActionDef = Registry.get_action(b.args.get("action_id", &""))
		if action != null and action.applies_status_enabled:
			out.append(int(action.applies_status))
	return out

## Total block count across a class's library. It is what adding every preset
## would cost, checked against Balance.plan_block_budget.
static func total_blocks(class_id: StringName) -> int:
	var total := 0
	for p in for_class(class_id):
		total += p.block_count()
	return total

static func for_class(class_id: StringName) -> Array[Plan]:
	match class_id:
		## Issue 433: Taunt leads. `DefaultBehavior` gates `_self_targeted_to_cast`
		## on `unit.pawn == null`, so a Warrior pawn never taunts, guards or blocks
		## on its own -- the shout is the loudest thing in the library that the
		## fallback cannot produce, and the one row folds in the old `always` one.
		&"warrior":
			return [
				_plan(&"warrior_taunt_when_they_close", "Taunt when they close",
					_condition(&"enemy_in_range", {"range": TAUNT_AT_RADIUS}),
					[_targeting(&"target_self"), _action_block(&"warrior_taunt")]),
				_plan(&"warrior_second_wind_when_hurt", "Second wind when hurt",
					_condition(&"self_hp_below_fraction", {"fraction": SECOND_WIND_ABOVE_FALLBACK}),
					[_targeting(&"target_self"), _action_block(&"warrior_second_wind")]),
				_plan(&"warrior_guard_when_hurt", "Guard when hurt",
					_condition(&"self_hp_below_fraction", {"fraction": 0.65}),
					[_targeting(&"target_self"), _action_block(&"warrior_guard")]),
				_plan(&"warrior_block_default", "Directional Block",
					_condition(&"always", {}),
					[_targeting(&"target_self"), _action_block(&"warrior_block")]),
			]
		# The player's own "one for speed, one for resistance" direction.
		&"priest":
			return [
				## Issue 433: 0.85, not 0.5. The fallback heals the same ally with the
				## same spell at 0.5, so the row only becomes an edit the player can
				## watch by firing on ticks the fallback would spend attacking.
				_plan(&"priest_heal_hurt_ally", "Heal before they break",
					_condition(&"ally_below_hp_fraction", {"fraction": HEAL_ABOVE_FALLBACK}),
					[_targeting(&"target_lowest_hp_fraction_ally"), _action_block(&"priest_heal")]),
				_plan(&"priest_ward_default", "Ward",
					_condition(&"self_resource_at_least", {"amount": PRIEST_SPENDER_RESERVE}),
					[_targeting(&"target_lowest_hp_fraction_ally"), _action_block(&"priest_ward")]),
				_plan(&"priest_haste_default", "Haste",
					_condition(&"self_resource_at_least", {"amount": PRIEST_SPENDER_RESERVE}),
					[_targeting(&"target_lowest_hp_fraction_ally"), _action_block(&"priest_haste")]),
				_plan(&"priest_smite_nearest", "Smite",
					_condition(&"self_resource_at_least", {"amount": PRIEST_SPENDER_RESERVE}),
					[_targeting(&"target_nearest_enemy"), _action_block(&"priest_smite")]),
				_plan(&"priest_channel_when_dry", "Channel when dry",
					_condition(&"self_resource_below", {"amount": CHANNEL_WHEN_BELOW}),
					[_targeting(&"target_self"), _action_block(&"channel_mana")]),
			]
		## Issue 406: the fire pair leads, because the library is priority order once
		## added and Scour is the least Geysermancer row in it. Blast stays above
		## Scald: swapping them is measured at 18 Blast casts against 481.
		&"geysermancer":
			return [
				_plan(&"geyser_blast_the_burning", "Blast the burning",
					_condition(&"enemy_has_status", {"status": CG.Status.BURN}),
					[_targeting(&"target_enemy_with_status", {"status": CG.Status.BURN}), _action_block(&"geyser_blast")]),
				_plan(&"geyser_scald_finisher", "Scald the weakest",
					_condition(&"enemy_in_range", {"range": CASTER_REACH}),
					[_targeting(&"target_lowest_hp_fraction_enemy"), _action_block(&"geyser_scald")]),
				_plan(&"geyser_scour_afflicted", "Scour the afflicted",
					_condition(&"ally_has_harmful_status", {}),
					[_targeting(&"target_ally_with_harmful_status"), _action_block(&"geyser_cleanse")]),
				_plan(&"geyser_channel_when_dry", "Channel when dry",
					_condition(&"self_resource_below", {"amount": CHANNEL_WHEN_BELOW}),
					[_targeting(&"target_self"), _action_block(&"channel_mana")]),
			]
		## Issue 432: Mark leads. `siege_engine_bolt` is marked-only, so an engine
		## built before anything carries MARKED has nothing to shoot at.
		&"siege_master":
			return [
				_plan(&"siege_master_mark_default", "Mark the target",
					_condition(&"enemy_in_range", {"range": CASTER_REACH}),
					[_targeting(&"target_nearest_enemy"), _action_block(&"spotter_mark")]),
				_plan(&"siege_master_build_when_ready", "Build the engine",
					_condition(&"self_resource_at_least", {"amount": 25}),
					[_targeting(&"target_self"), _action_block(&"build_siege_engine")]),
			]
		&"abomination":
			return [
				_plan(&"abomination_claw_the_unpoisoned", "Claw whoever is not poisoned",
					_condition(&"enemy_lacks_status", {"status": CG.Status.POISON}),
					[_targeting(&"target_enemy_without_status", {"status": CG.Status.POISON}), _action_block(&"abomination_claw")]),
				_plan(&"abomination_grapple_close", "Grapple",
					_condition(&"enemy_in_range", {"range": 45.0}),
					[_targeting(&"target_nearest_enemy"), _action_block(&"abomination_grapple")]),
				_plan(&"abomination_immolate_dump", "Immolate what is close but not gripped",
					_condition(&"enemy_in_range", {"range": 90.0}),
					[_targeting(&"target_self"), _action_block(&"abomination_immolate")]),
				_plan(&"abomination_hook_far", "Hook",
					_condition(&"enemy_in_range", {"range": 140.0}),
					[_targeting(&"target_nearest_enemy"), _action_block(&"abomination_hook")]),
			]
	return []

static func _plan(id: StringName, display_name: String, condition: PlanBlock, blocks: Array[PlanBlock]) -> Plan:
	var p := Plan.new()
	p.id = id
	p.display_name = display_name
	p.condition = condition
	p.blocks = blocks
	return p

static func _condition(op: StringName, args: Dictionary) -> PlanBlock:
	var b := PlanBlock.new()
	b.kind = PlanBlock.Kind.CONDITION
	b.op = op
	b.args = args
	return b

static func _targeting(op: StringName, args: Dictionary = {}) -> PlanBlock:
	var b := PlanBlock.new()
	b.kind = PlanBlock.Kind.TARGETING
	b.op = op
	b.args = args
	return b

static func _action_block(action_id: StringName) -> PlanBlock:
	var b := PlanBlock.new()
	b.kind = PlanBlock.Kind.ACTION
	b.op = &"use_action"
	b.args = {"action_id": action_id}
	return b
