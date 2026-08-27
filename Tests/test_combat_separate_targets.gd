extends "res://Tests/TestCase.gd"


## Issue 671 follow-up: `ActionDelivery.separate_targets` sends `count` shots at
## `count` DIFFERENT enemies instead of fanning them all at one. The player's
## words: seeker bolts should "fire at 2 *different* enemies".

func _delivery(count: int, separate: bool) -> ActionDelivery:
	var d := ActionDelivery.new()
	d.speed = 13.0
	d.count = count
	d.spread_degrees = 16.0
	d.separate_targets = separate
	return d

func _action(count: int, separate: bool) -> ActionDef:
	var a := ActionDef.new()
	a.id = &"probe_volley"
	a.delivery = _delivery(count, separate)
	a.targeting = ActionTargeting.new()
	a.targeting.range_units = 999.0
	return a

func _caster() -> CombatUnit:
	var u := CombatUnit.new()
	u.id = 0
	u.team = CG.Team.PLAYER
	u.hp = 10
	u.hp_max = 10
	u.position = Vector2.ZERO
	return u

func _enemy(id: int, at: Vector2) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = CG.Team.ENEMY
	u.hp = 10
	u.hp_max = 10
	u.position = at
	return u

func _fired_at(state: CombatState) -> Array:
	var out := []
	for p in state.projectiles:
		out.append(p.target_id)
	out.sort()
	return out

func _state_with(enemies: Array, action: ActionDef) -> CombatState:
	var s := CombatState.new(671)
	s.units.append(_caster())
	for e in enemies:
		s.units.append(e)
	CombatSim._spawn_projectiles(s, s.units[0], s.units[1], action, SimDeps.new())
	return s

func test_two_bolts_go_to_two_different_enemies() -> void:
	var s := _state_with([_enemy(1, Vector2(100, 0)), _enemy(2, Vector2(140, 0))], _action(2, true))
	assert_eq(s.projectiles.size(), 2, "two bolts")
	assert_eq(_fired_at(s), [1, 2], "each bolt must pick a different enemy, nearest first")


## The negative half, and without it the test above proves nothing about the
## flag: the same two bolts with the flag off must BOTH go to the primary.
func test_without_the_flag_both_bolts_go_to_the_primary() -> void:
	var s := _state_with([_enemy(1, Vector2(100, 0)), _enemy(2, Vector2(140, 0))], _action(2, false))
	assert_eq(s.projectiles.size(), 2, "two bolts")
	assert_eq(_fired_at(s), [1, 1], "with the flag off both bolts go at the one target, as before")


## A two-bolt volley into a lone survivor is still two bolts. Falling silent
## because the roster ran short would be worse than doubling up.
func test_a_volley_into_one_enemy_is_still_two_bolts() -> void:
	var s := _state_with([_enemy(1, Vector2(100, 0))], _action(2, true))
	assert_eq(s.projectiles.size(), 2, "count is honoured even when there are fewer enemies than shots")
	assert_eq(_fired_at(s), [1, 1], "the second bolt falls back to the primary target")


## The dead are not targets. Ordering is by distance, so a corpse in the way
## must not take one of the two bolts.
func test_a_dead_enemy_is_not_picked() -> void:
	var corpse := _enemy(1, Vector2(60, 0))
	corpse.hp = 0
	corpse.alive = false # hp and alive are separate fields; the sim sets both
	var s := _state_with([corpse, _enemy(2, Vector2(100, 0)), _enemy(3, Vector2(140, 0))], _action(2, true))
	assert_eq(_fired_at(s), [2, 3], "the nearest is dead, so the two living ones take the bolts")
