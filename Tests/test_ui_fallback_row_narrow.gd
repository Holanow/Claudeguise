extends "res://Tests/TestCase.gd"

## Issue 414: in the party screen's column the fallback row autowrapped into a
## column of ragged fragments. Measured on the running app at 1280x720 before
## this: 187px tall, three chips 45, 69 and 91px wide, 11 wrapped lines for one
## sentence. Since #399 it is the only thing on that panel for a pawn with no
## rows.

func _pawn(class_id: StringName) -> PawnData:
	return PawnFactory.make_starter_pawn(class_id, StringName("%s_0" % class_id), String(class_id).capitalize())

func _wide(pawn: PawnData) -> InspectPanel:
	var panel := InspectPanel.create()
	panel._ready()
	panel.open([pawn] as Array[PawnData])
	return panel

func _narrow(pawn: PawnData) -> InspectPanel:
	var panel := InspectPanel.create()
	panel._ready()
	panel.embed()
	panel.show_pawn(pawn)
	return panel

func _fallback_rows(panel: InspectPanel) -> Array:
	var out: Array = []
	for n in _walk(panel):
		if n is Control and n.name.begins_with(InspectPanel.FALLBACK_ROW_NAME):
			out.append(n)
	return out

func _walk(n: Node, out: Array = []) -> Array:
	out.append(n)
	for c in n.get_children():
		_walk(c, out)
	return out

func _panels_in(n: Node, out: Array = []) -> Array:
	if n is PanelContainer:
		out.append(n)
	for c in n.get_children():
		_panels_in(c, out)
	return out

func _text_of(n: Node) -> String:
	var out := ""
	if n is Label:
		out += n.text + "\n"
	for c in n.get_children():
		out += _text_of(c)
	return out

## The same split `_assemble_row` and `_assemble_library_row` already make:
## three chips where there is room for three, one sentence where there is not.
func test_the_fallback_row_is_one_sentence_in_a_column_and_three_chips_wide() -> void:
	var pawn := _pawn(&"warrior")

	var wide := _wide(pawn)
	var wide_rows := _fallback_rows(wide)
	assert_true(wide_rows.size() > 0, "the wide screen has a fallback row")
	assert_eq(_panels_in(wide_rows[0]).size(), 3, "wide, skill/target/condition are three chips")

	var narrow := _narrow(pawn)
	var narrow_rows := _fallback_rows(narrow)
	assert_eq(narrow_rows.size(), wide_rows.size(), "the same rows are described either way")
	assert_eq(_panels_in(narrow_rows[0]).size(), 0, "embedded, no autowrapping chips")

	wide.free()
	narrow.free()

## Compressing the row must not drop a fact: the same three things it says in
## three columns, said in one line.
func test_the_narrow_sentence_still_carries_every_fact() -> void:
	var pawn := _pawn(&"warrior")
	var wide := _wide(pawn)
	var narrow := _narrow(pawn)

	var sentence := _text_of(_fallback_rows(narrow)[0])
	for fact in _text_of(_fallback_rows(wide)[0]).split("\n", false):
		assert_true(sentence.contains(fact),
			"the sentence dropped '%s': %s" % [fact, sentence])

	wide.free()
	narrow.free()

## A pawn with no rows at all is the case #399 made normal, and the case the
## issue is about: the fallback row is then the whole panel.
func test_a_pawn_with_no_rows_still_gets_the_short_fallback() -> void:
	var pawn := _pawn(&"warrior")
	pawn.plans = []
	var narrow := _narrow(pawn)
	var rows := _fallback_rows(narrow)
	assert_true(rows.size() > 0, "a pawn with no rows must still be described")
	assert_eq(_panels_in(rows[0]).size(), 0, "and described in one sentence, not four chips")
	narrow.free()
