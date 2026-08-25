extends "res://Tests/TestCase.gd"

## **Issue 412: the library existed in content and the editor could not offer
## it.** `PawnFactory` ships zero rows (#404) and `InspectPanel` never named
## `PresetPlans`, so fifteen starting actions were reachable only by composing
## them from four blank pickers. These assert the door, and the last one asserts
## a row taken through it reaches a fight.

func _pawn(class_id: StringName) -> PawnData:
	return PawnFactory.make_starter_pawn(class_id, StringName("%s_0" % class_id), String(class_id).capitalize())

func _panel(pawn: PawnData) -> InspectPanel:
	var panel := InspectPanel.create()
	panel._ready()
	panel.open([pawn] as Array[PawnData])
	return panel

func _buttons(node: Node, out: Array = []) -> Array:
	if node is Button:
		out.append(node)
	for c in node.get_children():
		_buttons(c, out)
	return out

func _named(node: Node, text: String) -> Button:
	for b in _buttons(node):
		if b.text == text:
			return b
	return null

func _adds(panel: InspectPanel) -> Array:
	return _buttons(panel._detail_box).filter(func(b): return b.text == InspectPanel.LIBRARY_ADD)

## The premise this issue rests on, checked rather than assumed: a fresh pawn
## carries no rows and the class has a library to offer it.
func test_a_starting_pawn_has_no_rows_and_a_library_that_does() -> void:
	for class_id in [&"warrior", &"priest", &"geysermancer", &"siege_master", &"abomination"]:
		var pawn := _pawn(class_id)
		assert_eq(pawn.plans.size(), 0, "%s must ship with no plan rows" % class_id)
		assert_true(PresetPlans.for_class(class_id).size() > 0, "%s must have library rows to offer" % class_id)

## The empty state teaches, which is where the screen was showing nothing.
func test_the_library_is_open_on_a_pawn_with_no_rows() -> void:
	var pawn := _pawn(&"priest")
	var panel := _panel(pawn)
	assert_true(panel._library_open, "a pawn with no rows opens on its library")
	var adds := _adds(panel)
	assert_eq(adds.size(), PresetPlans.for_class(&"priest").size(),
		"every library row must be offered, one Add each")
	assert_true(_text_of(panel._detail_box).contains(InspectPanel.LIBRARY_EMPTY_STATE),
		"the empty state must say where a row comes from")
	panel.free()

## What a row shows before you take it: the same three columns, in the same
## words, as the editable row it becomes.
func test_a_library_row_reads_as_the_sentence_it_will_become() -> void:
	var pawn := _pawn(&"abomination")
	var panel := _panel(pawn)
	var immolate = _preset(&"abomination", &"abomination_immolate_dump")
	var texts := panel._library_row_texts(immolate)
	assert_eq(texts.size(), 3, "skill, target, condition")
	assert_eq(texts[0], "Immolate", "the skill is named, not its id")
	assert_eq(texts[1], "Self")
	assert_eq(texts[2], "An enemy within 90 units")
	assert_true(_text_of(panel._detail_box).contains("Immolate"),
		"and it is on the screen, not only available from the function")
	panel.free()

## The constraint from the issue, stated as a test because it is what keeps the
## budget checkable: a preset costs its blocks, the same as building it by hand.
func test_adding_a_preset_charges_exactly_what_its_blocks_cost() -> void:
	var pawn := _pawn(&"warrior")
	var panel := _panel(pawn)
	var before := panel._blocks_used(pawn)
	var row = panel._library_rows(pawn)[0]
	var cost: int = row.block_count()
	panel._add_preset(pawn, row)
	assert_eq(pawn.plans.size(), 1, "the row must land on the pawn")
	assert_eq(panel._blocks_used(pawn) - before, cost,
		"a preset must charge its own block count and nothing else")
	assert_eq(pawn.plans[0].id, row.id, "the row taken is the row offered")
	panel.free()

## A row already on the pawn is not offered again, so pressing Add twice cannot
## charge twice for the same behaviour.
func test_a_taken_row_leaves_the_library() -> void:
	var pawn := _pawn(&"warrior")
	var panel := _panel(pawn)
	var offered := panel._library_rows(pawn).size()
	panel._add_preset(pawn, panel._library_rows(pawn)[0])
	panel._build_detail(pawn)
	assert_eq(panel._library_rows(pawn).size(), offered - 1, "the taken row must leave the library")
	assert_eq(_adds(panel).size(), offered - 1, "and leave the screen with it")
	panel.free()

## #392's rule: refused with the reason beside it, never silently.
func test_an_unaffordable_row_is_disabled_and_says_why() -> void:
	var pawn := _pawn(&"priest")
	## On the pawn, not on `pawn_class`: the ClassDef is the Registry's own
	## instance and every later test in the run would inherit the change.
	pawn.attribute_bonus[CG.Attribute.WIS] = 1 - Balance.plan_block_budget(pawn)
	assert_eq(Balance.plan_block_budget(pawn), 1, "the fixture must actually be broke")
	var panel := _panel(pawn)
	var adds := _adds(panel)
	assert_true(adds.size() > 0, "the rows are still listed, not hidden")
	for add in adds:
		assert_true(add.disabled, "1 block of budget cannot pay for a 2-block row")
		assert_true(add.tooltip_text.contains("costs"), "the reason must be readable: '%s'" % add.tooltip_text)
	var row = panel._library_rows(pawn)[0]
	panel._add_preset(pawn, row)
	assert_eq(pawn.plans.size(), 0, "the guard must hold when the function is called directly too")
	panel.free()

## The negative half. A library that refuses everything would pass the test
## above and be useless.
func test_an_affordable_row_is_live() -> void:
	var pawn := _pawn(&"priest")
	var panel := _panel(pawn)
	var adds := _adds(panel)
	assert_true(adds.size() > 0)
	for add in adds:
		assert_false(add.disabled, "a starting Priest's WIS pays for any one row")
	panel.free()

func test_the_library_button_opens_and_closes_it() -> void:
	var pawn := _pawn(&"warrior")
	pawn.plans = [PresetPlans.for_class(&"warrior")[0]] as Array[Plan]
	var panel := _panel(pawn)
	assert_false(panel._library_open, "a pawn that already has rows does not open on the library")
	assert_eq(_adds(panel).size(), 0, "and the rows are not listed")

	var button := _named(panel._detail_box, InspectPanel.LIBRARY_OPEN % 3)
	assert_not_null(button, "the door has to be a control, found: %s" %
		str(_buttons(panel._detail_box).map(func(b): return b.text)))
	button.emit_signal("pressed")
	panel._build_detail(pawn)
	assert_true(panel._library_open)
	assert_eq(_adds(panel).size(), 3, "the three rows this Warrior has not taken; #592 took Execute out of the library")

	_named(panel._detail_box, InspectPanel.LIBRARY_CLOSE).emit_signal("pressed")
	panel._build_detail(pawn)
	assert_eq(_adds(panel).size(), 0)
	panel.free()

## A pawn holding every row of its class has an empty library, and the button
## says so rather than opening onto nothing.
func test_an_exhausted_library_is_disabled_with_a_reason() -> void:
	var pawn := _pawn(&"siege_master")
	pawn.plans = PresetPlans.for_class(&"siege_master")
	var panel := _panel(pawn)
	var button := _named(panel._detail_box, InspectPanel.LIBRARY_OPEN % 0)
	assert_not_null(button)
	assert_true(button.disabled)
	assert_eq(button.tooltip_text, InspectPanel.LIBRARY_EXHAUSTED)
	panel.free()

## And the row taken from the library reaches the simulation. This is the half
## `test_plans_edit_reaches_the_fight.gd` is the precedent for: an edit accepted
## and echoed back that leaves the fight byte-identical is not an edit.
func test_a_row_taken_from_the_library_changes_the_fight() -> void:
	var bare := _fight(null)
	var pawn := _pawn(&"abomination")
	var panel := _panel(pawn)
	var immolate = null
	for row in panel._library_rows(pawn):
		if row.id == &"abomination_immolate_dump":
			immolate = row
	assert_not_null(immolate, "the library must offer Immolate")
	panel._add_preset(pawn, immolate)
	var taken := _fight(pawn.plans[0])
	panel.free()

	assert_eq(bare["casts"], 0, "with no rows nothing can fire from a plan")
	assert_true(taken["casts"] > 0,
		"the row taken from the library must fire; it fired %d times" % taken["casts"])
	assert_ne(bare["signature"], taken["signature"],
		"the same seed produced the same event stream with and without the row, so the library never reached the simulation")

## Embedded in the party screen's column the three chips cannot line up:
## `_fixed_chip` autowraps, and on a real capture one row stood five lines tall
## and two of them filled the panel. One sentence instead, carrying every fact
## the three columns carry.
func test_the_embedded_row_is_one_sentence_and_the_wide_row_is_three_columns() -> void:
	var pawn := _pawn(&"abomination")
	var immolate = _preset(&"abomination", &"abomination_immolate_dump")

	var wide := _panel(pawn)
	var wide_row := wide._library_row(pawn, immolate)
	assert_eq(_panels_in(wide_row).size(), 3, "wide, skill/target/condition are three chips")

	var narrow := InspectPanel.create()
	narrow._ready()
	narrow.embed()
	narrow.show_pawn(pawn)
	var narrow_row := narrow._library_row(pawn, immolate)
	assert_eq(_panels_in(narrow_row).size(), 0, "embedded, no autowrapping chips")
	var sentence := _text_of(narrow_row)
	for fact in ["Immolate", "Self", "An enemy within 90 units"]:
		assert_true(sentence.contains(fact), "the sentence must still carry '%s': %s" % [fact, sentence])

	wide_row.free()
	narrow_row.free()
	wide.free()
	narrow.free()

## Both doors are on the embedded screen too, where the column is narrow enough
## that a third control in the header pushed "+ Add a plan" off the edge.
func test_both_buttons_are_on_the_embedded_screen() -> void:
	var pawn := _pawn(&"warrior")
	var panel := InspectPanel.create()
	panel._ready()
	panel.embed()
	panel.show_pawn(pawn)
	var texts := _buttons(panel._detail_box).map(func(b): return b.text)
	assert_true(texts.has("+ Add a plan"), "found: %s" % str(texts))
	assert_true(texts.has(InspectPanel.LIBRARY_CLOSE), "found: %s" % str(texts))
	panel.free()

# ---------------------------------------------------------------------------

const _SEED := 11

func _panels_in(node: Node, out: Array = []) -> Array:
	if node is PanelContainer:
		out.append(node)
	for c in node.get_children():
		_panels_in(c, out)
	return out

func _preset(class_id: StringName, plan_id: StringName):
	for p in PresetPlans.for_class(class_id):
		if p.id == plan_id:
			return p
	return null

func _text_of(node: Node) -> String:
	var out := ""
	if node is Label:
		out += node.text + "\n"
	for c in node.get_children():
		out += _text_of(c)
	return out

## One Abomination against three goblins, carrying `plan` or nothing at all.
## Goblins because they do not taunt: the compulsion branch runs before the plan
## layer and would mask what this measures.
func _fight(plan) -> Dictionary:
	var pawn := _pawn(&"abomination")
	var rows: Array[Plan] = []
	if plan != null:
		rows.append(plan)
	pawn.plans = rows
	var encounter := Encounter.new()
	encounter.id = &"test_preset_library"
	encounter.party_spawns = [Vector2(-60.0, 0.0)] as Array[Vector2]
	encounter.enemy_spawns = [
		{"enemy_id": &"goblin", "position": Vector2(20.0, -20.0)},
		{"enemy_id": &"goblin", "position": Vector2(20.0, 20.0)},
		{"enemy_id": &"goblin", "position": Vector2(40.0, 0.0)},
	]
	var state := CombatSim.build([pawn] as Array[PawnData], encounter, _SEED)
	CombatSim.run(state)

	var casts := 0
	var parts := PackedStringArray()
	for e in state.events:
		if e.source_plan != &"":
			casts += 1
		parts.append("%d:%d:%d:%d:%s:%d" % [e.tick, e.kind, e.source_id, e.target_id, e.action_id, e.amount])
	return {"casts": casts, "signature": "|".join(parts)}
