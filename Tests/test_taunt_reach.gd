extends "res://Tests/TestCase.gd"


## Issue 310: a taunt must give its victim time to cross its own radius.
##
## Measured 0 of 208 taunts geometrically impossible on `floor1_hazard`
## (`Tools/TauntArrival.gd`). This holds that at zero: widening a radius or
## shortening a duration past what the slowest victim can walk fires here.


func test_every_taunt_radius_is_walkable_inside_its_own_duration() -> void:
	var taunts := _taunt_actions()
	assert_true(taunts.size() > 0, "no action applies TAUNTING; this test measures nothing")
	var victims := _victims()
	assert_true(victims.size() > 0, "no victims to measure against")
	for action in taunts:
		for victim in victims:
			var need := _ticks_to_close(action.taunt_radius, float(victim["speed"]), float(victim["reach"]))
			assert_true(need <= action.status_duration_ticks,
				("%s taunts to %.0f units for %d ticks, and %s walks %.1f/tick with %.0f reach:\n"
				+ "  it needs %d ticks to close and cannot arrive before the taunt ends.") % [
					action.id, action.taunt_radius, action.status_duration_ticks,
					victim["name"], float(victim["speed"]), float(victim["reach"]), need])


func test_the_check_fires_on_a_radius_nothing_can_cross() -> void:
	assert_eq(_ticks_to_close(200.0, 6.3, 140.0), 10, "a 60-unit gap at 6.3/tick is 10 ticks")
	assert_true(_ticks_to_close(2000.0, 1.0, 0.0) > 120,
		"a 2000-unit radius at 1 unit/tick must exceed an 8-second duration")
	assert_eq(_ticks_to_close(100.0, 6.3, 140.0), 0, "already inside reach costs nothing")


## Ticks to walk from the edge of `radius` to within `reach`, in a straight line.
func _ticks_to_close(radius: float, speed: float, reach: float) -> int:
	return int(ceil(maxf(0.0, radius - reach) / maxf(0.001, speed)))


## Everything a taunt could land on, with the move speed and attack reach the
## simulation would give it.
func _victims() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for class_id in Registry.all_class_ids():
		var pawn := PawnFactory.make_starter_pawn(class_id, class_id, String(class_id))
		var ids: Array[StringName] = []
		if pawn.pawn_class != null:
			ids.append_array(pawn.pawn_class.starting_action_ids())
		for e in pawn.equipment():
			ids.append_array(e.granted_actions)
		out.append({"name": String(class_id), "speed": Balance.move_speed(pawn), "reach": _reach(ids)})
	for enemy_id in Registry.all_enemy_ids():
		var enemy := EnemyLibrary.get_enemy(enemy_id)
		if enemy == null or enemy.move_speed <= 0.0:
			continue
		out.append({"name": String(enemy_id), "speed": enemy.move_speed, "reach": _reach(enemy.actions)})
	return out


## The furthest a unit can hit from, which is what the compulsion closes to.
func _reach(action_ids: Array[StringName]) -> float:
	var defs: Array[ActionDef] = []
	for id in action_ids:
		var a := ActionLibrary.get_action(id)
		if a != null:
			defs.append(a)
	var out := 0.0
	for a in [DefaultBehavior.default_attack_action(defs, false), DefaultBehavior.default_attack_action(defs, true)]:
		if a != null:
			out = maxf(out, a.range_units)
	return out


func _taunt_actions() -> Array[ActionDef]:
	var out: Array[ActionDef] = []
	for id in Registry.all_action_ids():
		var a := ActionLibrary.get_action(id)
		if a != null and a.applies_status_enabled and a.applies_status == CG.Status.TAUNTING and a.taunt_radius > 0.0:
			out.append(a)
	return out
