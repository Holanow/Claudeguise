extends "res://Tests/TestCase.gd"


## Issue 621. Actions are `.tres` now, and a `.tres` stores an enum as its
## ORDINAL. Reordering `CG.DamageType` or `CG.Status` would silently repoint
## every one of the 38 files at a different value, and nothing else in the suite
## would notice. These pin the ordinals and the manifest that loads the files.

const ACTIONS_DIR := "res://Scripts/Content/Actions/"

## The literal ordinals every shipped `.tres` was written against. A new member
## may be APPENDED. Moving or removing one rewrites content that is not in this
## file, so it fails here first.
const DAMAGE_TYPE_ORDINALS := {
	"PHYSICAL": 0, "FIRE": 1, "WATER": 2, "AIR": 3,
	"EARTH": 4, "DIVINE": 5, "PROFANE": 6, "RAW": 7,
}

const STATUS_ORDINALS := {
	"SHIELD": 0, "BLEED": 1, "TAUNTED": 2, "BURN": 3, "HASTE": 4, "STUN": 5,
	"BLOCK": 6, "MARKED": 7, "POISON": 8, "SLOWED": 9, "TAUNTING": 10,
	"SHIELDING": 11, "SUSTAINING": 12,
}

func test_damage_type_ordinals_are_what_the_tres_files_were_written_against() -> void:
	for name in DAMAGE_TYPE_ORDINALS:
		assert_eq(CG.DamageType[name], DAMAGE_TYPE_ORDINALS[name],
			"CG.DamageType.%s moved. Every .tres under %s stores the ordinal, so this silently changes content." % [name, ACTIONS_DIR])

func test_status_ordinals_are_what_the_tres_files_were_written_against() -> void:
	for name in STATUS_ORDINALS:
		assert_eq(CG.Status[name], STATUS_ORDINALS[name],
			"CG.Status.%s moved. Every .tres under %s stores the ordinal, so this silently changes content." % [name, ACTIONS_DIR])

## The manifest is listed rather than scanned, so a file can be added and never
## loaded. This is the half that notices.
func test_every_action_tres_on_disk_is_in_the_manifest() -> void:
	var dir := DirAccess.open(ACTIONS_DIR)
	assert_not_null(dir, "no %s to walk" % ACTIONS_DIR)
	var on_disk: Array[String] = []
	for file in dir.get_files():
		if file.ends_with(".tres"):
			on_disk.append(ACTIONS_DIR + file)
	assert_true(on_disk.size() > 30, "only %d action files; this walk is wrong" % on_disk.size())
	for path in on_disk:
		assert_true(ActionLibrary.PATHS.has(path),
			"%s exists but ActionLibrary.PATHS does not list it, so nothing loads it" % path)
	assert_eq(ActionLibrary.PATHS.size(), on_disk.size(),
		"the manifest lists a path with no file behind it")

func test_a_files_name_is_its_action_id() -> void:
	for path in ActionLibrary.PATHS:
		var a: ActionDef = load(path)
		assert_not_null(a, "%s did not load as an ActionDef" % path)
		assert_eq(String(a.id), String(path).get_file().get_basename(),
			"%s holds an action whose id is '%s'" % [path, a.id])

func test_every_action_the_registry_knows_came_from_the_library() -> void:
	assert_eq(ActionLibrary.all_ids().size(), ActionLibrary.PATHS.size(),
		"the registry and the manifest disagree about how many actions exist")

## A `.tres` loaded twice is the SAME instance, so every unit in the game reads
## one object. Nothing writes an action any more, which is what makes that safe.
func test_the_registry_hands_out_one_shared_instance_per_action() -> void:
	var a := ActionLibrary.get_action(&"warrior_strike")
	assert_true(a.resource_path != "",
		"a registry action must be a loaded resource rather than a fixture")
	assert_true(a == ActionLibrary.get_action(&"warrior_strike"),
		"two lookups of one id must be the same instance, not a copy")

## A fixture composes an action the same way a `.tres` does. The four tests
## that used to sit here pinned the flat setters instead -- the seeded
## `HitEffect`, canonical order from any assignment order, zero-removes-the-part
## and authorability -- and issue 622 deleted the setters they were about.
func test_a_composed_action_carries_the_effects_it_was_given_in_order() -> void:
	var a := ActionDef.new()
	assert_eq(a.effects.size(), 0, "a bare ActionDef does nothing until it is composed")
	assert_true(a.targeting == null, "and reaches nowhere")
	var hit := HitEffect.new()
	hit.power_scale = 3.5
	a.effects = [hit, CleanseEffect.new()] as Array[AbilityEffect]
	assert_almost_eq(a.power_scale, 3.5, 0.0001, "the flat name still reads the composed value")
	assert_true(a.has_cleanse(), "and the second effect is there beside it")
