extends "res://Tests/TestCase.gd"


## Issue 588: the enemy the player clicked, and the two layers that read it.
## The pawn a player actually deploys is planless, so `DefaultBehavior` is the
## path that matters and it is tested first.

func _party_state(seed_value: int = 1) -> CombatState:
	var pawn := PawnFactory.make_starter_pawn(&"warrior", &"p0", "P")
	return CombatSim.build([pawn], Registry.get_encounter(&"floor1_ghoul_den"), seed_value, SimDeps.new())

func _enemies(state: CombatState) -> Array[CombatUnit]:
	return state.living(CG.Team.ENEMY)

func _pawn(state: CombatState) -> CombatUnit:
	for u in state.units:
		if u.pawn != null:
			return u
	return null

# ---------------------------------------------------------------------------

func test_a_fresh_fight_has_no_focus() -> void:
	assert_eq(_party_state().player_focus_id, -1, "nothing is focused until the player clicks")

## The headline. A planless pawn runs entirely on `DefaultBehavior`, so if the
## focus does not reach this function it does not reach the shipped game.
func test_a_planless_pawn_attacks_the_focused_enemy_instead_of_the_nearest() -> void:
	var state := _party_state()
	var me := _pawn(state)
	var foes := _enemies(state)
	assert_true(foes.size() >= 2, "this room needs at least two enemies to tell the two rules apart")

	var nearest := DefaultBehavior._choose_target(state, me, foes)
	var other: CombatUnit = null
	for f in foes:
		if f.id != nearest.id:
			other = f
			break
	assert_ne(other, null, "there is a second enemy to focus")

	state.player_focus_id = other.id
	var picked := DefaultBehavior._choose_target(state, me, foes)
	assert_eq(picked.id, other.id, "the pawn should go for the enemy the player clicked")
	assert_ne(picked.id, nearest.id, "and that is not the one it would have picked on its own")

## The negative, and it is the one that says the change did not leak.
func test_with_no_focus_the_choice_is_exactly_what_it_was() -> void:
	var state := _party_state()
	var me := _pawn(state)
	var foes := _enemies(state)
	var before := DefaultBehavior._choose_target(state, me, foes)
	state.player_focus_id = -1
	assert_eq(DefaultBehavior._choose_target(state, me, foes).id, before.id,
		"an unfocused fight must choose the way it always did")

func test_a_dead_focus_is_ignored_rather_than_held() -> void:
	var state := _party_state()
	var me := _pawn(state)
	var foes := _enemies(state)
	var victim := foes[foes.size() - 1]
	state.player_focus_id = victim.id
	victim.alive = false
	var still_living := _enemies(state)
	var picked := DefaultBehavior._choose_target(state, me, still_living)
	assert_ne(picked, null, "the pawn still has something to attack")
	assert_ne(picked.id, victim.id, "a dead focus is not a target")

## The focus may not outrank the mark filter: `_choose_target` is handed the
## candidates its caller already narrowed, so it must search inside them.
func test_the_focus_cannot_pull_a_target_out_of_a_narrowed_candidate_list() -> void:
	var state := _party_state()
	var foes := _enemies(state)
	state.player_focus_id = foes[1].id
	var only_first: Array[CombatUnit] = [foes[0]]
	assert_eq(DefaultBehavior.player_focus(state, only_first), null,
		"the focused enemy is not among the candidates, so it is not offered")

# ---------------------------------------------------------------------------

func test_when_focused_is_parameterless_like_the_other_state_conditions() -> void:
	assert_true(BlockCatalog.CONDITION_OPS.has(&"enemy_is_focused"),
		"the editor's dropdown is the catalog, so it should be there")
	var block := BlockCatalog.condition(&"enemy_is_focused")
	assert_true(block.operands().is_empty())
	assert_true(block.describe() != "",
		"a condition with no sentence is a condition the player cannot read")

func test_the_focus_condition_holds_only_while_a_living_enemy_is_focused() -> void:
	var state := _party_state()
	var me := _pawn(state)
	var plan := Plan.new()
	plan.id = &"focus_test"
	plan.display_name = "When focused"
	var condition := PlanFixtures.block(&"enemy_is_focused")
	plan.condition = condition as ConditionBlock

	assert_false(PlanInterpreter.condition_holds(state, me, plan), "nothing focused yet")
	var foe := _enemies(state)[0]
	state.player_focus_id = foe.id
	assert_true(PlanInterpreter.condition_holds(state, me, plan), "the player has focused an enemy")
	foe.alive = false
	assert_false(PlanInterpreter.condition_holds(state, me, plan), "the focused enemy is dead")

## The op that lets a written plan opt in, rather than having its own targeting
## silently overruled. Returns -1 when there is no focus, which is how every
## other targeting op reports "nobody".
func test_target_focused_enemy_aims_at_the_click_and_reports_nobody_without_one() -> void:
	var state := _party_state()
	var me := _pawn(state)
	var block := BlockCatalog.targeting(&"target_focused_enemy")

	assert_eq(block.pick(state, me), -1, "no focus, no target")
	var foe := _enemies(state)[1]
	state.player_focus_id = foe.id
	assert_eq(block.pick(state, me), foe.id)
	assert_true(BlockCatalog.TARGETING_OPS.has(&"target_focused_enemy"),
		"the editor builds its picker from this list")
	assert_true(block.describe() != "")

## An authored TARGETING block is NOT overruled by the focus. This is the
## binding principle and it is the reason `target_focused_enemy` exists.
func test_an_authored_targeting_block_still_aims_where_it_says() -> void:
	var state := _party_state()
	var me := _pawn(state)
	var block := BlockCatalog.targeting(&"target_nearest_enemy")

	var without := block.pick(state, me)
	var other: CombatUnit = null
	for f in _enemies(state):
		if f.id != without:
			other = f
			break
	state.player_focus_id = other.id
	assert_eq(block.pick(state, me), without,
		"the row says nearest, so it aims at the nearest whatever the player clicked")
