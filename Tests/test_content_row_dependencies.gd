extends "res://Tests/TestCase.gd"


## Issue 434. A library row that needs a status nobody has applied yet does
## nothing on its own, and until now the library said so nowhere.


func test_blast_the_burning_declares_burn_and_names_scald_as_its_supplier() -> void:
	var deps := PresetPlans.row_dependencies(&"geysermancer")
	assert_true(deps.has(&"geyser_blast_the_burning"),
		"the row that eats BURN declares no dependency: %s" % [deps])
	var d: Dictionary = deps[&"geyser_blast_the_burning"]
	assert_eq(int(d["status"]), int(CG.Status.BURN), "wrong status declared: %s" % [d])
	assert_eq(d["supplied_by"], [&"geyser_scald_finisher"] as Array[StringName],
		"wrong supplier: %s" % [d])


## The negative half. A row whose condition holds against an untouched enemy is
## not a dependency, or every Claw and every in-range row would declare one.
func test_a_row_that_works_alone_declares_nothing() -> void:
	for class_id in Registry.all_class_ids():
		var deps := PresetPlans.row_dependencies(class_id)
		for plan in PresetPlans.for_class(class_id):
			if plan.id == &"geyser_blast_the_burning":
				continue
			assert_false(deps.has(plan.id),
				"%s declares a dependency it does not have: %s" % [plan.id, deps.get(plan.id)])


## `enemy_lacks_status` is satisfied by an enemy nobody has touched, so the
## Abomination's Claw row is not waiting on anything.
func test_a_negative_status_condition_is_not_a_dependency() -> void:
	var claw: Plan = _plan(&"abomination", &"abomination_claw_the_unpoisoned")
	assert_eq(PresetPlans.required_status(claw), -1,
		"a lacks-status row read as needing the status it avoids")


## The derivation reads the rows rather than a hand-written table, so it moves
## when they do. Repoint the Blast row's condition and the declaration follows.
func test_the_declaration_follows_the_row_rather_than_a_table() -> void:
	var blast: Plan = _plan(&"geysermancer", &"geyser_blast_the_burning")
	assert_eq(PresetPlans.required_status(blast), int(CG.Status.BURN))
	(blast.condition as EnemyHasStatusBlock).status = CG.Status.POISON
	(blast.blocks[0] as TargetEnemyWithStatusBlock).status = CG.Status.POISON
	assert_eq(PresetPlans.required_status(blast), int(CG.Status.POISON),
		"the requirement is not read off the row")


## The supplier side is read off the action, not off the row's name.
func test_scald_is_what_applies_burn_and_blast_is_not() -> void:
	var scald: Plan = _plan(&"geysermancer", &"geyser_scald_finisher")
	assert_true(PresetPlans.applied_statuses(scald).has(int(CG.Status.BURN)),
		"Scald no longer applies BURN")
	var blast: Plan = _plan(&"geysermancer", &"geyser_blast_the_burning")
	assert_false(PresetPlans.applied_statuses(blast).has(int(CG.Status.BURN)),
		"Blast reads as supplying the BURN it consumes")


func _plan(class_id: StringName, plan_id: StringName) -> Plan:
	for p in PresetPlans.for_class(class_id):
		if p.id == plan_id:
			return p
	fail("no plan %s in %s's library" % [plan_id, class_id])
	return null
