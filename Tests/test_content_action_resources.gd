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
	assert_eq(Registry.all_action_ids().size(), ActionLibrary.PATHS.size(),
		"the registry and the manifest disagree about how many actions exist")

## A `.tres` loaded twice is the SAME instance, so a write through the flat
## bridge would change the action for every unit in the game. It refuses, and
## `resource_path` is what tells it apart from a fixture built with `.new()`.
func test_the_registry_hands_out_one_shared_instance_per_action() -> void:
	var a := Registry.get_action(&"warrior_strike")
	assert_true(a.resource_path != "",
		"a registry action must be a loaded resource, or the mutation guard cannot see it")
	assert_true(a == Registry.get_action(&"warrior_strike"),
		"two lookups of one id must be the same instance, not a copy")

func test_a_fixture_built_with_new_is_still_authorable() -> void:
	var a := ActionDef.new()
	assert_eq(a.resource_path, "", "a fresh ActionDef is not a loaded resource")
	a.power_scale = 3.5
	assert_almost_eq(a.power_scale, 3.5, 0.0001, "a fixture may still be composed field by field")

## A bare `ActionDef.new()` used to deal physical damage at 1.0 with no fields
## set, and 11 fixtures still rely on that.
func test_a_bare_action_still_carries_one_hit() -> void:
	var a := ActionDef.new()
	assert_eq(a.effects.size(), 1, "one HitEffect and nothing else")
	assert_almost_eq(a.power_scale, 1.0, 0.0001)
	assert_eq(a.damage_type, CG.DamageType.PHYSICAL)
	assert_false(a.heals)

## The sim runs `effects` in list order, so the order may not depend on the
## order a fixture happened to assign fields in.
func test_effects_land_in_canonical_order_whatever_order_they_are_authored_in() -> void:
	var a := ActionDef.new()
	a.restores_resource = 3
	a.cleanses_harmful = true
	a.pull_distance = 100.0
	a.applies_status_enabled = true
	var kinds: Array[String] = []
	for fx in a.effects:
		kinds.append(fx.get_script().get_global_name())
	assert_eq(kinds, ["HitEffect", "StatusEffect", "PullEffect", "CleanseEffect", "RestoreEffect"],
		"authored back to front, resolved front to back")

## The old fields were value-gated: a speed of 0.0 meant no projectile at all,
## not a shot that never arrives. The sim now checks presence, so the bridge has
## to remove the part rather than leave a zeroed one behind.
func test_a_zero_value_removes_the_part_rather_than_zeroing_it() -> void:
	var a := ActionDef.new()
	a.projectile_speed = 30.0
	assert_not_null(a.delivery)
	a.projectile_speed = 0.0
	assert_true(a.delivery == null, "speed 0 must mean no delivery, not a delivery at 0")
	a.pull_distance = 50.0
	assert_not_null(a.pull_effect())
	a.pull_distance = 0.0
	assert_true(a.pull_effect() == null, "a pull of 0 still stuns if the effect is left in place")
