extends "res://Tests/TestCase.gd"

## Issue 942: `pickable_ids()` was doing two jobs, and the day #941 cleared
## `pickable` on the Warden thirteen instruments stopped measuring him in silence.

func test_fight_ids_is_every_room_that_holds_a_fight() -> void:
	var fights := RoomLibrary.fight_ids()
	for id in RoomLibrary.all_ids():
		var has_enemies := not RoomLibrary.get_room(id).enemy_spawns.is_empty()
		assert_eq(fights.has(id), has_enemies,
			"'%s' holds %d enemy spawns and fight_ids() %s it" % [
				id, RoomLibrary.get_room(id).enemy_spawns.size(),
				"lists" if fights.has(id) else "does not list"])


## The regression itself: the boss room is not on the menu and is still a fight.
func test_fight_ids_holds_the_boss_room_the_picker_does_not_offer() -> void:
	assert_true(RoomLibrary.fight_ids().has(FloorGenerator.BOSS_ID),
		"the floor's boss room is a fight whatever the picker offers")
	assert_false(RoomLibrary.pickable_ids().has(FloorGenerator.BOSS_ID),
		"issue 300: the Warden is arrived at, not picked")


## The camp is the one room that is a place rather than a fight.
func test_fight_ids_leaves_out_the_room_that_holds_no_enemies() -> void:
	assert_false(RoomLibrary.fight_ids().has(&"floor1_camp"),
		"the camp holds no enemies, so a sweep over it measures nothing")


func test_every_offered_room_is_a_fight() -> void:
	for id in RoomLibrary.pickable_ids():
		assert_true(RoomLibrary.fight_ids().has(id),
			"the picker offers '%s' and it holds no fight" % id)


## ROOMS order, never sorted: `pickable_ids()` carries a player-visible order
## (#32) and these two must not disagree about it.
func test_fight_ids_keeps_the_authored_order() -> void:
	var fights := RoomLibrary.fight_ids()
	var seen := -1
	for id in RoomLibrary.pickable_ids():
		var at := fights.find(id)
		assert_true(at > seen, "'%s' is out of authored order in fight_ids()" % id)
		seen = at
