extends RefCounted
class_name BlockCatalog

## Op name -> block script, and **the only place a name is turned into a block.**
## It replaces the five whitelists and three shape tables `PlanInterpreter`
## used to carry: the script is the whitelist, its exported fields are the args.
##
## Insertion order is the order the plan editor offers them in, and it is the
## order the deleted whitelists had. A dictionary keeps its insertion order in
## GDScript; do not sort these.

const CONDITIONS := {
	&"always": preload("res://Scripts/Plans/Blocks/AlwaysBlock.gd"),
	&"self_hp_below_fraction": preload("res://Scripts/Plans/Blocks/SelfHpBelowBlock.gd"),
	&"ally_below_hp_fraction": preload("res://Scripts/Plans/Blocks/AllyHpBelowBlock.gd"),
	&"self_resource_at_least": preload("res://Scripts/Plans/Blocks/SelfResourceAtLeastBlock.gd"),
	&"self_resource_at_least_fraction": preload("res://Scripts/Plans/Blocks/SelfResourceAtLeastFractionBlock.gd"),
	&"self_resource_below": preload("res://Scripts/Plans/Blocks/SelfResourceBelowBlock.gd"),
	&"enemy_in_range": preload("res://Scripts/Plans/Blocks/EnemyInRangeBlock.gd"),
	&"ally_has_harmful_status": preload("res://Scripts/Plans/Blocks/AllyHasHarmfulStatusBlock.gd"),
	&"enemy_has_status": preload("res://Scripts/Plans/Blocks/EnemyHasStatusBlock.gd"),
	&"enemy_lacks_status": preload("res://Scripts/Plans/Blocks/EnemyLacksStatusBlock.gd"),
	&"self_on_harmful_ground": preload("res://Scripts/Plans/Blocks/SelfOnHarmfulGroundBlock.gd"),
	&"self_on_safe_ground": preload("res://Scripts/Plans/Blocks/SelfOnSafeGroundBlock.gd"),
	&"self_in_cover": preload("res://Scripts/Plans/Blocks/SelfInCoverBlock.gd"),
	&"self_not_in_cover": preload("res://Scripts/Plans/Blocks/SelfNotInCoverBlock.gd"),
	&"enemy_is_focused": preload("res://Scripts/Plans/Blocks/EnemyIsFocusedBlock.gd"),
}

const TARGETING := {
	&"target_nearest_enemy": preload("res://Scripts/Plans/Blocks/TargetNearestEnemyBlock.gd"),
	&"target_lowest_hp_fraction_ally": preload("res://Scripts/Plans/Blocks/TargetLowestHpAllyBlock.gd"),
	&"target_lowest_hp_fraction_enemy": preload("res://Scripts/Plans/Blocks/TargetLowestHpEnemyBlock.gd"),
	&"target_self": preload("res://Scripts/Plans/Blocks/TargetSelfBlock.gd"),
	&"target_ally_with_harmful_status": preload("res://Scripts/Plans/Blocks/TargetAfflictedAllyBlock.gd"),
	&"target_enemy_with_status": preload("res://Scripts/Plans/Blocks/TargetEnemyWithStatusBlock.gd"),
	&"target_enemy_without_status": preload("res://Scripts/Plans/Blocks/TargetEnemyWithoutStatusBlock.gd"),
	&"target_focused_enemy": preload("res://Scripts/Plans/Blocks/TargetFocusedEnemyBlock.gd"),
}

const MOVEMENT := {
	&"keep_distance": preload("res://Scripts/Plans/Blocks/KeepDistanceBlock.gd"),
	&"move_into_cover": preload("res://Scripts/Plans/Blocks/MoveIntoCoverBlock.gd"),
	&"leave_harmful_ground": preload("res://Scripts/Plans/Blocks/LeaveHarmfulGroundBlock.gd"),
}

## The picker orders, derived so a name cannot be in the map and missing here.
static var CONDITION_OPS: Array = CONDITIONS.keys()
static var TARGETING_OPS: Array = TARGETING.keys()
static var MOVEMENT_OPS: Array = MOVEMENT.keys()

static func condition(op: StringName) -> ConditionBlock:
	return CONDITIONS[op].new()

static func targeting(op: StringName) -> TargetingBlock:
	return TARGETING[op].new()

static func movement(op: StringName) -> MovementBlock:
	return MOVEMENT[op].new()

## The name a block goes by, for the tests and the instruments. Display never
## reads this -- `block.describe()` is the sentence a player sees.
static func op_of(block: PlanBlock) -> StringName:
	if block == null:
		return &""
	var script: Script = block.get_script()
	for table in [CONDITIONS, TARGETING, MOVEMENT]:
		for op in table:
			if table[op] == script:
				return op
	return &""
