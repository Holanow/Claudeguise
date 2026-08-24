extends "res://Tests/TestCase.gd"


## DefaultBehavior tested two ways: direct decide() calls for the precise,
## single-decision cases (heals fire only when needed), and a real
## CombatSim.step loop with a hand-built two-unit CombatState for the range
## behaviour, which needs many ticks of movement to become a "median distance"

func _unit(id: int, team: CG.Team, enemy_id: StringName, pos: Vector2) -> CombatUnit:
	var def := Registry.get_enemy(enemy_id)
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.enemy_id = enemy_id
	u.position = pos
	u.hp_max = 1000000
	u.hp = u.hp_max
	u.resource_max = def.resource_max
	u.resource_kind = def.resource_kind
	u.move_speed = def.move_speed
	u.radius = def.radius
	u.actions = def.actions.duplicate()
	return u

func _immobile_dummy(id: int, team: CG.Team, pos: Vector2) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.position = pos
	u.hp_max = 1000000
	u.hp = u.hp_max
	u.move_speed = 0.0
	u.actions = []
	return u

func _median_distance_over_fight(attacker_id: StringName, ticks: int) -> float:
	var state := CombatState.new(1)
	var attacker := _unit(0, CG.Team.PLAYER, attacker_id, Vector2(-400.0, 0.0))
	var dummy := _immobile_dummy(1, CG.Team.ENEMY, Vector2.ZERO)
	state.units.append(attacker)
	state.units.append(dummy)

	var distances: Array[float] = []
	for i in ticks:
		CombatSim.step(state)
		distances.append(attacker.position.distance_to(dummy.position))
	distances.sort()
	return distances[distances.size() / 2]


func test_ranged_default_behaviour_keeps_more_distance_than_melee() -> void:
	# Measured over 300 ticks (10 seconds) against a stationary target.
	var ranged_median := _median_distance_over_fight(&"goblin_archer", 300)
	var melee_median := _median_distance_over_fight(&"goblin", 300)
	print("DefaultBehavior range check: ranged median=%.1f melee median=%.1f" % [ranged_median, melee_median])
	assert_true(ranged_median > melee_median * 1.5, "ranged (%.1f) should sit well further back than melee (%.1f)" % [ranged_median, melee_median])


## TAUNTING, in DefaultBehavior._choose_target (via _nearest_taunter). Real
## decide() calls throughout, not the private helper directly, matching how
## every other test in this file exercises DefaultBehavior -- through its
## one public entry point.

func _taunter(id: int, pos: Vector2, radius: float) -> CombatUnit:
	var u := _immobile_dummy(id, CG.Team.ENEMY, pos)
	u.statuses[CG.Status.TAUNTING] = 999999
	u.taunt_radius = radius
	return u

func test_taunt_overrides_the_nearest_enemy() -> void:
	var state := CombatState.new(1)
	var attacker := _unit(0, CG.Team.PLAYER, &"goblin_archer", Vector2.ZERO)
	var nearest := _immobile_dummy(1, CG.Team.ENEMY, Vector2(50.0, 0.0))
	var taunter := _taunter(2, Vector2(150.0, 0.0), 999.0)
	state.units.append(attacker)
	state.units.append(nearest)
	state.units.append(taunter)

	var intent := DefaultBehavior.decide(state, attacker)
	assert_eq(intent.kind, CG.IntentKind.USE_ACTION, "expected a committed attack, not a move")
	assert_eq(intent.target_id, taunter.id, "a taunting enemy in range should be targeted over a nearer non-taunting one")


func test_taunt_out_of_its_own_radius_does_not_override() -> void:
	var state := CombatState.new(1)
	var attacker := _unit(0, CG.Team.PLAYER, &"goblin_archer", Vector2.ZERO)
	# Beyond the ranged commit window (170), so the baseline behaviour is
	# closing distance on it -- unambiguous MOVE_TO(nearest.position).
	var nearest := _immobile_dummy(1, CG.Team.ENEMY, Vector2(180.0, 0.0))
	# Taunting, but taunt_radius does not reach the attacker's position.
	var taunter := _taunter(2, Vector2(300.0, 0.0), 10.0)
	state.units.append(attacker)
	state.units.append(nearest)
	state.units.append(taunter)

	var intent := DefaultBehavior.decide(state, attacker)
	assert_eq(intent.kind, CG.IntentKind.MOVE_TO, "the nearest enemy is out of ranged commit range, so this should still be closing distance on it")
	# MOVE_TO carries no target_id; destination is the nearest enemy's own position.
	assert_eq(intent.destination, nearest.position)


func test_an_untaunting_enemy_is_never_treated_as_a_taunter() -> void:
	var state := CombatState.new(1)
	var attacker := _unit(0, CG.Team.PLAYER, &"goblin_archer", Vector2.ZERO)
	var nearest := _immobile_dummy(1, CG.Team.ENEMY, Vector2(150.0, 0.0))
	state.units.append(attacker)
	state.units.append(nearest)

	var intent := DefaultBehavior.decide(state, attacker)
	assert_eq(intent.kind, CG.IntentKind.USE_ACTION)
	assert_eq(intent.target_id, nearest.id, "with nobody taunting, ordinary nearest-target selection should be untouched")


func test_taunt_works_symmetrically_for_an_enemy_unit_too() -> void:
	# The Warrior taunting real enemies is the primary case per the class
	# fantasy -- TAUNTING and _nearest_taunter are generic over team, same
	## as _choose_target already is, so this checks the enemy side directly
	## rather than assuming symmetry.
	var state := CombatState.new(1)
	var attacker := _unit(0, CG.Team.ENEMY, &"goblin_archer", Vector2.ZERO)
	var nearest := _immobile_dummy(1, CG.Team.PLAYER, Vector2(50.0, 0.0))
	var taunter := _taunter(2, Vector2(150.0, 0.0), 999.0)
	taunter.team = CG.Team.PLAYER
	state.units.append(attacker)
	state.units.append(nearest)
	state.units.append(taunter)

	var intent := DefaultBehavior.decide(state, attacker)
	assert_eq(intent.kind, CG.IntentKind.USE_ACTION)
	assert_eq(intent.target_id, taunter.id)


func test_healer_heals_hurt_ally() -> void:
	var priest_pawn := PawnFactory.make_starter_pawn(&"priest", &"p1", "Priest")
	var priest := CombatUnit.new()
	priest.id = 0
	priest.team = CG.Team.PLAYER
	priest.pawn = priest_pawn
	priest.position = Vector2.ZERO
	priest.hp_max = 100
	priest.hp = 100
	priest.actions = priest_pawn.pawn_class.starting_actions.duplicate()

	var hurt_ally := CombatUnit.new()
	hurt_ally.id = 1
	hurt_ally.team = CG.Team.PLAYER
	hurt_ally.position = Vector2(50.0, 0.0)
	hurt_ally.hp_max = 100
	hurt_ally.hp = 30

	var enemy := CombatUnit.new()
	enemy.id = 2
	enemy.team = CG.Team.ENEMY
	enemy.position = Vector2(100.0, 0.0)
	enemy.hp_max = 50
	enemy.hp = 50

	var state := CombatState.new(0)
	state.units.append(priest)
	state.units.append(hurt_ally)
	state.units.append(enemy)

	var intent := DefaultBehavior.decide(state, priest)
	assert_eq(intent.kind, CG.IntentKind.USE_ACTION)
	var action := Registry.get_action(intent.action_id)
	assert_true(action.heals, "should pick the heal action when an ally is below half hp")
	assert_eq(intent.target_id, hurt_ally.id)


func test_healer_does_not_heal_full_health_allies() -> void:
	var priest_pawn := PawnFactory.make_starter_pawn(&"priest", &"p1", "Priest")
	var priest := CombatUnit.new()
	priest.id = 0
	priest.team = CG.Team.PLAYER
	priest.pawn = priest_pawn
	priest.position = Vector2.ZERO
	priest.hp_max = 100
	priest.hp = 100
	priest.actions = priest_pawn.pawn_class.starting_actions.duplicate()

	var healthy_ally := CombatUnit.new()
	healthy_ally.id = 1
	healthy_ally.team = CG.Team.PLAYER
	healthy_ally.position = Vector2(50.0, 0.0)
	healthy_ally.hp_max = 100
	healthy_ally.hp = 100

	var enemy := CombatUnit.new()
	enemy.id = 2
	enemy.team = CG.Team.ENEMY
	enemy.position = Vector2(100.0, 0.0)
	enemy.hp_max = 50
	enemy.hp = 50

	var state := CombatState.new(0)
	state.units.append(priest)
	state.units.append(healthy_ally)
	state.units.append(enemy)

	var intent := DefaultBehavior.decide(state, priest)
	if intent.kind == CG.IntentKind.USE_ACTION:
		var action := Registry.get_action(intent.action_id)
		assert_false(action.heals, "should not spend a turn healing when nobody needs it")
	else:
		assert_eq(intent.kind, CG.IntentKind.MOVE_TO, "should still do something useful, like closing to attack range")


## PLAYTEST-NOTES-2.md note 11: "The Abomination runs away a lot... tanks
## should move toward enemies." Root cause traced directly: `abomination_hook`
func test_a_pull_action_never_retreats_from_a_target_it_is_built_to_close_on() -> void:
	var abom_pawn := PawnFactory.make_starter_pawn(&"abomination", &"a1", "Abomination")
	var abom := CombatUnit.new()
	abom.id = 0
	abom.team = CG.Team.PLAYER
	abom.pawn = abom_pawn
	abom.position = Vector2.ZERO
	abom.hp_max = 200
	abom.hp = 200
	abom.resource_kind = CG.ResourceKind.RAGE
	abom.resource_max = 100
	abom.resource = 0
	abom.actions = abom_pawn.pawn_class.starting_actions.duplicate()

	var enemy := _immobile_dummy(1, CG.Team.ENEMY, Vector2(60.0, 0.0))
	var state := CombatState.new(0)
	state.units.append(abom)
	state.units.append(enemy)

	var intent := DefaultBehavior.decide(state, abom)
	if intent.kind == CG.IntentKind.MOVE_TO:
		var old_dist := abom.position.distance_to(enemy.position)
		var new_dist := intent.destination.distance_to(enemy.position)
		assert_true(new_dist <= old_dist, "a pull action must never order a retreat, got a move to %s (was %.1f away, would end %.1f away)" % [intent.destination, old_dist, new_dist])
	else:
		assert_eq(intent.kind, CG.IntentKind.USE_ACTION, "expected either an approach or a committed cast, not idle")
		assert_eq(intent.target_id, enemy.id)


func test_no_living_enemies_means_idle() -> void:
	var priest_pawn := PawnFactory.make_starter_pawn(&"priest", &"p1", "Priest")
	var priest := CombatUnit.new()
	priest.id = 0
	priest.team = CG.Team.PLAYER
	priest.pawn = priest_pawn
	priest.actions = priest_pawn.pawn_class.starting_actions.duplicate()

	var state := CombatState.new(0)
	state.units.append(priest)

	var intent := DefaultBehavior.decide(state, priest)
	assert_eq(intent.kind, CG.IntentKind.IDLE)


## Issue 87: geyser_cleanse is the first action in the game with `heals = true`
func test_default_behaviour_never_reaches_for_the_geysermancers_cleanse() -> void:
	var geo_pawn := PawnFactory.make_starter_pawn(&"geysermancer", &"g1", "Geysermancer")
	var geo := CombatUnit.new()
	geo.id = 0
	geo.team = CG.Team.PLAYER
	geo.pawn = geo_pawn
	geo.position = Vector2.ZERO
	geo.hp_max = 100
	geo.hp = 100
	geo.resource_kind = CG.ResourceKind.MANA
	geo.resource_max = 100
	geo.resource = 100
	geo.actions = geo_pawn.pawn_class.starting_actions.duplicate()
	assert_true(geo.actions.has(&"geyser_cleanse"), "fixture is only meaningful while the class actually carries it")

	var dying_ally := _immobile_dummy(1, CG.Team.PLAYER, Vector2(20.0, 0.0))
	dying_ally.hp = 1
	var enemy := _immobile_dummy(2, CG.Team.ENEMY, Vector2(150.0, 0.0))
	var state := CombatState.new(0)
	state.units.append(geo)
	state.units.append(dying_ally)
	state.units.append(enemy)

	var intent := DefaultBehavior.decide(state, geo)
	assert_true(intent.kind != CG.IntentKind.USE_ACTION or intent.action_id != &"geyser_cleanse",
		"DefaultBehavior picked the cleanse; its only route into a fight is its own preset plan")
	assert_eq(intent.kind, CG.IntentKind.USE_ACTION)
	assert_eq(intent.target_id, enemy.id, "with no real heal in the kit it should be attacking")

# ---------------------------------------------------------------------------
# Issue 129: the fallback picks the cheapest action that can deal damage,
# not the first non-heal entry in the list.

## **Issue 150: this helper is called `_pawn_unit_with` and did not make a pawn.**
## `u.pawn` was never set, so every unit it built read as an enemy to the two
## places in `DefaultBehavior` that ask -- `_choose_target`'s focus-bias branch
## then, and the self-targeted branch now. It was invisible before because the
## enemy path in `_choose_target` falls through to `_nearest` for a unit with no
## `enemy_id` either, so both branches returned the same answer.
func _pawn_unit_with(actions: Array[StringName], resource: int) -> CombatUnit:
	var u := CombatUnit.new()
	u.pawn = PawnData.new()
	u.id = 0
	u.team = CG.Team.PLAYER
	u.position = Vector2.ZERO
	u.hp_max = 100
	u.hp = 100
	u.move_speed = 3.0
	u.resource_kind = CG.ResourceKind.RAGE
	u.resource_max = 100
	u.resource = resource
	u.actions = actions
	return u

func _decide_against_a_dummy(unit: CombatUnit, enemy_at: float) -> Intent:
	var enemy := _immobile_dummy(1, CG.Team.ENEMY, Vector2(enemy_at, 0.0))
	var state := CombatState.new(0)
	state.units.append(unit)
	state.units.append(enemy)
	return DefaultBehavior.decide(state, unit)

## The exact case the equipment grant creates: a class action first, the
## weapon's attack last. Under the old first-in-list rule this Warrior would
## have "attacked" with Guard -- a self-buff with no damage in it -- and stood
## there recasting it.
func test_the_fallback_skips_an_action_that_cannot_damage_anything() -> void:
	var unit := _pawn_unit_with([&"warrior_guard", &"warrior_taunt", &"warrior_strike"], 100)
	var intent := _decide_against_a_dummy(unit, 20.0)
	assert_eq(intent.kind, CG.IntentKind.USE_ACTION)
	assert_eq(intent.action_id, &"warrior_strike",
		"Guard and Taunt deal no damage; neither is a way to attack somebody")

## Free beats cheap beats first. Strike sits last and still wins, which is the
## whole claim: order no longer decides anything.
func test_the_fallback_takes_the_cheapest_attack_not_the_first_one() -> void:
	var unit := _pawn_unit_with([&"warrior_execute", &"warrior_strike"], 100)
	var intent := _decide_against_a_dummy(unit, 20.0)
	assert_eq(intent.action_id, &"warrior_strike",
		"Execute costs 20 Rage and Strike costs nothing; the fallback is what a pawn can always pay for")

## The positive half of the pair, and the one that would catch a filter so
## strict it lets nothing through. A Warrior with its weapon taken away still
## has Execute, and must reach for it rather than idling -- a free zero-power
## Taunt is present and must not be mistaken for the cheapest attack.
func test_a_pawn_with_only_an_expensive_attack_still_uses_it() -> void:
	var unit := _pawn_unit_with([&"warrior_taunt", &"warrior_execute"], 100)
	var intent := _decide_against_a_dummy(unit, 20.0)
	assert_eq(intent.kind, CG.IntentKind.USE_ACTION)
	assert_eq(intent.action_id, &"warrior_execute",
		"the only damaging action it owns, whatever it costs")

## And the end-to-end version through the real builder, because every case above
## hands `decide()` a list this test does not. `CombatSim.build` is what puts a
## weapon's grant into `unit.actions`, and the two are separate code paths.
func test_a_real_built_warrior_falls_back_to_the_attack_its_sword_grants() -> void:
	var party: Array[PawnData] = [PawnFactory.make_starter_pawn(&"warrior", &"w0", "Warrior")]
	party[0].plans = []
	var state := CombatSim.build(party, Registry.get_encounter(&"floor1_room1"), 0)
	var warrior: CombatUnit = null
	for u in state.units:
		if u.pawn != null:
			warrior = u
	assert_not_null(warrior, "no Warrior was built")
	assert_true(warrior.actions.has(&"warrior_strike"),
		"the Sword's grant did not reach the fight")
	var intent := DefaultBehavior.decide(state, warrior)
	assert_true(intent != null and (intent.kind != CG.IntentKind.USE_ACTION or intent.action_id == &"warrior_strike"),
		"a built Warrior should approach or Strike, never cast something it cannot pay for")

## The Warden is the one unit carrying both a melee and a ranged attack, and it
## is why the melee-versus-ranged split exists at all (issue 62). Both of its
## actions are free, so the cheapest rule must not collapse the choice back to
## one of them: near, the axe; far, the chain.
func test_the_wardens_two_attacks_both_still_get_used() -> void:
	# On the PLAYER side only because `_decide_against_a_dummy` puts its dummy on
	# the ENEMY one. DefaultBehavior reads `unit.team` to find its foes and
	# nothing else about the side, which is what makes it drive both.
	var near := _unit(0, CG.Team.PLAYER, &"the_warden", Vector2.ZERO)
	var near_intent := _decide_against_a_dummy(near, 15.0)
	assert_eq(near_intent.action_id, &"warden_axe", "in its face, the axe")
	var far := _unit(2, CG.Team.PLAYER, &"the_warden", Vector2.ZERO)
	var far_intent := _decide_against_a_dummy(far, 190.0)
	assert_eq(far_intent.action_id, &"warden_chain_toss",
		"out of axe reach, the chain -- the thing that never fired before issue 62")

# ---------------------------------------------------------------------------
# Issue 214: "usable" has to mean usable.

## The reproduction, at the smallest scale that can show it. The Stalker carries
## Mark (60-tick cooldown, first in its list) and Dart (free, no cooldown). With
## Mark cooling, the old code returned Mark anyway and the tick died.
func test_a_cooling_action_falls_through_to_the_one_underneath_it() -> void:
	var stalker := _unit(0, CG.Team.PLAYER, &"stalker", Vector2.ZERO)
	stalker.cooldowns[&"stalker_mark"] = 30
	var intent := _decide_against_a_dummy(stalker, 150.0)
	assert_eq(intent.kind, CG.IntentKind.USE_ACTION)
	assert_eq(intent.action_id, &"stalker_dart",
		"Mark is on cooldown, so the Stalker should reach for the Dart underneath it")

## The other half of the pair, and the one that catches a filter written the
## wrong way round: off cooldown, the Stalker must still prefer Mark. A fix that
## made it dart forever would pass the test above on its own.
func test_the_same_stalker_still_marks_when_the_cooldown_is_clear() -> void:
	var stalker := _unit(0, CG.Team.PLAYER, &"stalker", Vector2.ZERO)
	var intent := _decide_against_a_dummy(stalker, 150.0)
	assert_eq(intent.action_id, &"stalker_mark",
		"nothing is cooling, so the specialty comes first")

## **The branch the fix could regress, and nothing in a real fight exercises it.**
## Filtering alone would empty the candidate list for a unit whose only action is
## cooling, and `decide` idles on an empty list -- so a one-action enemy would
## stop kiting, approaching and retreating for the whole cooldown. heron's own
## content comment on `stalker_dart` names that as the reason the Stalker got a
## second action at all.
func test_a_unit_whose_only_action_is_cooling_still_approaches() -> void:
	var goblin := _unit(0, CG.Team.PLAYER, &"goblin", Vector2.ZERO)
	goblin.cooldowns[&"goblin_stab"] = 30
	var intent := _decide_against_a_dummy(goblin, 400.0)
	assert_eq(intent.kind, CG.IntentKind.MOVE_TO,
		"a unit on cooldown keeps closing; it does not stand still for 60 ticks")

## And the same unit in range: it commits to the cooling action exactly as it did
## before, because there is nothing else to reach for. The sim refuses it and the
## tick is spent -- unchanged, deliberately. Making that case idle instead would
## be a second behaviour change with no content asking for it.
func test_a_unit_whose_only_action_is_cooling_does_not_idle_in_range() -> void:
	var goblin := _unit(0, CG.Team.PLAYER, &"goblin", Vector2.ZERO)
	goblin.cooldowns[&"goblin_stab"] = 30
	var intent := _decide_against_a_dummy(goblin, 15.0)
	assert_eq(intent.kind, CG.IntentKind.USE_ACTION,
		"unchanged from before issue 214: with nothing usable, behaviour is what it was")
