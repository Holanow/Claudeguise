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

## The `CG.Status` this row's condition or targeting demands, or -1. Only the
## positive ops count: `EnemyLacksStatusBlock` is satisfied by an untouched
## enemy, so it is not a dependency.
static func required_status(plan: Plan) -> int:
	var blocks: Array[PlanBlock] = []
	if plan.condition != null:
		blocks.append(plan.condition)
	blocks.append_array(plan.blocks)
	for b in blocks:
		if b is EnemyHasStatusBlock:
			return int((b as EnemyHasStatusBlock).status)
		if b is TargetEnemyWithStatusBlock:
			return int((b as TargetEnemyWithStatusBlock).status)
	return -1

## Every `CG.Status` this row's own actions put on somebody.
static func applied_statuses(plan: Plan) -> Array[int]:
	var out: Array[int] = []
	for b in plan.blocks:
		if not (b is UseActionBlock):
			continue
		var action: ActionDef = (b as UseActionBlock).action
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
					_enemy_in_range(TAUNT_AT_RADIUS),
					[TargetSelfBlock.new(), _use(&"warrior_taunt")]),
				_plan(&"warrior_second_wind_when_hurt", "Second wind when hurt",
					_self_hp_below(SECOND_WIND_ABOVE_FALLBACK),
					[TargetSelfBlock.new(), _use(&"warrior_second_wind")]),
				_plan(&"warrior_guard_when_hurt", "Guard when hurt",
					_self_hp_below(0.65),
					[TargetSelfBlock.new(), _use(&"warrior_guard")]),
				## Issue 593: the row NAMES THE ALLY, which is the whole point.
				## `target_self` here would be the invisible auto-pick the
				## pawn-behaviour principle forbids -- the player must be able to
				## see, and change, who the Warrior puts itself in front of.
				_plan(&"warrior_block_default", "Cover the weakest ally",
					AlwaysBlock.new(),
					[TargetLowestHpAllyBlock.new(), _use(&"warrior_block")]),
			]
		# The player's own "one for speed, one for resistance" direction.
		&"priest":
			return [
				## Issue 433: 0.85, not 0.5. The fallback heals the same ally with the
				## same spell at 0.5, so the row only becomes an edit the player can
				## watch by firing on ticks the fallback would spend attacking.
				_plan(&"priest_heal_hurt_ally", "Heal before they break",
					_ally_hp_below(HEAL_ABOVE_FALLBACK),
					[TargetLowestHpAllyBlock.new(), _use(&"priest_heal")]),
				_plan(&"priest_ward_default", "Ward",
					_resource_at_least(PRIEST_SPENDER_RESERVE),
					[TargetLowestHpAllyBlock.new(), _use(&"priest_ward")]),
				_plan(&"priest_haste_default", "Haste",
					_resource_at_least(PRIEST_SPENDER_RESERVE),
					[TargetLowestHpAllyBlock.new(), _use(&"priest_haste")]),
				_plan(&"priest_smite_nearest", "Smite",
					_resource_at_least(PRIEST_SPENDER_RESERVE),
					[TargetNearestEnemyBlock.new(), _use(&"priest_smite")]),
				_plan(&"priest_channel_when_dry", "Channel when dry",
					_resource_below(CHANNEL_WHEN_BELOW),
					[TargetSelfBlock.new(), _use(&"channel_mana")]),
			]
		## Issue 406: the fire pair leads, because the library is priority order once
		## added and Scour is the least Geysermancer row in it. Blast stays above
		## Scald: swapping them is measured at 18 Blast casts against 481.
		&"geysermancer":
			return [
				_plan(&"geyser_blast_the_burning", "Blast the burning",
					_enemy_has(CG.Status.BURN),
					[_target_enemy_with(CG.Status.BURN), _use(&"geyser_blast")]),
				_plan(&"geyser_scald_finisher", "Scald the weakest",
					_enemy_in_range(CASTER_REACH),
					[TargetLowestHpEnemyBlock.new(), _use(&"geyser_scald")]),
				_plan(&"geyser_scour_afflicted", "Scour the afflicted",
					AllyHasHarmfulStatusBlock.new(),
					[TargetAfflictedAllyBlock.new(), _use(&"geyser_cleanse")]),
				_plan(&"geyser_channel_when_dry", "Channel when dry",
					_resource_below(CHANNEL_WHEN_BELOW),
					[TargetSelfBlock.new(), _use(&"channel_mana")]),
			]
		## Issue 432: Mark leads. `siege_engine_bolt` is marked-only, so an engine
		## built before anything carries MARKED has nothing to shoot at.
		&"siege_master":
			return [
				_plan(&"siege_master_mark_default", "Mark the target",
					_enemy_in_range(CASTER_REACH),
					[TargetNearestEnemyBlock.new(), _use(&"spotter_mark")]),
				_plan(&"siege_master_build_when_ready", "Build the engine",
					_resource_at_least(25),
					[TargetSelfBlock.new(), _use(&"build_siege_engine")]),
			]
		&"abomination":
			return [
				_plan(&"abomination_claw_the_unpoisoned", "Claw whoever is not poisoned",
					_enemy_lacks(CG.Status.POISON),
					[_target_enemy_without(CG.Status.POISON), _use(&"abomination_claw")]),
				_plan(&"abomination_grapple_close", "Grapple",
					_enemy_in_range(45.0),
					[TargetNearestEnemyBlock.new(), _use(&"abomination_grapple")]),
				_plan(&"abomination_immolate_dump", "Immolate what is close but not gripped",
					_enemy_in_range(90.0),
					[TargetSelfBlock.new(), _use(&"abomination_immolate")]),
				_plan(&"abomination_hook_far", "Hook",
					_enemy_in_range(140.0),
					[TargetNearestEnemyBlock.new(), _use(&"abomination_hook")]),
			]
	return []

static func _plan(id: StringName, display_name: String, condition: ConditionBlock, blocks: Array[PlanBlock]) -> Plan:
	var p := Plan.new()
	p.id = id
	p.display_name = display_name
	p.condition = condition
	p.blocks = blocks
	return p

# Builders for the blocks that carry an operand. A block with no operand is
# constructed at the call site, because `TargetSelfBlock.new()` already says
# everything a helper would.

## Issue 658: PresetPlans still writes an action out by its readable id, and
## resolves it once at build time rather than storing the id in the block.
static func _use(action_id: StringName) -> UseActionBlock:
	var b := UseActionBlock.new()
	b.action = ActionLibrary.get_action(action_id)
	return b

static func _enemy_in_range(units: float) -> EnemyInRangeBlock:
	var b := EnemyInRangeBlock.new()
	b.range_units = units
	return b

static func _self_hp_below(fraction: float) -> SelfHpBelowBlock:
	var b := SelfHpBelowBlock.new()
	b.fraction = fraction
	return b

static func _ally_hp_below(fraction: float) -> AllyHpBelowBlock:
	var b := AllyHpBelowBlock.new()
	b.fraction = fraction
	return b

static func _resource_at_least(amount: int) -> SelfResourceAtLeastBlock:
	var b := SelfResourceAtLeastBlock.new()
	b.amount = amount
	return b

static func _resource_below(amount: int) -> SelfResourceBelowBlock:
	var b := SelfResourceBelowBlock.new()
	b.amount = amount
	return b

static func _enemy_has(status: CG.Status) -> EnemyHasStatusBlock:
	var b := EnemyHasStatusBlock.new()
	b.status = status
	return b

static func _enemy_lacks(status: CG.Status) -> EnemyLacksStatusBlock:
	var b := EnemyLacksStatusBlock.new()
	b.status = status
	return b

static func _target_enemy_with(status: CG.Status) -> TargetEnemyWithStatusBlock:
	var b := TargetEnemyWithStatusBlock.new()
	b.status = status
	return b

static func _target_enemy_without(status: CG.Status) -> TargetEnemyWithoutStatusBlock:
	var b := TargetEnemyWithoutStatusBlock.new()
	b.status = status
	return b
