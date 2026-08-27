extends "res://Tests/TestCase.gd"

## Issue 434: the library is one list serving two orders. It is read top-down by
## a new player and it is priority order for the simulation, and the
## Geysermancer's first row -- "Blast the burning" -- is inert until a second
## row applies BURN. Since #399 the library is the only place a class explains
## itself, so a row that does nothing on its own must say so.

func _pawn(class_id: StringName) -> PawnData:
	return PawnFactory.make_starter_pawn(class_id, StringName("%s_0" % class_id), String(class_id).capitalize())

func _panel(pawn: PawnData) -> InspectPanel:
	var panel := InspectPanel.create()
	panel._ready()
	panel.open([pawn] as Array[PawnData])
	return panel

func _text_of(n: Node) -> String:
	var out := ""
	if n is Label:
		out += n.text + "\n"
	for c in n.get_children():
		out += _text_of(c)
	return out

func _row_for(panel: InspectPanel, pawn: PawnData, plan_id: StringName) -> Control:
	for plan in panel._library_rows(pawn):
		if plan.id == plan_id:
			return panel._library_row(pawn, plan)
	return null

## The row the issue is about: it needs BURN and another library row supplies
## it, so the note has to name both.
func test_a_row_that_needs_another_row_says_which_one() -> void:
	var pawn := _pawn(&"geysermancer")
	var panel := _panel(pawn)
	var row := _row_for(panel, pawn, &"geyser_blast_the_burning")
	assert_true(row != null, "the Geysermancer library still offers Blast the burning")
	var text := _text_of(row)
	assert_true(text.contains("Burn"), "the note must name the status: %s" % text)
	assert_true(text.contains("Scald the weakest"),
		"the note must name the row that supplies it: %s" % text)
	row.free()
	panel.free()

## Data-driven, so the next class to ship a dependency cannot render nothing:
## every dependency the content declares must produce a sentence. Only one
## exists today, and none of them has an empty `supplied_by`, so the
## "the fight supplies it" branch has no content to exercise it -- said in the
## PR rather than faked with a fixture.
func test_every_declared_dependency_reaches_the_screen() -> void:
	var seen := 0
	for class_id in ClassLibrary.all_ids():
		var deps := PresetPlans.row_dependencies(class_id)
		if deps.is_empty():
			continue
		var pawn := _pawn(class_id)
		var panel := _panel(pawn)
		for plan in panel._library_rows(pawn):
			if not deps.has(plan.id):
				continue
			seen += 1
			var row := _row_for(panel, pawn, plan.id)
			assert_true(_text_of(row).contains(InspectPanel.LIBRARY_NEEDS_MARK),
				"%s declares a dependency the library never says: %s" % [plan.id, _text_of(row)])
			row.free()
		panel.free()
	assert_true(seen > 0, "no library row declares a dependency, so this checks nothing")

## The negative, and it is the one that keeps the note meaningful: a row with
## no dependency at all says nothing extra.
func test_a_row_with_no_dependency_carries_no_note() -> void:
	var pawn := _pawn(&"warrior")
	var panel := _panel(pawn)
	var deps := PresetPlans.row_dependencies(&"warrior")
	for plan in panel._library_rows(pawn):
		if deps.has(plan.id):
			continue
		var row := panel._library_row(pawn, plan)
		assert_false(_text_of(row).contains(InspectPanel.LIBRARY_NEEDS_MARK),
			"a row that depends on nothing must not claim a dependency: %s" % _text_of(row))
		row.free()
	panel.free()

## Reading order stays priority order, and the heading says so. Rows are taken
## top-down and `_add_preset` appends, so the order they are listed in is the
## order they end up in -- which #430 measured: Blast below Scald falls from
## 481 casts to 18.
func test_taking_the_library_top_down_builds_the_measured_priority_order() -> void:
	var pawn := _pawn(&"geysermancer")
	var panel := _panel(pawn)
	var offered := panel._library_rows(pawn)
	for plan in offered:
		panel._add_preset(pawn, plan)
	var ids: Array[StringName] = []
	for p in pawn.plans:
		ids.append(p.id)
	var blast := ids.find(&"geyser_blast_the_burning")
	var scald := ids.find(&"geyser_scald_finisher")
	assert_true(blast >= 0 and scald >= 0, "both rows were taken: %s" % str(ids))
	assert_true(blast < scald,
		"taking the library top-down must not starve Blast: %s" % str(ids))
	panel.free()
