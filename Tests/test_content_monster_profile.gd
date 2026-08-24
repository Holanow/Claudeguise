extends "res://Tests/TestCase.gd"


## Issue 542: the mechanism changed and not one number did.

## Every monster's stats exactly as they were hand-written before the profile
## existed, copied from the rows #542 replaced. This is the frozen truth: if a
## multiplier is mistyped, the fingerprint would catch it a hundred seconds
## later with no name attached, and this catches it by name.
const BEFORE := {
	&"goblin":        {"hp": 35,   "dmg": 9,  "move": 4.0, "dr": 0.0,  "radius": 11.0, "type": CG.DamageType.PHYSICAL},
	&"goblin_archer": {"hp": 28,   "dmg": 8,  "move": 3.2, "dr": 0.0,  "radius": 11.0, "type": CG.DamageType.PHYSICAL},
	&"ghoul":         {"hp": 200,  "dmg": 20, "move": 1.6, "dr": 0.1,  "radius": 16.0, "type": CG.DamageType.PHYSICAL},
	&"cultist":       {"hp": 50,   "dmg": 11, "move": 3.0, "dr": 0.0,  "radius": 12.0, "type": CG.DamageType.PROFANE},
	&"the_warden":    {"hp": 1000, "dmg": 58, "move": 1.4, "dr": 0.05, "radius": 22.0, "type": CG.DamageType.PHYSICAL},
	&"brute":         {"hp": 320,  "dmg": 24, "move": 1.8, "dr": 0.15, "radius": 18.0, "type": CG.DamageType.PHYSICAL},
	&"stalker":       {"hp": 30,   "dmg": 5,  "move": 3.8, "dr": 0.0,  "radius": 10.0, "type": CG.DamageType.PHYSICAL},
	&"rat":           {"hp": 20,   "dmg": 3,  "move": 5.0, "dr": 0.0,  "radius": 8.0,  "type": CG.DamageType.PHYSICAL},
	&"rat_king":      {"hp": 420,  "dmg": 21, "move": 1.2, "dr": 0.0,  "radius": 24.0, "type": CG.DamageType.PHYSICAL},
	&"siege_engine":  {"hp": 140,  "dmg": 16, "move": 0.0, "dr": 0.0,  "radius": 20.0, "type": CG.DamageType.PHYSICAL},
}

# ---------------------------------------------------------------------------
# Every number unchanged, which is the entire order this issue had to follow
# ---------------------------------------------------------------------------

## Exact equality on the floats, deliberately. `is_equal_approx` would pass a
## value one ULP out, and one ULP is enough to move a fight and the fingerprint
## with it -- which is why the bases are powers of two.
func test_every_monster_resolves_to_the_number_it_had_before() -> void:
	var wrong: Array[String] = []
	for id in BEFORE:
		var e: EnemyDef = Registry.get_enemy(id)
		if e == null:
			wrong.append("%s: no such enemy" % id)
			continue
		var want: Dictionary = BEFORE[id]
		if e.hp_max != want["hp"]:
			wrong.append("%s hp_max %d, was %d" % [id, e.hp_max, want["hp"]])
		if e.move_speed != want["move"]:
			wrong.append("%s move_speed %.17f, was %.17f" % [id, e.move_speed, want["move"]])
		if e.damage_reduction != want["dr"]:
			wrong.append("%s damage_reduction %.17f, was %.17f" % [id, e.damage_reduction, want["dr"]])
		if e.radius != want["radius"]:
			wrong.append("%s radius %.17f, was %.17f" % [id, e.radius, want["radius"]])
		var power: int = int(e.attack_power.get(want["type"], -1))
		if power != want["dmg"]:
			wrong.append("%s attack power %d, was %d" % [id, power, want["dmg"]])
	assert_eq(wrong, [] as Array[String],
		"issue 542 was to change where the numbers come from, not the numbers:\n  %s"
			% "\n  ".join(wrong))

## The table above is only worth anything if it covers the whole bestiary.
func test_the_frozen_table_covers_every_registered_enemy() -> void:
	var missing: Array[String] = []
	for id in Registry.all_enemy_ids():
		if not BEFORE.has(id):
			missing.append(String(id))
	assert_eq(missing, [] as Array[String],
		"these enemies are outside the frozen table, so nothing checks them: %s"
			% ", ".join(missing))

# ---------------------------------------------------------------------------
# The profile itself
# ---------------------------------------------------------------------------

func test_the_float_bases_are_powers_of_two() -> void:
	# Scaling by a power of two is exact, which is the only reason a multiplier
	# can reproduce a hand-written float bit for bit.
	assert_eq(MonsterProfile.BASE_MOVE_SPEED, 4.0)
	assert_eq(MonsterProfile.BASE_RESISTANCE, 0.25)
	assert_eq(MonsterProfile.move_speed(0.35), 1.4, "one ULP out here moves the fight")
	assert_eq(MonsterProfile.resistance(0.6), 0.15)

func test_a_multiplier_of_one_is_the_baseline_itself() -> void:
	assert_eq(MonsterProfile.hp(1.0), MonsterProfile.BASE_HP)
	assert_eq(MonsterProfile.damage(1.0), MonsterProfile.BASE_DAMAGE)
	assert_eq(MonsterProfile.move_speed(1.0), MonsterProfile.BASE_MOVE_SPEED)
	assert_eq(MonsterProfile.resistance(1.0), MonsterProfile.BASE_RESISTANCE)

# ---------------------------------------------------------------------------
# Action speed, which is new capability rather than a conversion
# ---------------------------------------------------------------------------

## The identity that keeps ten monsters' fights untouched: every enemy ships at
## 1.0 today, so every authored tick count must survive the new path unchanged.
func test_action_speed_of_one_returns_the_authored_ticks() -> void:
	for ticks in [1, 2, 3, 5, 8, 13, 18, 20, 45, 120, 240]:
		assert_eq(Balance.scale_enemy_action_ticks(ticks, 1.0), ticks,
			"an enemy at 1.0 must act at exactly its authored %d ticks" % ticks)

func test_every_enemy_ships_at_the_baseline_action_speed() -> void:
	var moved: Array[String] = []
	for id in Registry.all_enemy_ids():
		var e: EnemyDef = Registry.get_enemy(id)
		if e != null and e.action_speed != MonsterProfile.BASE_ACTION_SPEED:
			moved.append("%s at %.2f" % [id, e.action_speed])
	assert_eq(moved, [] as Array[String],
		("issue 542 adds the mechanism and moves nothing; a monster off 1.0 is a "
		+ "balance change and belongs in the curve issue: %s") % ", ".join(moved))

func test_action_speed_is_capped_at_both_ends() -> void:
	assert_eq(Balance.scale_enemy_action_ticks(20, 2.0), 10, "twice as fast is the floor")
	assert_eq(Balance.scale_enemy_action_ticks(20, 100.0), 10, "and it is a cap, not a slope")
	assert_eq(Balance.scale_enemy_action_ticks(20, 0.5), 40, "half speed is the ceiling")
	assert_eq(Balance.scale_enemy_action_ticks(20, 0.01), 40, "and that is a cap too")

func test_action_speed_never_reaches_zero_ticks() -> void:
	assert_true(Balance.scale_enemy_action_ticks(1, 100.0) >= 1,
		"a one-tick action must still take a tick")

## Passthrough, matching the pawn's: an action with no wind-up has none.
func test_zero_ticks_stay_zero() -> void:
	assert_eq(Balance.scale_enemy_action_ticks(0, 2.0), 0)
	assert_eq(Balance.scale_enemy_action_ticks(0, 1.0), 0)

## A nonsense speed must not turn an action instant.
func test_a_zero_action_speed_falls_back_to_the_authored_ticks() -> void:
	assert_eq(Balance.scale_enemy_action_ticks(20, 0.0), 20)
	assert_eq(Balance.scale_enemy_action_ticks(20, -1.0), 20)
