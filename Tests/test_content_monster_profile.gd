extends "res://Tests/TestCase.gd"


## Issue 542: the arithmetic every monster's statline is derived through.

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
