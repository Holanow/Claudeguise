extends "res://Tests/TestCase.gd"

const BattleScene := preload("res://Scenes/Battle.tscn")

## Issue 442. Three end-of-fight statements that contradicted what was on
## screen beside them, from the seventh blind playtest.

func _pawn_unit(id: int, hp: int, name: String) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = CG.Team.PLAYER
	u.hp = hp
	u.hp_max = 10
	u.alive = hp > 0
	u.display_name = name
	u.pawn = PawnFactory.make_starter_pawn(&"warrior", StringName("p%d" % id), name)
	return u

func _summon_unit(id: int, name: String = "Siege Engine") -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = CG.Team.PLAYER
	u.hp = 30
	u.hp_max = 30
	u.alive = true
	u.enemy_id = &"siege_engine"
	u.display_name = name
	return u

## The fight the playtester watched: every pawn dead, two engines at full
## health, and the card said "None of your party survived."
func _wipe_with_engines() -> CombatState:
	var state := CombatState.new(0)
	state.units.append(_pawn_unit(0, 0, "Siege Master"))
	state.units.append(_pawn_unit(1, 0, "Warrior"))
	state.units.append(_summon_unit(2))
	state.units.append(_summon_unit(3))
	return state

# ---------------------------------------------------------------------------
# 1. The card names what it counted
# ---------------------------------------------------------------------------

## It counts pawns and it said "party", while two units of the player's own
## team stood at full health forty pixels away. Saying "pawns" is true under
## either reading of "your party" and settles neither.
func test_the_card_names_pawns_because_pawns_are_what_it_counts() -> void:
	var view = BattleScene.instantiate()
	view._ready()
	view.state = _wipe_with_engines()
	var summary: String = view._cost_summary()
	assert_true(summary.contains("pawn"), summary)
	assert_false(summary.to_lower().contains("party"),
		"the card counts pawns, and a summon is on the player's team: %s" % summary)
	view.free()

func test_a_full_survival_names_pawns_too() -> void:
	var view = BattleScene.instantiate()
	view._ready()
	var state := CombatState.new(0)
	state.units.append(_pawn_unit(0, 10, "Warrior"))
	state.units.append(_summon_unit(1))
	view.state = state
	var summary: String = view._cost_summary()
	assert_true(summary.contains("pawn"), summary)
	assert_false(summary.to_lower().contains("party"), summary)
	view.free()

## The count itself must not move. A summon is not a pawn and never was one.
func test_the_engines_are_still_not_counted_as_pawns() -> void:
	var view = BattleScene.instantiate()
	view._ready()
	view.state = _wipe_with_engines()
	var summary: String = view._cost_summary()
	assert_false(summary.contains("4"), "two pawns died, not four: %s" % summary)
	assert_true(summary.contains("Siege Master") and summary.contains("Warrior"), summary)
	view.free()

# ---------------------------------------------------------------------------
# 2. No countdown after the fight is over
# ---------------------------------------------------------------------------

func _unit_on_cooldown(state: CombatState) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = 7
	u.team = CG.Team.PLAYER
	u.hp = 10
	u.hp_max = 10
	u.alive = true
	u.display_name = "Warrior"
	u.pawn = PawnFactory.make_starter_pawn(&"warrior", &"w", "Warrior")
	u.actions = [&"warrior_second_wind"]
	u.cooldowns[&"warrior_second_wind"] = state.tick + 400
	state.units.append(u)
	return u

## The negative half first: while the fight is running the countdown is the
## whole point of the chip and must still be there.
func test_a_running_fight_still_counts_a_cooldown_down() -> void:
	var state := CombatState.new(0)
	var u := _unit_on_cooldown(state)
	assert_eq(TeamStatusView.cooldowns_for(state, u).size(), 1)
	assert_eq(TeamStatusView.cooldown_summary(state, u), "")

## A countdown is a statement about what this unit does next, and once the
## fight has resolved there is no next. The playtester read a 29.1s countdown
## beside a card saying the fight took 15.6s and ended.
func test_no_cooldown_is_offered_once_the_fight_has_resolved() -> void:
	var state := CombatState.new(0)
	var u := _unit_on_cooldown(state)
	state.outcome = CombatState.Outcome.ENEMY_WIN
	assert_true(TeamStatusView.cooldowns_for(state, u).is_empty(),
		"a resolved fight has no next action to wait for")
	assert_eq(TeamStatusView.cooldown_summary(state, u), "",
		"and 'All ready' is just as false once nothing can act")

## Through the panel, not the function under it.
func test_the_panel_draws_no_cooldown_chip_after_the_fight() -> void:
	var panel := TeamStatusView.new()
	panel._ready()
	var state := CombatState.new(0)
	var u := _unit_on_cooldown(state)
	panel.sync(state)
	assert_eq(_visible_cooldown_chips(panel), 1, "the fight is live, so the chip is drawn")
	state.outcome = CombatState.Outcome.ENEMY_WIN
	panel.sync(state)
	assert_eq(_visible_cooldown_chips(panel), 0, "the fight is over, so the chip is not")
	panel.free()

func _visible_cooldown_chips(panel: TeamStatusView) -> int:
	var shown := 0
	for row in panel._row_by_id.values():
		if bool(row.get_meta("summon")):
			continue
		for chip in row.get_meta("cooldown_chips"):
			if chip.visible:
				shown += 1
	return shown

# ---------------------------------------------------------------------------
# 3. Three strings on the same pixels
# ---------------------------------------------------------------------------

## The card's prose is centred and the team panel is pinned to the right, so
## the widest the prose may be is twice the gap from the screen's centre to
## the panel's left edge. Checked as arithmetic at the two sizes the project
## ships, the way `compute_layout` is.
func test_the_end_cards_prose_never_reaches_the_team_panel() -> void:
	var sizes: Array[Vector2] = [Vector2(1280.0, 720.0), Vector2(1600.0, 900.0), Vector2(844.0, 390.0)]
	for size in sizes:
		var width := BattleView.end_text_width(size)
		var right_edge := size.x * 0.5 + width * 0.5
		var panel_left: float = size.x + CombatLogView.LOG_MARGIN - TeamStatusView.PANEL_WIDTH
		assert_true(right_edge <= panel_left,
			"at %s the prose reaches %.1f and the panel starts at %.1f" % [size, right_edge, panel_left])

## And the label has to be wired to it, or the number above is arithmetic
## about nothing.
func test_the_card_wraps_its_prose_rather_than_running_past_it() -> void:
	var view = BattleScene.instantiate()
	view._ready()
	view.state = _wipe_with_engines()
	view._show_outcome()
	for label in [view._end_cost_label, view._end_prompt_label]:
		assert_ne(label.autowrap_mode, TextServer.AUTOWRAP_OFF,
			"a label that cannot wrap prints past its own box")
		assert_true(label.custom_minimum_size.x > 0.0,
			"and one with no width to wrap inside never wraps")
	view.free()

## The duration used to print through the last name in the casualty list. It is
## its own line now, so no measurement of the list's width can push it into
## anything.
func test_the_duration_is_not_on_the_casualty_lists_line() -> void:
	var view = BattleScene.instantiate()
	view._ready()
	view.state = _wipe_with_engines()
	view._show_outcome()
	var carried := false
	for line in view._end_cost_label.text.split("\n"):
		if line.contains("You lost"):
			carried = true
			assert_false(line.contains("lasted"),
				"the duration belongs on its own line: %s" % line)
	assert_true(carried, "no casualty list, so the overlap case went unexercised")
	assert_true(view._end_cost_label.text.contains("The fight lasted"),
		"the duration still has to be on the card: %s" % view._end_cost_label.text)
	view.free()
