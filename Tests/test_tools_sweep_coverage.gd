extends "res://Tests/TestCase.gd"


## Every class must appear in some party the screenshot sweep photographs.

const ScreenSweepScript := preload("res://Tools/ScreenSweep.gd")


func _union(parties: Array) -> Array:
	var seen := []
	for party in parties:
		for id in party:
			if not seen.has(id):
				seen.append(id)
	return seen


func test_sweep_covers_every_registered_class() -> void:
	var ids := ClassLibrary.all_ids()
	var covered := _union(ScreenSweepScript.sweep_parties(ids))
	for id in ids:
		assert_true(covered.has(id), "class '%s' is never photographed by ScreenSweep" % id)


func test_the_warrior_is_photographed() -> void:
	# Issue 327: five classes sorted alphabetically, party size four, and the
	# Warrior is fifth. No whole-game screenshot ever contained one.
	var covered := _union(ScreenSweepScript.sweep_parties(ClassLibrary.all_ids()))
	assert_true(covered.has(&"warrior"), "the sweep still cannot reach a Warrior")


func test_five_classes_need_two_full_parties() -> void:
	var five: Array = [&"a", &"b", &"c", &"d", &"e"]
	var parties: Array = ScreenSweepScript.sweep_parties(five)
	assert_eq(parties.size(), 2, "five classes at four a party")
	assert_eq(_union(parties).size(), 5, "every class covered")
	for party in parties:
		assert_eq(party.size(), 4, "each shot is a full party")


func test_four_classes_need_one_party() -> void:
	var parties: Array = ScreenSweepScript.sweep_parties([&"a", &"b", &"c", &"d"])
	assert_eq(parties.size(), 1, "no second party when four fit")
	assert_eq(_union(parties).size(), 4, "every class covered")


func test_a_short_roster_is_not_padded_with_duplicates() -> void:
	var parties: Array = ScreenSweepScript.sweep_parties([&"a", &"b"])
	assert_eq(parties.size(), 1, "one party")
	assert_eq(parties[0], [&"a", &"b"], "padding never repeats a class")


func test_an_empty_roster_yields_no_parties() -> void:
	assert_eq(ScreenSweepScript.sweep_parties([]).size(), 0, "nothing to photograph")
