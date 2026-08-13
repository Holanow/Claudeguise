extends RefCounted

const Plan := preload("res://Scripts/Core/Plan.gd")
const PlanBlock := preload("res://Scripts/Core/PlanBlock.gd")

## Two preset plans per class, shipped on the pawn per issue 2. No editor, no
## UI: issue 3 displays these read-only. Each is deliberately a specialty
## override rather than an always-fire attack, so DefaultBehavior is what most
## of a fight actually looks like, per README.md's "a player should not have
## to touch the plan system" — these are the exceptions, not the rule.
##
## Most of these conditions are not bare `always`. An ACTION block has no
## notion of range or movement — that logic lives only in DefaultBehavior —
## so a plan that fires unconditionally at a target still out of range makes
## the pawn stand still and whiff forever instead of closing the distance.
## `enemy_in_range` keyed to the action's own range makes a plan preempt
## DefaultBehavior only once it would already have moved into position,
## which is exactly when overriding its target choice is worth doing. Found
## by running an actual fight and watching a Siege Master never leave its
## spawn point.
##
## The one exception (issue 30's `warrior_taunt_default`) is safe from that
## exact failure by construction rather than by luck: a self-targeted,
## 0-range action is always "in range" of its own caster regardless of
## position, so `always` never strands it the way it would strand an
## enemy-targeted one. `build_siege_engine`'s plan is the same shape
## (self-targeted, range 0) and could have used `always` too; it happens to
## gate on Mana instead because the resource check is also doing real work
## there.
##
## Every plan here uses only the ops PlanInterpreter.gd whitelists. Total
## blocks per class must not exceed Balance.plan_block_budget for that class's
## WIS; Tests/test_content_classes.gd checks this so a future class or plan
## addition cannot silently blow the budget.
##
## Five plans here used to disagree with their own action's range, found by
## rook's Tools/PlanRangeAudit.gd and by issue 14's playtest (a Geysermancer
## firing six times and connecting once). Two were a plain number mismatch,
## fixed here. The other three had no range check at all on the target their
## targeting block actually picks — fixed structurally instead, in
## PlanInterpreter._target_in_range (issue 14a): it checks the resolved
## target's distance against the firing action's own range right before
## building the intent, so no plan here needs its own range condition to stay
## safe, and neither does any plan added after this one.
##
## OWNER: teal.

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
		## real, tested invariant (test_content_classes.gd asserts
		## exactly 2), not a soft guideline, and a third plan blew both
		## that and the WIS-based block budget. Execute is not gone from
		## the class: it stays in warrior_strike/warrior_guard/
		## warrior_execute/warrior_taunt (starting_classes.gd) and a
		## player can wire its own condition through the plan editor
		## (issue 6, since merged) if they want the Rage-dump behaviour
		## back automatically -- it just is not preset any more.
		## warrior_strike itself has never had a preset plan either,
		## relying entirely on the DefaultBehavior fallback the same way
		## it always has; losing Execute's preset does not touch that.
		## `always` as the condition, not a self-missing-status check --
		## warrior_taunt's own cooldown_ticks equals its duration_ticks,
		## so `_can_afford` (cooldown gate) already makes this fall
		## through to DefaultBehavior for every tick it is still active,
		## with no new condition op needed.
		&"warrior":
			return [
				_plan(&"warrior_guard_when_hurt", "Guard when hurt",
					_condition(&"self_hp_below_fraction", {"fraction": 0.35}),
					[_targeting(&"target_self"), _action_block(&"warrior_guard")]),
				_plan(&"warrior_taunt_default", "Taunt",
					_condition(&"always", {}),
					[_targeting(&"target_self"), _action_block(&"warrior_taunt")]),
			]
		&"priest":
			return [
				_plan(&"priest_heal_hurt_ally", "Heal the hurt",
					_condition(&"ally_below_hp_fraction", {"fraction": 0.5}),
					[_targeting(&"target_lowest_hp_fraction_ally"), _action_block(&"priest_heal")]),
				_plan(&"priest_smite_nearest", "Smite",
					_condition(&"enemy_in_range", {"range": 220.0}),
					[_targeting(&"target_nearest_enemy"), _action_block(&"priest_smite")]),
			]
		&"geysermancer":
			return [
				_plan(&"geyser_blast_cluster", "Blast a cluster",
					_condition(&"enemy_in_range", {"range": 200.0}),
					[_targeting(&"target_nearest_enemy"), _action_block(&"geyser_blast")]),
				_plan(&"geyser_scald_finisher", "Scald the weakest",
					_condition(&"self_resource_at_least", {"amount": 40}),
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
		&"abomination":
			return [
				_plan(&"abomination_immolate_when_close", "Immolate",
					_condition(&"enemy_in_range", {"range": 45.0}),
					[_targeting(&"target_nearest_enemy"), _action_block(&"abomination_immolate")]),
				_plan(&"abomination_claw_default", "Claw",
					_condition(&"enemy_in_range", {"range": 45.0}),
					[_targeting(&"target_nearest_enemy"), _action_block(&"abomination_claw")]),
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
