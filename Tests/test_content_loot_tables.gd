extends "res://Tests/TestCase.gd"


## Issue 919: what a cleared room's chest holds. The per-room-type drop chance
## this file used to check is gone -- the player's rate is "every fight on floor
## 1 drops 1 to 3 items", so there is no room type that pays nothing.

func _party() -> Array[PawnData]:
	var out: Array[PawnData] = []
	for id in [&"warrior", &"priest", &"geysermancer", &"siege_master"]:
		out.append(PawnFactory.make_starter_pawn(id, id, String(id)))
	return out


func test_every_chest_holds_between_one_and_three_pieces() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 919
	var sizes := {}
	for i in 200:
		var batch := LootTables.roll_batch(_party(), 1, rng)
		assert_true(batch.size() >= LootTables.MIN_ITEMS and batch.size() <= LootTables.MAX_ITEMS,
			"a chest held %d pieces" % batch.size())
		sizes[batch.size()] = true
	assert_eq(sizes.size(), 3, "200 chests produced only %d distinct sizes" % sizes.size())


## README: every drop batch guarantees at least one item usable by a current
## pawn. "Usable" is the class gate, not an empty slot.
func test_every_chest_holds_something_a_living_pawn_is_allowed() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var party := _party()
	for i in 120:
		var batch := LootTables.roll_batch(party, 1, rng)
		var usable := false
		for item in batch:
			for p in party:
				if item.allows_class(p.pawn_class):
					usable = true
		assert_true(usable, "a chest held nothing this party is allowed")


## And with a party of one class, the guarantee still holds against a library
## most of which that class is refused.
func test_the_guarantee_holds_for_a_single_class_party() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 6
	var party: Array[PawnData] = [PawnFactory.make_starter_pawn(&"warrior", &"w", "W")]
	for i in 120:
		var usable := false
		for item in LootTables.roll_batch(party, 1, rng):
			if item.allows_class(party[0].pawn_class):
				usable = true
		assert_true(usable, "a Warrior-only party was handed a chest it could use none of")


## The weighting reads the party's classes and never what they are wearing, so
## stripping every slot must not change the distribution at all.
func test_the_weighting_does_not_read_equipped_gear() -> void:
	var dressed := _party()
	var stripped := _party()
	for p in stripped:
		p.main_hand = null
		p.off_hand = null
		p.body = null
	var a := RandomNumberGenerator.new()
	a.seed = 33
	var b := RandomNumberGenerator.new()
	b.seed = 33
	for i in 40:
		var one := LootTables.roll_batch(dressed, 1, a)
		var two := LootTables.roll_batch(stripped, 1, b)
		assert_eq(one.size(), two.size())
		for j in one.size():
			assert_eq(one[j].id, two[j].id, "what the party is wearing moved the roll")


func test_a_dropped_piece_is_a_roll_of_a_real_registered_base() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	for item in LootTables.roll_batch(_party(), 1, rng):
		assert_not_null(ItemLibrary.get_equipment(item.id),
			"%s is not a registered base type" % item.id)


## Floor 1 rolls numbers only. #931 records that `AffixDef.Kind.VERB` is a stub,
## so this is asserted through `ItemRoller.unlocked` rather than through content.
func test_a_floor_one_chest_rolls_no_verb() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	for i in 60:
		for item in LootTables.roll_batch(_party(), 1, rng):
			for roll in item.affixes:
				assert_ne(int(roll.affix.kind), int(AffixDef.Kind.VERB),
					"%s rolled a verb on floor 1" % item.id)


func test_same_seed_replays_bit_identical() -> void:
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 777
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 777
	for i in 10:
		var a := LootTables.roll_batch(_party(), 1, rng_a)
		var b := LootTables.roll_batch(_party(), 1, rng_b)
		assert_eq(a.size(), b.size(), "same seed should produce the same chest")
		for j in a.size():
			assert_eq(a[j].display_name, b[j].display_name)
