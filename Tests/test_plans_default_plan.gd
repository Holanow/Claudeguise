extends "res://Tests/TestCase.gd"


## Issue 719: the fallback is two rules -- move at the nearest enemy avoiding
## hazard, attack in range with the weapon's basic attack -- and this file is
## the proof for `DefaultPlan`, the live fallback (`SimDeps.default_decide`).

func _pawn(class_id: StringName) -> PawnData:
	return PawnFactory.make_starter_pawn(class_id, class_id, String(class_id))

func _unit(id: int, team: CG.Team, pos: Vector2, actions: Array[StringName] = []) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.hp_max = 200
	u.hp = 200
	u.position = pos
	u.move_speed = 3.0
	u.actions = actions
	return u

# ---------------------------------------------------------------------------
# Structure: one row, always legible.

func test_every_class_has_exactly_one_default_row() -> void:
	for cid in ClassLibrary.all_ids():
		var state := CombatSim.build([_pawn(cid)], RoomLibrary.get_room(CG.DEFAULT_ENCOUNTER), 0)
		var rows := DefaultPlan.rows_for(state.units[0])
		assert_eq(rows.size(), 1, "%s: the fallback is one row, not several" % cid)

func test_every_default_row_has_a_sentence_for_every_class() -> void:
	for cid in ClassLibrary.all_ids():
		var state := CombatSim.build([_pawn(cid)], RoomLibrary.get_room(CG.DEFAULT_ENCOUNTER), 0)
		for row in DefaultPlan.rows_for(state.units[0]):
			assert_true(row.condition.describe() != "", "%s: the row's condition has no sentence" % cid)
			for block in row.blocks:
				assert_true(block.describe() != "", "%s: a block has no sentence" % cid)

# ---------------------------------------------------------------------------
# Rule 2: the weapon's basic attack, specifically.

func test_weapon_attack_is_the_pawns_weapon_granted_action() -> void:
	var pawn := _pawn(&"warrior")
	var state := CombatSim.build([pawn], RoomLibrary.get_room(CG.DEFAULT_ENCOUNTER), 0)
	var unit := state.units[0]
	assert_eq(DefaultPlan.weapon_attack(unit), ActionLibrary.get_action(pawn.main_hand.granted_actions[0]),
		"the fallback's attack must be the weapon's own, not a class ability")

## The Abomination's class carries `abomination_grapple`, an attack-shaped
## class ability, alongside its weapon's `abomination_claw`. The fallback must
## never reach for the class ability.
func test_weapon_attack_ignores_a_class_ability_even_when_it_would_qualify() -> void:
	var pawn := _pawn(&"abomination")
	var state := CombatSim.build([pawn], RoomLibrary.get_room(CG.DEFAULT_ENCOUNTER), 0)
	var picked := DefaultPlan.weapon_attack(state.units[0])
	assert_ne(picked, null)
	assert_eq(picked.id, &"abomination_claw", "the weapon's own action, not the class's grapple")

func test_weapon_attack_is_null_with_no_weapon_equipped() -> void:
	var pawn := _pawn(&"warrior")
	pawn.main_hand = null
	var state := CombatSim.build([pawn], RoomLibrary.get_room(CG.DEFAULT_ENCOUNTER), 0)
	assert_eq(DefaultPlan.weapon_attack(state.units[0]), null,
		"no weapon, no basic attack -- the class carries none of its own")

func test_weapon_attack_is_the_first_attack_shaped_action_for_an_enemy() -> void:
	var enemy_def: EnemyDef = EnemyLibrary.get_enemy(&"brute")
	var unit := _unit(0, CG.Team.ENEMY, Vector2.ZERO, enemy_def.actions)
	assert_eq(DefaultPlan.weapon_attack(unit).id, &"brute_slam",
		"first in the enemy's own list, no cost search among the rest")

# ---------------------------------------------------------------------------
# Nothing else: no heal, no self-buff, no player focus, no pile-on, no taunter
# targeting reachable through the fallback any more. All still exist, just as
# blocks a player's own plan can author -- `rows_for` simply never builds them.

func test_the_row_carries_no_heal_or_buff_condition() -> void:
	for cid in ClassLibrary.all_ids():
		var state := CombatSim.build([_pawn(cid)], RoomLibrary.get_room(CG.DEFAULT_ENCOUNTER), 0)
		for row in DefaultPlan.rows_for(state.units[0]):
			for block in row.blocks:
				assert_false(block is AllyNeedsHealBlock or block is EnemyWithinBuffReachBlock
					or block is UseHealBlock or block is UseSelfBuffBlock
					or block is TargetFocusedEnemyBlock or block is TargetPileOnBlock
					or block is TargetTaunterBlock,
					"%s: the fallback row still carries %s" % [cid, block])

# ---------------------------------------------------------------------------
# Issue 650, re-proved against the new row: an unaffordable order idles rather
# than spending the tick on a refusal.

func test_an_unaffordable_default_row_idles_rather_than_ordering_a_refusal() -> void:
	var attacker := _unit(0, CG.Team.PLAYER, Vector2.ZERO, [&"warrior_strike"])
	var target := _unit(1, CG.Team.ENEMY, Vector2(20.0, 0.0))
	var state := CombatState.new(0)
	state.units.append(attacker)
	state.units.append(target)
	# warrior_strike costs nothing, so cooldown is the only way to make it
	# unaffordable: hold it down past this tick.
	attacker.cooldowns[&"warrior_strike"] = state.tick + 50
	var intent := DefaultPlan.decide(state, attacker)
	assert_eq(intent.kind, CG.IntentKind.IDLE,
		"an action on cooldown must idle rather than order a refusal")

# ---------------------------------------------------------------------------
# Rule 1, proved live: hazardous ground can slow the approach but must never
# stop it. `CombatSim._avoid_hazard` (issue 163) is what does the avoiding;
# this proves the fallback's own MOVE_TO intents ride it all the way to a
# landed hit, including when the whole direct path burns.

func test_the_fallback_reaches_and_attacks_from_inside_hazardous_ground() -> void:
	var attacker := _unit(0, CG.Team.PLAYER, Vector2(-150.0, 0.0), [&"warrior_strike"])
	attacker.hp_max = 2000
	attacker.hp = 2000
	var target := _unit(1, CG.Team.ENEMY, Vector2(150.0, 0.0))
	target.hp_max = 5000
	target.hp = 5000
	var state := CombatState.new(0)
	state.units.append(attacker)
	state.units.append(target)
	# A hazard strip wide enough to cover the whole straight-line approach and
	# both of _avoid_hazard's side-step candidates -- there is no clear step
	# anywhere on the way, only a straight walk through.
	state.grid.stamp_features([Terrain.hazard(Rect2(-400.0, -400.0, 800.0, 800.0), 2, CG.DamageType.FIRE)])
	var deps := SimDeps.new()
	var landed := false
	for _i in 400:
		CombatSim.step(state, deps)
		if target.hp < target.hp_max:
			landed = true
			break
	assert_true(landed, "the attacker never landed a hit -- it deadlocked against hazard it could not avoid")
	assert_true(attacker.hp < attacker.hp_max, "and it really did walk through the fire to get there")

# ---------------------------------------------------------------------------
# Issue 747: dual_wields

func test_dual_wields_true_for_two_martial_weapons() -> void:
	var pawn := _pawn(&"warrior")
	pawn.main_hand = ItemLibrary.get_equipment(&"sword")
	pawn.off_hand = ItemLibrary.get_equipment(&"wrench")
	assert_true(DefaultPlan.dual_wields(pawn))

func test_dual_wields_false_for_a_shield() -> void:
	var pawn := _pawn(&"warrior")
	pawn.off_hand = ItemLibrary.get_equipment(&"shield")
	assert_false(DefaultPlan.dual_wields(pawn), "a shield grants no attack")

func test_dual_wields_false_for_a_quiver() -> void:
	var pawn := _pawn(&"siege_master")
	pawn.off_hand = ItemLibrary.get_equipment(&"quiver")
	assert_false(DefaultPlan.dual_wields(pawn), "a quiver is MARTIAL-tagged but grants no attack")

func test_dual_wields_false_for_a_focus() -> void:
	var pawn := _pawn(&"priest")
	pawn.off_hand = ItemLibrary.get_equipment(&"focus")
	assert_false(DefaultPlan.dual_wields(pawn), "MAGICAL, not MARTIAL, and the wrong hand entirely")

func test_dual_wields_false_with_an_empty_off_hand() -> void:
	var pawn := _pawn(&"warrior")
	## Issue 822: a starter Warrior now carries a shield, so the empty off hand
	## this is named for has to be built rather than assumed.
	pawn.off_hand = null
	assert_false(DefaultPlan.dual_wields(pawn))

func test_dual_wields_false_with_no_pawn() -> void:
	assert_false(DefaultPlan.dual_wields(null))
