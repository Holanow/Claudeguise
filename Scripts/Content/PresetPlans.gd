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

## Total block count across a class's library. It is what adding every preset
## would cost, checked against Balance.plan_block_budget.
static func total_blocks(class_id: StringName) -> int:
	var total := 0
	for p in for_class(class_id):
		total += p.block_count()
	return total

static func for_class(class_id: StringName) -> Array[Plan]:
	match class_id:
		&"warrior":
			return [
				_plan(&"warrior_second_wind_when_critical", "Second wind when critical",
					_condition(&"self_hp_below_fraction", {"fraction": 0.35}),
					[_targeting(&"target_self"), _action_block(&"warrior_second_wind")]),
				_plan(&"warrior_guard_when_hurt", "Guard when hurt",
					_condition(&"self_hp_below_fraction", {"fraction": 0.65}),
					[_targeting(&"target_self"), _action_block(&"warrior_guard")]),
				_plan(&"warrior_taunt_default", "Taunt",
					_condition(&"always", {}),
					[_targeting(&"target_self"), _action_block(&"warrior_taunt")]),
				_plan(&"warrior_block_default", "Directional Block",
					_condition(&"always", {}),
					[_targeting(&"target_self"), _action_block(&"warrior_block")]),
				_plan(&"warrior_execute_finisher", "Execute",
					_condition(&"self_resource_at_least", {"amount": 40}),
					[_targeting(&"target_nearest_enemy"), _action_block(&"warrior_execute")]),
			]
		# The player's own "one for speed, one for resistance" direction.
		&"priest":
			return [
				_plan(&"priest_heal_hurt_ally", "Heal the hurt",
					_condition(&"ally_below_hp_fraction", {"fraction": 0.5}),
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
					_condition(&"enemy_in_range", {"range": 200.0}),
					[_targeting(&"target_lowest_hp_fraction_enemy"), _action_block(&"geyser_scald")]),
				_plan(&"geyser_scour_afflicted", "Scour the afflicted",
					_condition(&"ally_has_harmful_status", {}),
					[_targeting(&"target_ally_with_harmful_status"), _action_block(&"geyser_cleanse")]),
				_plan(&"geyser_channel_when_dry", "Channel when dry",
					_condition(&"self_resource_below", {"amount": CHANNEL_WHEN_BELOW}),
					[_targeting(&"target_self"), _action_block(&"channel_mana")]),
			]
		&"siege_master":
			return [
				_plan(&"siege_master_build_when_ready", "Build the engine",
					_condition(&"self_resource_at_least", {"amount": 25}),
					[_targeting(&"target_self"), _action_block(&"build_siege_engine")]),
				_plan(&"siege_master_mark_default", "Mark the target",
					_condition(&"enemy_in_range", {"range": 220.0}),
					[_targeting(&"target_nearest_enemy"), _action_block(&"spotter_mark")]),
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
