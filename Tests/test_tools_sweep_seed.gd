extends "res://Tests/TestCase.gd"


## Issue 897: the sweep's roster came from `randi()`, so two runs of one
## unchanged tree differed on 12 of its 14 shots and it could not be a differ.

const ScreenSweepScript := preload("res://Tools/ScreenSweep.gd")


func test_no_seed_argument_gives_the_same_seed_every_run() -> void:
	assert_eq(ScreenSweepScript.seed_of(PackedStringArray([])),
		ScreenSweepScript.DEFAULT_SEED, "an unseeded sweep must still repeat")
	assert_eq(ScreenSweepScript.seed_of(PackedStringArray(["--party=warrior"])),
		ScreenSweepScript.DEFAULT_SEED, "another tool's argument is not a seed")


func test_the_seed_argument_is_read_in_the_spelling_the_game_uses() -> void:
	assert_eq(ScreenSweepScript.seed_of(PackedStringArray(["--seed=0000ABCD"])),
		0xABCD, "the game's own seed field would read this as 0xABCD")
	assert_eq(ScreenSweepScript.seed_of(PackedStringArray(["--x", "--seed=1"])), 1,
		"the seed is found wherever it sits in the argument list")


func test_a_seed_that_is_not_hex_still_resolves_to_one_fixed_number() -> void:
	var a := ScreenSweepScript.seed_of(PackedStringArray(["--seed=not-hex"]))
	assert_eq(a, ScreenSweepScript.seed_of(PackedStringArray(["--seed=not-hex"])),
		"RunConfig.parse_seed hashes an unparsable seed rather than rerolling")
	assert_true(a >= 0, "the roster seed is masked to 31 bits, as PartySelect masks it")


func test_a_roster_rolled_from_the_default_seed_is_the_same_roster_twice() -> void:
	var first := PawnFactory.make_rolled_pawn(&"warrior", &"a", "A",
		ScreenSweepScript.DEFAULT_SEED)
	var second := PawnFactory.make_rolled_pawn(&"warrior", &"a", "A",
		ScreenSweepScript.DEFAULT_SEED)
	assert_eq(first.attribute_bonus, second.attribute_bonus,
		"the seed the sweep ships must roll one roster, not a family of them")
