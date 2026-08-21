extends "res://Tests/TestCase.gd"

## Issue 379 step 3. `CombatSim._decide_phase` checks `_compelling_taunter`
## **before** it calls the plan layer, so while TAUNTED a pawn's rows are not
## outranked -- they are not consulted. The screen went on drawing five live
## rows with `ready` and `waiting` beside them, which is what cost a blind
## playtester their trust in the whole editor.

func _make_pawn() -> PawnData:
	var cls := ClassDef.new()
	cls.id = &"test_class"
	cls.display_name = "Test Class"
	cls.starting_actions = [&"test_swing"]
	cls.base_attributes = {CG.Attribute.WIS: 8}
	var pawn := PawnData.new()
	pawn.id = &"test_pawn"
	pawn.display_name = "Test Pawn"
	pawn.pawn_class = cls
	return pawn

func _make_plan(label: String) -> Plan:
	var plan := Plan.new()
	plan.id = StringName(label.to_snake_case())
	plan.display_name = label
	return plan

func _unit(id: int, team: CG.Team, display_name: String) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.display_name = display_name
	u.hp = 50
	u.hp_max = 50
	u.position = Vector2(float(id) * 40.0, 0.0)
	u.radius = 22.0
	return u

## A pawn with two rows, in a live fight, taunted by "The Brute" unless
## `taunted` is false.
func _panel(taunted: bool, ticks_left: int = 45):
	var pawn := _make_pawn()
	pawn.plans = [_make_plan("First"), _make_plan("Second")]
	var unit := _unit(0, CG.Team.PLAYER, "Test Pawn")
	unit.pawn = pawn
	var brute := _unit(1, CG.Team.ENEMY, "The Brute")
	var state := CombatState.new(0)
	state.units = [unit, brute]
	state.tick = 100
	if taunted:
		unit.statuses[CG.Status.TAUNTED] = state.tick + ticks_left
		unit.status_magnitude[CG.Status.TAUNTED] = float(brute.id)
	var panel := InspectPanel.create()
	panel._ready()
	panel.open([pawn], state)
	return panel

## A plan row is the row carrying its own Remove button, the same definition
## `test_ui_inspect_panel.gd` uses.
func _plan_rows(panel) -> Array:
	var out := []
	for child in panel._detail_box.get_children():
		if _buttons_named(child, "X"):
			out.append(child)
	return out

func _buttons_named(node: Node, text: String) -> bool:
	if node is Button and node.text == text:
		return true
	for c in node.get_children():
		if _buttons_named(c, text):
			return true
	return false

func _labels(node: Node) -> String:
	var out := ""
	if node is Label:
		out += node.text + " "
	for child in node.get_children():
		out += _labels(child)
	return out

## ---------------------------------------------------------------------------
## The banner

func test_a_taunted_pawn_carries_a_banner_over_its_plans() -> void:
	var panel = _panel(true)
	var text := _labels(panel._detail_box)
	assert_true(text.contains(InspectPanel.TAUNT_BANNER_MARK), text)
	panel.free()

func test_the_banner_names_the_taunter_and_how_long_is_left() -> void:
	var panel = _panel(true, 45)
	var text := _labels(panel._detail_box)
	assert_true(text.contains("The Brute"), "the player has to know who did it: %s" % text)
	assert_true(text.contains("3.0s"), "45 ticks at 15/s is 3.0s: %s" % text)
	panel.free()

## The whole point: not "outranked by a row above", not consulted.
func test_the_banner_says_the_rows_are_not_read_at_all() -> void:
	var panel = _panel(true)
	var text := _labels(panel._detail_box)
	assert_true(text.contains("None of the rows below are read"), text)
	panel.free()

## The verdict key explains three words. While taunted no row carries one, so
## the key is explaining something that is not on the screen.
func test_the_verdict_key_is_not_shown_while_the_pawn_is_taunted() -> void:
	var panel = _panel(true)
	var text := _labels(panel._detail_box)
	assert_false(text.contains("Right now:"), text)
	panel.free()

func test_the_verdict_key_is_shown_in_a_live_fight_that_is_not_taunted() -> void:
	var panel = _panel(false)
	assert_true(_labels(panel._detail_box).contains("Right now:"))
	panel.free()

## The negative, and it is the one that matters. A banner that is always there
## is furniture within a session.
func test_an_untaunted_pawn_carries_no_banner() -> void:
	var panel = _panel(false)
	var text := _labels(panel._detail_box)
	assert_false(text.contains(InspectPanel.TAUNT_BANNER_MARK), text)
	panel.free()

func test_between_fights_there_is_no_banner() -> void:
	var pawn := _make_pawn()
	pawn.plans = [_make_plan("First")]
	var panel := InspectPanel.create()
	panel._ready()
	panel.open([pawn])
	var text := _labels(panel._detail_box)
	assert_false(text.contains(InspectPanel.TAUNT_BANNER_MARK), text)
	panel.free()

## A taunter that died the same tick leaves the status behind for one decide
## phase. The banner must still say something rather than name a null.
func test_a_banner_with_no_taunter_left_still_reads() -> void:
	var pawn := _make_pawn()
	pawn.plans = [_make_plan("First")]
	var unit := _unit(0, CG.Team.PLAYER, "Test Pawn")
	unit.pawn = pawn
	var state := CombatState.new(0)
	state.units = [unit]
	state.tick = 100
	unit.statuses[CG.Status.TAUNTED] = 145
	unit.status_magnitude[CG.Status.TAUNTED] = 99.0
	var panel := InspectPanel.create()
	panel._ready()
	panel.open([pawn], state)
	var text := _labels(panel._detail_box)
	assert_true(text.contains(InspectPanel.TAUNT_BANNER_MARK), text)
	panel.free()

## ---------------------------------------------------------------------------
## And the lie the banner exists to stop

## `ready` beside a row nobody reads is the sentence that cost the playtester
## their trust: they raised a threshold, the fight came out byte-identical, and
## concluded "don't bother touching the numbers".
func test_no_plan_row_claims_ready_or_waiting_while_the_pawn_is_taunted() -> void:
	var panel = _panel(true)
	for row in _plan_rows(panel):
		var text := _labels(row)
		for word in [InspectPanel.VERDICT_READY, InspectPanel.VERDICT_WAITING,
				InspectPanel.VERDICT_ACTING]:
			assert_false(text.contains(word),
				"'%s' on a row the simulation never reads: %s" % [word, text])
	panel.free()

## The pair, in the same fixture with one field changed: untaunted, the rows
## must still carry a verdict, or the assertion above is passed by a panel that
## never prints one.
func test_the_same_rows_untaunted_still_carry_a_verdict() -> void:
	var panel = _panel(false)
	var found := false
	for row in _plan_rows(panel):
		var text := _labels(row)
		if text.contains(InspectPanel.VERDICT_READY) or text.contains(InspectPanel.VERDICT_WAITING):
			found = true
	assert_true(found, "untaunted, a live fight must still mark its rows")
	panel.free()
