extends "res://Tests/TestCase.gd"


## Issue 42: items are loot per issue 41's own outcome. What drops, and how
## often, against the real Registry content.

func test_ordinary_rooms_never_drop() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for t in [FloorRoom.Type.ENEMY, FloorRoom.Type.TRAP, FloorRoom.Type.LIBRARY, FloorRoom.Type.CELL]:
		for i in 20:
			assert_eq(LootTables.roll_drop(t, 1, rng), null, "%s should never drop" % FloorRoom.type_name(t))


func test_treasure_and_boss_rooms_always_drop() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	for t in [FloorRoom.Type.TREASURE, FloorRoom.Type.BOSS]:
		for i in 20:
			var item := LootTables.roll_drop(t, 1, rng)
			assert_not_null(item, "%s should always drop something" % FloorRoom.type_name(t))


func test_miniboss_and_big_enemy_rooms_sometimes_drop() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var got_something := false
	var got_nothing := false
	for i in 40:
		var item := LootTables.roll_drop(FloorRoom.Type.MINIBOSS, 1, rng)
		if item != null:
			got_something = true
		else:
			got_nothing = true
	assert_true(got_something, "MINIBOSS should drop sometimes")
	assert_true(got_nothing, "MINIBOSS should not drop every time")


func test_a_dropped_item_is_a_real_registered_item() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var item := LootTables.roll_drop(FloorRoom.Type.TREASURE, 1, rng)
	assert_not_null(item)
	assert_eq(ItemLibrary.get_equipment(item.id), item)


func test_same_seed_replays_bit_identical() -> void:
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 777
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 777
	for i in 10:
		var item_a := LootTables.roll_drop(FloorRoom.Type.MINIBOSS, 2, rng_a)
		var item_b := LootTables.roll_drop(FloorRoom.Type.MINIBOSS, 2, rng_b)
		var id_a: StringName = item_a.id if item_a != null else &""
		var id_b: StringName = item_b.id if item_b != null else &""
		assert_eq(id_a, id_b, "same seed should produce the same drop sequence")
