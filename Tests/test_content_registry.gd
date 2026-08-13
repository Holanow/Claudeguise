extends "res://Tests/TestCase.gd"

const Registry := preload("res://Scripts/Content/Registry.gd")

## Registry.all_enemy_ids(): the missing fourth sibling of all_class_ids/
## all_encounter_ids/all_equipment_ids, added for the level editor's
## bestiary picker. Its own file has no dedicated test yet, so these check
## the same properties the other three already rely on callers assuming:
## sorted, no duplicates, and every id actually resolves through
## Registry.get_enemy.

func test_all_enemy_ids_is_sorted() -> void:
	var ids := Registry.all_enemy_ids()
	var sorted_copy := ids.duplicate()
	sorted_copy.sort()
	assert_eq(ids, sorted_copy)


func test_all_enemy_ids_has_no_duplicates() -> void:
	var ids := Registry.all_enemy_ids()
	var seen := {}
	for id in ids:
		assert_false(seen.has(id), "duplicate enemy id %s" % id)
		seen[id] = true


func test_all_enemy_ids_is_not_empty() -> void:
	assert_true(Registry.all_enemy_ids().size() > 0, "expected at least one registered enemy")


func test_every_id_in_all_enemy_ids_resolves() -> void:
	for id in Registry.all_enemy_ids():
		assert_not_null(Registry.get_enemy(id), "all_enemy_ids returned %s but get_enemy could not resolve it" % id)


## Not every registered enemy has to be used by an encounter -- that gap is
## exactly why this function exists (see Registry.gd's own comment on it).
## This just confirms the two lists are not accidentally identical by
## construction, i.e. that all_enemy_ids really reads the enemy table and
## not something derived from encounters.
func test_all_enemy_ids_is_not_derived_from_encounters() -> void:
	var enemy_ids := Registry.all_enemy_ids()
	var siege_engine_registered := enemy_ids.has(&"siege_engine")
	assert_true(siege_engine_registered, "expected siege_engine (built mid-fight, never placed in a hand-written encounter) to still be registered")
