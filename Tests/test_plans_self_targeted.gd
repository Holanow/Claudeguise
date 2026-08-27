extends "res://Tests/TestCase.gd"


## Issue 150. **A self-targeted action had no path through `DefaultBehavior`, and
## the units that need one have no plans at all.**
##
## `decide()` picks a target from the opposing team and measures the action's
## range against it, so an action aimed at its own caster could never fire from
## this file. `PlanInterpreter` has a `target_self` block and every pawn has
## plans; nothing in the bestiary does. That is why floor 1's "big heavy guy that
## stuns units and taunts" shipped with a stun and no taunt.

const ROAR := &"brute_roar"

func _unit(id: int, team: CG.Team, pos: Vector2, actions: Array[StringName]) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.position = pos
	u.hp_max = 100
	u.hp = 100
	u.move_speed = 2.0
	u.resource_kind = CG.ResourceKind.ENERGY
	u.resource_max = 100
	u.resource = 100
	u.actions = actions
	return u

func _decide(unit: CombatUnit, enemy_at: float) -> Intent:
	var enemy := _unit(1, CG.Team.ENEMY, Vector2(enemy_at, 0.0), [&"goblin_stab"])
	var state := CombatState.new(0)
	state.units.append(unit)
	state.units.append(enemy)
	return DefaultBehavior.decide(state, unit)

# ---------------------------------------------------------------------------
# it fires, and it is aimed at the caster
# ---------------------------------------------------------------------------

func test_a_unit_with_no_plans_casts_its_self_targeted_action_on_itself() -> void:
	var brute := _unit(0, CG.Team.PLAYER, Vector2.ZERO, [ROAR, &"brute_slam"])
	var intent := _decide(brute, 150.0)
	assert_eq(intent.kind, CG.IntentKind.USE_ACTION, "it should act rather than walk")
	assert_eq(intent.action_id, ROAR, "the roar is the action")
	assert_eq(intent.target_id, brute.id, "and it is aimed at the caster, not at the enemy")

## The reach rule, both halves. `brute_roar` states a `taunt_radius` of 200, so
## an enemy at 250 is outside it and the Brute has nothing to shout at yet -- it
## should fall through to closing with its slam rather than spending the cast.
func test_the_roar_waits_until_something_is_inside_its_own_radius() -> void:
	var brute := _unit(0, CG.Team.PLAYER, Vector2.ZERO, [ROAR, &"brute_slam"])
	var intent := _decide(brute, 250.0)
	assert_ne(intent.action_id, ROAR, "nothing is inside 200 units yet")
	assert_eq(intent.kind, CG.IntentKind.MOVE_TO, "so it closes, which is what it did before this branch existed")

## A self-buff with no radius of its own braces when the fight is inside the
## unit's own longest reach. `warrior_guard` states no `taunt_radius`, and this
## unit's only attack is `goblin_stab` at 40 units.
func test_a_self_buff_with_no_radius_uses_the_units_own_reach() -> void:
	var near := _unit(0, CG.Team.PLAYER, Vector2.ZERO, [&"warrior_guard", &"goblin_stab"])
	assert_eq(_decide(near, 30.0).action_id, &"warrior_guard", "inside 40 units it braces")
	var far := _unit(0, CG.Team.PLAYER, Vector2.ZERO, [&"warrior_guard", &"goblin_stab"])
	assert_ne(_decide(far, 300.0).action_id, &"warrior_guard", "at 300 there is nothing to brace against")

# ---------------------------------------------------------------------------
# the negative side, and it is the half that matters
# ---------------------------------------------------------------------------

func test_a_pawn_never_self_buffs_from_the_fallback_layer() -> void:
	var pawn_unit := _unit(0, CG.Team.PLAYER, Vector2.ZERO, [&"warrior_guard", &"warrior_strike"])
	pawn_unit.pawn = PawnData.new()
	var intent := _decide(pawn_unit, 20.0)
	assert_eq(
		intent.action_id, &"warrior_strike",
		"a pawn buffing itself here is a pawn doing something written in no plan"
	)

## The three exclusions, each of them a rule that lives somewhere else. A heal is
## `_first_heal`'s, a channel is #219's, a summon is the plan layer's cap.
func test_the_branch_declines_heals_channels_and_summons() -> void:
	for id in [&"warrior_second_wind", &"abomination_immolate", &"build_siege_engine"]:
		var action := ActionLibrary.get_action(id)
		assert_not_null(action, "%s should exist" % id)
		assert_true(action.targets_self, "%s is self-targeted, or this test proves nothing" % id)
		var u := _unit(0, CG.Team.PLAYER, Vector2.ZERO, [id, &"goblin_stab"])
		u.resource_kind = CG.ResourceKind.MANA
		var intent := _decide(u, 20.0)
		assert_ne(intent.action_id, id, "%s must not be cast by the fallback layer" % id)

## Every zero-range action must say it is self-targeted, because a zero-range
## action aimed at anybody else can never be in range of anything. **This is the
## one direction of the inference that is safe:** it does not derive
## `targets_self` from the range -- `_action_summon` and `_action_self_heal` want
## opposite things from that zero -- it refuses the pair that is definitionally
## broken.
func test_no_action_states_zero_range_without_saying_it_targets_itself() -> void:
	var checked := 0
	for id in Registry.all_action_ids():
		var action := ActionLibrary.get_action(id)
		if action.range_units > 0.0:
			continue
		checked += 1
		assert_true(action.targets_self, "%s has no reach and does not declare targets_self" % id)
	assert_true(checked >= 5, "only %d zero-range actions were checked" % checked)

# ---------------------------------------------------------------------------
# and it happens in a real fight
# ---------------------------------------------------------------------------

## The live half: a structural check would pass on a build where the Brute never
## meets anybody. Measured over 60 fights with `Tools/BruteRoar.gd`: 1.23 roars a
## fight and 78.5 pawn-ticks of TAUNTED. The floor here is a third of that.
func test_the_brute_really_roars_and_it_really_lands_on_a_pawn() -> void:
	var roars := 0
	var taunted := 0
	var longest := 0
	for s in 6:
		var party: Array[PawnData] = []
		for cid in [&"abomination", &"geysermancer", &"priest", &"warrior"]:
			party.append(PawnFactory.make_starter_pawn(cid, StringName("%s_0" % cid), String(cid)))
		var state := CombatSim.build(party, Registry.get_encounter(&"floor1_hazard"), s)
		var run := {}
		while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
			CombatSim.step(state)
			for u in state.units:
				if u.pawn == null or not u.alive:
					continue
				if u.has_status(CG.Status.TAUNTED):
					taunted += 1
					run[u.id] = int(run.get(u.id, 0)) + 1
					longest = maxi(longest, int(run[u.id]))
				else:
					run[u.id] = 0
		for e in state.events:
			if e.kind == CG.EventKind.ACTION_FIRE and e.action_id == ROAR:
				roars += 1
	print("brute_roar over 6 fights: %d roars, %d pawn-ticks taunted, longest lock %d ticks" % [roars, taunted, longest])
	assert_true(roars >= 2, "the Brute should roar, got %d in 6 fights" % roars)
	assert_true(taunted >= 100, "the roar should land on pawns, got %d pawn-ticks in 6 fights" % taunted)

## **The player's #58 ruling, as an assertion rather than as an argument from the
## numbers on the action:** *"taunts must not permanently lock a pawn"*. Measured
## every tick from `unit.statuses`, because a status is state and the run of ticks
## it was held cannot be recovered from the event stream afterwards.
func test_no_pawn_is_ever_locked_for_longer_than_the_roar_lasts() -> void:
	var duration: int = ActionLibrary.get_action(ROAR).status_duration_ticks
	var cooldown: int = ActionLibrary.get_action(ROAR).cooldown_ticks
	assert_true(
		cooldown > duration,
		"the roar is up %d of every %d ticks, which is the permanent lock #58 forbids" % [duration, cooldown]
	)
	var longest := 0
	for s in 4:
		var party: Array[PawnData] = []
		for cid in [&"abomination", &"geysermancer", &"priest", &"warrior"]:
			party.append(PawnFactory.make_starter_pawn(cid, StringName("%s_0" % cid), String(cid)))
		var state := CombatSim.build(party, Registry.get_encounter(&"floor1_hazard"), s)
		var run := {}
		while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
			CombatSim.step(state)
			for u in state.units:
				if u.pawn == null or not u.alive:
					continue
				if u.has_status(CG.Status.TAUNTED):
					run[u.id] = int(run.get(u.id, 0)) + 1
					longest = maxi(longest, int(run[u.id]))
				else:
					run[u.id] = 0
	print("longest unbroken TAUNTED run across 4 fights: %d ticks, against a %d-tick roar" % [longest, duration])
	assert_true(longest > 0, "nothing was taunted at all, so this measured nothing")
	assert_true(
		longest <= duration,
		"a pawn carried TAUNTED for %d consecutive ticks against a %d-tick roar" % [longest, duration]
	)
