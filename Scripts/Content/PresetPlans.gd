extends RefCounted

const Plan := preload("res://Scripts/Core/Plan.gd")
const PlanBlock := preload("res://Scripts/Core/PlanBlock.gd")

## Preset plans, shipped on the pawn per issue 2. No editor, no
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
		## Issue 30, second pass: warrior_guard_when_hurt's own threshold,
		## 0.35 -> 0.65. Traced why CON alone (starting_classes.gd's own
		## comment has the sweep) never fixed anything: The Warden's axe
		## does a fixed 139 raw every ~42 ticks (no variance -- enemies
		## read attack power straight off EnemyDef, not through Balance's
		## pawn-only roll), and two of those in a row always crossed a
		## fixed 35% threshold, however large the pool behind it, because
		## raising max hp raises what "35%" means by the same proportion.
		## Guard could never fire before the second hit landed, so it was
		## never actually protecting the Warrior from the swing that
		## mattered -- only from swings after the pool was already mostly
		## gone. Measured directly (a throwaway probe against a real fight,
		## not committed): at 0.35, hits 1 and 2 both land before Guard's
		## first cast; at 0.65, Guard fires immediately after hit 1 and hit
		## 2 is already mitigated. Took no_geysermancer and no_priest from
		## 14/20 and 17/20 to a clean 20/20 apiece.
		&"warrior":
			return [
				_plan(&"warrior_guard_when_hurt", "Guard when hurt",
					_condition(&"self_hp_below_fraction", {"fraction": 0.65}),
					[_targeting(&"target_self"), _action_block(&"warrior_guard")]),
				_plan(&"warrior_taunt_default", "Taunt",
					_condition(&"always", {}),
					[_targeting(&"target_self"), _action_block(&"warrior_taunt")]),
				# Issue 52: third plan, after guard and taunt -- SHIELDING
				# had nothing to intercept before shots travelled (issue 18)
				# and no path from the game to a player even with the
				# mechanism live, since the plan editor is deferred and a
				# preset plan is therefore the only way this ability ever
				# fires. `always`, same shape as taunt: taunt's own
				# cooldown_ticks equals its duration_ticks, so its plan sits
				# on cooldown (condition holds, action unaffordable) for
				# nearly all of its own uptime once cast -- decide()'s own
				# fallthrough (PlanInterpreter.gd: a plan whose action isn't
				# affordable falls through to the next one, not to
				# DefaultBehavior) is what lets this plan actually win a
				# real decide() tick instead of sitting permanently behind
				# taunt. starting_classes.gd's own WIS 4->6 note explains
				# why a third plan needed a budget change too.
				_plan(&"warrior_block_default", "Directional Block",
					_condition(&"always", {}),
					[_targeting(&"target_self"), _action_block(&"warrior_block")]),
				# Issue 79: fourth plan, and the restoration of the one issue
				# 30 deleted. Its own note above says Execute "is not gone from
				# the class" because it stays in starting_actions and a player
				# could wire it through the plan editor -- both halves of that
				# turned out to be false in practice. The plan editor is still
				# deferred, and `DefaultBehavior` never picks Execute anyway:
				# with no ranged action anywhere in the Warrior's kit,
				# `_choose_attack_action` falls to `_first_non_heal`, which
				# returns warrior_strike every time. So Execute fired exactly
				# zero times in 210 real fights (rook's
				# Tests/test_integration_reach.gd, issue 79) and no test
				# noticed for the whole of its existence.
				#
				# `self_resource_at_least: 40` is the whole Rage pool
				# (`Balance.max_resource` gives this class exactly 40), so
				# Execute fires only from a full bar and leaves exactly 20
				# behind -- one warrior_guard, which is what this class most
				# needs its Rage for. That is a tidier economy and, measured,
				# not a fix for the Warden regression this plan causes -- see
				# warrior_execute's own comment in core_actions.gd for the
				# probe that killed that hypothesis.
				#
				# Last rather than first, so it never starves guard, taunt or
				# block, all three of which are free or cheap.
				# `target_nearest_enemy` and not the lowest-hp enemy: this is a
				# melee action at 40 range, and the weakest enemy in the room is
				# usually not the one the Warrior is standing next to, so
				# targeting it would fail `_target_in_range` and fall through
				# every time.
				_plan(&"warrior_execute_finisher", "Execute",
					_condition(&"self_resource_at_least", {"amount": 40}),
					[_targeting(&"target_nearest_enemy"), _action_block(&"warrior_execute")]),
			]
		# The player's own "one for speed, one for resistance" direction.
		# Both use `target_lowest_hp_fraction_ally` -- the same targeting op
		# `priest_heal_hurt_ally` already uses, and the only ally-picking op
		# `PlanInterpreter` whitelists -- so both buffs land on whichever
		# ally is under the most pressure right now, a defensible read for a
		# SUPPORT-tagged class and one that needs no new targeting op.
		#
		# Ordered heal, ward, haste, smite: a hurt ally always outranks a
		# buff (heal's own condition is checked first), and both buffs use
		# `always` rather than a threshold, so whichever is off cooldown
		# fires ahead of Smite -- `priest_ward`/`priest_haste`'s own cooldown
		# matches their duration (see `_action_ally_buff`'s comment in
		# core_actions.gd), so this recasts the instant the buff lapses
		# rather than spamming every tick, the same fallthrough shape
		# `warrior_block_default` already established. Ward before haste,
		# arbitrarily -- a plan whose action is on cooldown falls through to
		# the next one exactly like an unaffordable one does, so the loser of
		# this ordering still fires as soon as the winner is on cooldown.
		&"priest":
			return [
				_plan(&"priest_heal_hurt_ally", "Heal the hurt",
					_condition(&"ally_below_hp_fraction", {"fraction": 0.5}),
					[_targeting(&"target_lowest_hp_fraction_ally"), _action_block(&"priest_heal")]),
				_plan(&"priest_ward_default", "Ward",
					_condition(&"always", {}),
					[_targeting(&"target_lowest_hp_fraction_ally"), _action_block(&"priest_ward")]),
				_plan(&"priest_haste_default", "Haste",
					_condition(&"always", {}),
					[_targeting(&"target_lowest_hp_fraction_ally"), _action_block(&"priest_haste")]),
				_plan(&"priest_smite_nearest", "Smite",
					_condition(&"enemy_in_range", {"range": 220.0}),
					[_targeting(&"target_nearest_enemy"), _action_block(&"priest_smite")]),
			]
		# Issue 79: geyser_scald fired zero times in 210 real fights, and the
		# action was never the problem -- its plan was strictly dominated by
		# the one above it, in a way no amount of tuning could have reached.
		#
		# The old pair: Blast first on `enemy_in_range: 200`, costing 20 Mana;
		# Scald second on `self_resource_at_least: 40`, costing 15. Every Mana
		# level at which Scald was affordable was one at which Blast was
		# affordable too, and Blast's condition is checked first, so the only
		# case that could ever reach Scald was "no enemy within 200" -- and both
		# actions have the same 200 range, so
		# `PlanInterpreter._target_in_range` declined it there as well. The
		# window was not small, it was empty: a throwaway probe (not committed)
		# stepping three real encounters tick by tick counted 0 ticks out of
		# 1043 in which Scald could fire at all.
		#
		# Rebuilt as a descending Mana ladder rather than by nudging the
		# threshold, so each of this class's three actions owns a window
		# nothing above it can take:
		#
		#   >= 60      Geyser Blast, the splash, 20 Mana
		#   15 .. 59   Scald, the focused burst, 15 Mana
		#   < 15       Spout, the free basic attack, via DefaultBehavior
		#
		# That also matches what the two spells are for: the expensive splash is
		# what a full pool buys, and as it drains the class falls back to
		# hitting one target properly, then to something free rather than to
		# standing still. Blast's own `enemy_in_range` condition is gone rather
		# than moved -- `_target_in_range` already checks the resolved target
		# against the action's own 200 range (this file's own header), so that
		# clause was doing nothing the structural check was not already doing,
		# and keeping it would only have hidden the resource gate behind a
		# second condition.
		&"geysermancer":
			return [
				_plan(&"geyser_blast_cluster", "Blast a cluster",
					_condition(&"self_resource_at_least", {"amount": 60}),
					[_targeting(&"target_nearest_enemy"), _action_block(&"geyser_blast")]),
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
		# two conditions are deliberately different ranges (45, then 140)
		# so the earlier, narrower one wins whenever it can: a target
		# already at melee range gets grappled (SLOWED, so it cannot walk
		# back out) rather than hooked again for no reason; only a target
		# still outside grapple's own reach gets hooked, which drags it in
		# for grapple to catch on the following action. A hooked target
		# that later escapes back past 45 units re-triggers the hook plan
		# instead of the grapple one, same fallthrough logic, so the loop
		# self-corrects rather than needing a third condition.
		&"abomination":
			return [
				_plan(&"abomination_grapple_close", "Grapple",
					_condition(&"enemy_in_range", {"range": 45.0}),
					[_targeting(&"target_nearest_enemy"), _action_block(&"abomination_grapple")]),
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
