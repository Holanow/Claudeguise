extends RefCounted
class_name PresetPlans


## Preset plans, shipped on the pawn per issue 2. No editor, no
## UI: issue 3 displays these read-only. Each is deliberately a specialty
## override rather than an always-fire attack, so DefaultBehavior is what most

## Issue 138: the Mana a Priest's lower plans must leave standing, so the heal
## above them can still be paid for. `priest_heal` costs 25 and Ward, Haste and
## Smite each cost 15, so 40 is "my own cost, plus the heal's, or I do not cast".
const PRIEST_SPENDER_RESERVE := 40

## Total block count across a class's preset plans. Used by
## Tests/test_content_classes.gd to check every class stays within its own
## Balance.plan_block_budget.
static func total_blocks(class_id: StringName) -> int:
	var total := 0
	for p in for_class(class_id):
		total += p.block_count()
	return total

static func for_class(class_id: StringName) -> Array[Plan]:
	match class_id:
		## Issue 30: warrior_execute_when_raging replaced by
		## warrior_taunt_default rather than added alongside it --
		## "two preset plans per class" (this file's own header) is a
		&"warrior":
			return [
				# Issue 99: replaces `warrior_block_default`, which went with
				# Block onto `plate_mail` (issue 100). Same slot in the
				# budget, so WIS stays at 8.
				_plan(&"warrior_second_wind_when_critical", "Second wind when critical",
					_condition(&"self_hp_below_fraction", {"fraction": 0.35}),
					[_targeting(&"target_self"), _action_block(&"warrior_second_wind")]),
				_plan(&"warrior_guard_when_hurt", "Guard when hurt",
					_condition(&"self_hp_below_fraction", {"fraction": 0.65}),
					[_targeting(&"target_self"), _action_block(&"warrior_guard")]),
				_plan(&"warrior_taunt_default", "Taunt",
					_condition(&"always", {}),
					[_targeting(&"target_self"), _action_block(&"warrior_taunt")]),
				# Issue 79: fourth plan, and the restoration of the one issue
				# 30 deleted. Its own note above says Execute "is not gone from
				# the class" because it stays in starting_actions and a player
				_plan(&"warrior_block_default", "Directional Block",
					_condition(&"always", {}),
					[_targeting(&"target_self"), _action_block(&"warrior_block")]),
				_plan(&"warrior_execute_finisher", "Execute",
					_condition(&"self_resource_at_least", {"amount": 40}),
					[_targeting(&"target_nearest_enemy"), _action_block(&"warrior_execute")]),
			]
		# The player's own "one for speed, one for resistance" direction.
		# Both use `target_lowest_hp_fraction_ally` -- the same targeting op
		# `priest_heal_hurt_ally` already uses, and the only ally-picking op
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
			]
		# Issue 79: geyser_scald fired zero times in 210 real fights, and the
		# action was never the problem -- its plan was strictly dominated by
		# the one above it, in a way no amount of tuning could have reached.
		&"geysermancer":
			return [
				_plan(&"geyser_scour_afflicted", "Scour the afflicted",
					_condition(&"ally_has_harmful_status", {}),
					[_targeting(&"target_ally_with_harmful_status"), _action_block(&"geyser_cleanse")]),
				## Issue 181: **Blast is now the payoff of a combo rather than a
				## high-Mana opener, and the order is the whole fix.**
				_plan(&"geyser_blast_the_burning", "Blast the burning",
					_condition(&"enemy_has_status", {"status": CG.Status.BURN}),
					[_targeting(&"target_enemy_with_status", {"status": CG.Status.BURN}), _action_block(&"geyser_blast")]),
				_plan(&"geyser_scald_finisher", "Scald the weakest",
					_condition(&"enemy_in_range", {"range": 200.0}),
					[_targeting(&"target_lowest_hp_fraction_enemy"), _action_block(&"geyser_scald")]),
			]
		## Issue 12: rebuilt for spotter/engineer. Build first: Mana starts
		## full (50 for this class's spread) and the action costs 40, so
		## `self_resource_at_least: 45` fires it once near the start of a
		## fight and then blocks a repeat until Mana has regenerated most of
		## the way back -- the resource economy is the gate, same reasoning
		## as the action's own comment. spotter_mark is the fallback for
		## every tick that condition does not hold, at its own action range.
		&"siege_master":
			return [
				_plan(&"siege_master_build_when_ready", "Build the engine",
					_condition(&"self_resource_at_least", {"amount": 25}),
					[_targeting(&"target_self"), _action_block(&"build_siege_engine")]),
				_plan(&"siege_master_mark_default", "Mark the target",
					_condition(&"enemy_in_range", {"range": 220.0}),
					[_targeting(&"target_nearest_enemy"), _action_block(&"spotter_mark")]),
			]
		# Issue 52: rebuilt for the hook and grapple. Order matters here in a
		# way it did not for the retired pair -- both old plans fired on the
		# same 45-unit condition, so only list order broke the tie. These
		&"abomination":
			return [
				## **Issue 206: Claw, and the first version of this row was wrong.**
				## The Sickle grants Claw and Claw fired **zero** times -- a weapon
				## granting an action that can never fire, this project's oldest
				_plan(&"abomination_claw_the_unpoisoned", "Claw whoever is not poisoned",
					_condition(&"enemy_lacks_status", {"status": CG.Status.POISON}),
					[_targeting(&"target_enemy_without_status", {"status": CG.Status.POISON}), _action_block(&"abomination_claw")]),
				_plan(&"abomination_grapple_close", "Grapple",
					_condition(&"enemy_in_range", {"range": 45.0}),
					[_targeting(&"target_nearest_enemy"), _action_block(&"abomination_grapple")]),
				## **Issue 219: Immolate, and this row is the only reason
				## `SUSTAIN_START` and `SUSTAIN_END` ever happen.** swift built
				## the channel in #61 and deliberately left every action inert;
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
