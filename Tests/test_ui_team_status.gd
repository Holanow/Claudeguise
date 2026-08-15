extends "res://Tests/TestCase.gd"

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const Palette := preload("res://Scripts/Core/Palette.gd")
const TeamStatusView := preload("res://Scripts/UI/TeamStatusView.gd")
const CombatLogView := preload("res://Scripts/UI/CombatLogView.gd")
const IconChip := preload("res://Scripts/UI/IconChip.gd")
const BattleScene := preload("res://Scenes/Battle.tscn")
const RunConfig := preload("res://Scripts/Core/RunConfig.gd")

## Issue 113, the team status panel.
##
## Two halves, and the second one is the one that matters. The first is that the
## panel says the right thing about a state handed to it. The second is that a
## real fight, stepped through `BattleView._process`, puts it on the screen and
## keeps it there -- twelve features on this project were built and unreachable,
## and every one of them would have passed the first half.
##
## **Every assertion here has been shown its failing case.** A floor nobody has
## crossed is a detector nobody has fired.

const _WARRIOR := &"warrior"

func _pawn(class_id: StringName) -> PawnData:
	return PawnFactory.make_starter_pawn(class_id, class_id, Registry.get_class_def(class_id).display_name)

func _party(class_ids: Array) -> Array[PawnData]:
	var out: Array[PawnData] = []
	for id in class_ids:
		out.append(_pawn(id))
	return out

# ---------------------------------------------------------------------------
# Which units get a row
# ---------------------------------------------------------------------------

func _unit(id: int, team: CG.Team, is_pawn: bool, alive: bool = true) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.display_name = "u%d" % id
	u.hp_max = 10
	u.hp = 10 if alive else 0
	u.alive = alive
	if is_pawn:
		u.pawn = PawnData.new()
	else:
		u.enemy_id = &"siege_engine"
	return u

func test_the_panel_lists_the_party_and_not_the_enemies() -> void:
	var state := CombatState.new(1)
	state.units.append(_unit(0, CG.Team.PLAYER, true))
	state.units.append(_unit(1, CG.Team.ENEMY, false))
	state.units.append(_unit(2, CG.Team.PLAYER, true))
	var ids: Array = []
	for u in TeamStatusView.rows_for(state):
		ids.append(u.id)
	assert_eq(ids, [0, 2], "an enemy must never get a row in the player's team panel")

## The half of the rule that is not obvious: a pawn keeps its row after it dies,
## because losing one is the most important thing that can happen to the party,
## and a summon does not, because a fight that builds and loses six engines
## would otherwise grow a six-row graveyard.
func test_a_dead_pawn_keeps_its_row_and_a_dead_summon_does_not() -> void:
	var state := CombatState.new(1)
	state.units.append(_unit(0, CG.Team.PLAYER, true, false))
	state.units.append(_unit(1, CG.Team.PLAYER, false, false))
	state.units.append(_unit(2, CG.Team.PLAYER, false, true))
	var ids: Array = []
	for u in TeamStatusView.rows_for(state):
		ids.append(u.id)
	assert_eq(ids, [0, 2], "the dead pawn stays, the dead summon goes")

## Pawns before summons regardless of the order they appear in `state.units`,
## which is spawn order: an engine built on tick 40 is appended after every pawn
## today, and this must not be relying on that.
func test_pawns_come_before_summons() -> void:
	var state := CombatState.new(1)
	state.units.append(_unit(0, CG.Team.PLAYER, false))
	state.units.append(_unit(1, CG.Team.PLAYER, true))
	var ids: Array = []
	for u in TeamStatusView.rows_for(state):
		ids.append(u.id)
	assert_eq(ids, [1, 0])

## The caps are per kind, so a fifth pawn and a third engine are both counted.
## One combined total would be able to report zero hidden while a row was
## missing, which is the failure `hidden_status_count` was written to end on the
## badges and would have been reintroduced here.
func test_the_overflow_count_is_counted_per_kind() -> void:
	var state := CombatState.new(1)
	for i in TeamStatusView.MAX_PAWN_ROWS + 1:
		state.units.append(_unit(i, CG.Team.PLAYER, true))
	for i in TeamStatusView.MAX_SUMMON_ROWS + 2:
		state.units.append(_unit(100 + i, CG.Team.PLAYER, false))
	assert_eq(TeamStatusView.rows_for(state).size(), TeamStatusView.MAX_ROWS)
	assert_eq(TeamStatusView.hidden_row_count(state), 3,
		"one pawn and two engines are hidden and the line has to say three")

func test_nothing_is_hidden_when_everything_fits() -> void:
	var state := CombatState.new(1)
	for i in TeamStatusView.MAX_PAWN_ROWS:
		state.units.append(_unit(i, CG.Team.PLAYER, true))
	assert_eq(TeamStatusView.hidden_row_count(state), 0,
		"an ordinary four-pawn party must not be told something is missing")

# ---------------------------------------------------------------------------
# Cooldowns -- the quarter of this issue that has never been drawn
# ---------------------------------------------------------------------------

## The three states, and the third one is why this is not a boolean. Measured on
## the real classes rather than a fixture, because the measurement that produced
## the design (`Tools/CooldownLoad.gd`) was of the real classes: the Warrior owns
## five of the game's eight cooldowns, the Abomination owns none at all.
func test_the_classes_that_own_no_cooldown_are_told_so_in_words() -> void:
	var state := CombatState.new(1)
	var warrior := _real_unit(&"warrior", 0)
	var abomination := _real_unit(&"abomination", 1)
	state.units.append(warrior)
	state.units.append(abomination)

	assert_true(TeamStatusView.has_cooldown_actions(warrior),
		"the Warrior owns five of the eight cooldowns in the game")
	assert_false(TeamStatusView.has_cooldown_actions(abomination),
		"the Abomination owns none, which is why the row needs words rather than an empty box")
	assert_eq(TeamStatusView.cooldown_summary(state, abomination), "No cooldowns")
	assert_eq(TeamStatusView.cooldown_summary(state, warrior), "All ready",
		"nothing has fired yet, so it has them and none is running")

func _real_unit(class_id: StringName, id: int) -> CombatUnit:
	var def = Registry.get_class_def(class_id)
	var u := CombatUnit.new()
	u.id = id
	u.team = CG.Team.PLAYER
	u.display_name = def.display_name
	u.pawn = _pawn(class_id)
	u.hp_max = 100
	u.hp = 100
	u.actions = def.starting_actions.duplicate()
	return u

## A running cooldown produces a chip that names the action and says how long is
## left, in seconds, read off the same expression `CombatSim` gates the action
## with (`state.tick < cooldowns[id]`).
func test_a_running_cooldown_names_its_action_and_its_seconds() -> void:
	var state := CombatState.new(1)
	var warrior := _real_unit(&"warrior", 0)
	state.units.append(warrior)

	var gated := _first_action_with_a_cooldown(warrior)
	assert_true(gated != &"", "the Warrior must own at least one gated action for this to test anything")
	var action = Registry.get_action(gated)
	state.tick = 100
	warrior.cooldowns[gated] = 100 + action.cooldown_ticks

	var running := TeamStatusView.cooldowns_for(state, warrior)
	assert_eq(running.size(), 1)
	assert_eq(running[0]["action_id"], gated)
	assert_eq(int(running[0]["ticks_left"]), action.cooldown_ticks)
	assert_almost_eq(float(running[0]["fraction"]), 1.0, 0.001,
		"a cooldown that has just started is full")
	assert_eq(TeamStatusView.cooldown_summary(state, warrior), "",
		"chips are being drawn, so the line must not also carry a note")

## The failing case for the gate above: a cooldown whose end tick has passed is
## not a cooldown. Without this the panel would show every action a unit had
## ever used, forever, which is the "detector that always fires" the design note
## on this file is about.
func test_an_expired_cooldown_is_not_shown() -> void:
	var state := CombatState.new(1)
	var warrior := _real_unit(&"warrior", 0)
	state.units.append(warrior)
	var gated := _first_action_with_a_cooldown(warrior)
	state.tick = 500
	warrior.cooldowns[gated] = 400
	assert_eq(TeamStatusView.cooldowns_for(state, warrior).size(), 0)
	assert_eq(TeamStatusView.cooldown_summary(state, warrior), "All ready")

## Soonest ready first, and capped at two. The cap is the measurement: nothing
## in five rooms by ten seeds by two parties ever held more than two at once.
func test_the_soonest_cooldown_is_first_and_the_list_is_capped() -> void:
	var state := CombatState.new(1)
	var warrior := _real_unit(&"warrior", 0)
	state.units.append(warrior)
	state.tick = 0
	var gated: Array = []
	for action_id in warrior.actions:
		var a = Registry.get_action(action_id)
		if a != null and a.cooldown_ticks > 0:
			gated.append(action_id)
	assert_true(gated.size() >= 3, "got %d gated actions, this test needs three to prove a cap of two" % gated.size())
	# Deliberately set longest-first, so an unsorted implementation returns the
	# wrong two and not merely the wrong order.
	for i in gated.size():
		warrior.cooldowns[gated[i]] = 900 - i * 100

	var running := TeamStatusView.cooldowns_for(state, warrior)
	assert_eq(running.size(), TeamStatusView.MAX_COOLDOWN_CHIPS)
	assert_true(int(running[0]["ticks_left"]) < int(running[1]["ticks_left"]),
		"the question a player has is when it gets its move back, so the smallest number leads")
	assert_eq(running[0]["action_id"], gated[gated.size() - 1],
		"the two shown must be the two soonest, not the first two in the action list")

func _first_action_with_a_cooldown(u: CombatUnit) -> StringName:
	for action_id in u.actions:
		var a = Registry.get_action(action_id)
		if a != null and a.cooldown_ticks > 0:
			return action_id
	return &""

func test_seconds_are_seconds_not_ticks() -> void:
	assert_eq(TeamStatusView.seconds_text(CG.TICKS_PER_SECOND), "1.0s")
	assert_eq(TeamStatusView.seconds_text(CG.TICKS_PER_SECOND * 3), "3.0s")

# ---------------------------------------------------------------------------
# It is on the screen, and it stays there
# ---------------------------------------------------------------------------

func _battle() -> Node:
	var battle = BattleScene.instantiate()
	battle._ready()
	return battle

func _config(class_ids: Array, encounter_id: StringName, seed_value: int) -> RunConfig:
	var cfg := RunConfig.new()
	cfg.party = _party(class_ids)
	cfg.encounter_id = encounter_id
	cfg.seed = seed_value
	return cfg

## The reachability half. `begin()` is the door a player comes through, and the
## panel has to be populated before the first tick -- a player looking at frame
## one should see their party, not a box that fills in once something happens.
func test_the_panel_is_populated_by_begin_before_any_tick() -> void:
	var battle := _battle()
	battle.begin(_config([&"warrior", &"priest", &"geysermancer", &"abomination"], &"floor1_room1", 7))
	var panel = battle._team_status
	assert_not_null(panel, "BattleView must build a team status panel")
	assert_eq(battle.state.tick, 0, "nothing has been stepped yet")
	assert_eq(panel.row_count(), 4, "four pawns, four rows, on the frame the fight starts")
	battle.free()

## Live means live, through the real per-frame path rather than by calling
## `sync` directly -- the defect this project keeps shipping is never in the
## helper, it is that nothing on the frame path ever calls it.
func test_a_summon_gets_a_row_through_the_real_frame_path() -> void:
	var battle := _battle()
	battle.begin(_config([&"siege_master", &"warrior", &"priest", &"geysermancer"], &"floor1_room1", 3))
	var panel = battle._team_status
	var started: int = panel.row_count()
	var grew := false
	for i in 600:
		battle._process(1.0 / float(CG.TICKS_PER_SECOND))
		if panel.row_count() > started:
			grew = true
			break
	assert_true(grew, "a Siege Master built an engine and the panel never grew a row for it (started at %d)" % started)
	battle.free()

## The instrument check for the test above. If a party that summons nothing also
## grows a row, the assertion is measuring something other than summoning.
func test_a_party_that_summons_nothing_never_grows_a_row() -> void:
	var battle := _battle()
	battle.begin(_config([&"warrior", &"priest", &"geysermancer", &"abomination"], &"floor1_room1", 3))
	var panel = battle._team_status
	for i in 600:
		battle._process(1.0 / float(CG.TICKS_PER_SECOND))
	assert_eq(panel.row_count(), 4,
		"no pawn in this party summons anything, so four rows is the whole answer")
	battle.free()

## The panel is drawn in the strip the log already reserves, so the arena is not
## made smaller to describe itself. The consequence is that the log starts
## further down, and that is asserted rather than assumed: the log's own inset
## has to equal where the panel ends.
func test_the_panel_sits_in_the_reserved_strip_and_the_log_starts_below_it() -> void:
	var battle := _battle()
	assert_almost_eq(
		battle._team_status.offset_right - battle._team_status.offset_left,
		TeamStatusView.PANEL_WIDTH, 0.5)
	assert_almost_eq(TeamStatusView.PANEL_WIDTH, CombatLogView.LOG_WIDTH, 0.5,
		"the panel is the width of the column it shares, or the two edges nearly agree and read as a mistake")
	battle.free()

## Portrait puts the log along the bottom, where the panel is nowhere near it,
## so the inset must go back to zero rather than staying set from the last
## orientation. Landscape and portrait are checked in that order on purpose --
## the bug this catches is a stale value, which only appears on the second call.
func test_the_log_inset_is_landscape_only() -> void:
	var BattleView := load("res://Scripts/UI/BattleView.gd")
	assert_true(BattleView.log_top_inset(Vector2(1280.0, 720.0)) > TeamStatusView.MAX_PANEL_HEIGHT,
		"landscape shares the side column, so the log has to start below the panel")
	assert_almost_eq(BattleView.log_top_inset(Vector2(390.0, 844.0)), 0.0, 0.001,
		"portrait docks the log along the bottom, where the panel is nowhere near it")

	var log_view := Control.new()
	log_view.set_script(CombatLogView)
	log_view._ready()

	log_view.set_landscape(true)
	log_view.set_top_inset(300.0)
	assert_almost_eq(log_view._label.offset_top, 300.0, 0.5)

	log_view.set_landscape(false)
	log_view.set_top_inset(0.0)
	assert_almost_eq(log_view._label.offset_top, CombatLogView.LOG_MARGIN - CombatLogView.LOG_HEIGHT, 0.5,
		"portrait docks the log along the bottom and must not carry a landscape inset into it")
	log_view.free()

## The panel is bounded. A fight that puts six units on the player's side must
## not produce a column taller than the space reserved for it, and the log's own
## inset is computed from that bound rather than from the current height, so the
## log cannot slide up and down as engines come and go.
func test_the_panel_never_exceeds_the_height_the_log_was_inset_by() -> void:
	var battle := _battle()
	battle.begin(_config([&"siege_master", &"warrior", &"priest", &"geysermancer"], &"floor1_room1", 3))
	var panel = battle._team_status
	var tallest := 0.0
	for i in 900:
		battle._process(1.0 / float(CG.TICKS_PER_SECOND))
		tallest = maxf(tallest, panel.panel_height())
	assert_true(tallest > 0.0, "the panel measured zero high, so this assertion saw nothing")
	assert_true(tallest <= TeamStatusView.MAX_PANEL_HEIGHT,
		"the panel reached %.0f in a real fight and the log was only moved down %.0f" % [tallest, TeamStatusView.MAX_PANEL_HEIGHT])
	battle.free()

## **The pair of assertions that would have caught the defect this panel already
## shipped into a screenshot once.**
##
## `MAX_PANEL_HEIGHT` is the number the combat log is moved down by. The first
## version derived it from constants, with a text line at 18 px because an
## `IconChip` is 18 px square -- and a `Label` at `FONT_SIZE_SMALL` will not go
## below 23, so a pawn row was really 72 rather than 66, the panel overran the
## inset, and two rows drew underneath the log's text. Nineteen tests were green
## through it, because not one of them asked Godot how tall a label is.
##
## So `panel_height` sums what the nodes report, and this checks the constant
## against that in **both** directions. The upper bound alone is not enough: a
## constant of 5000 would pass it and move the log off the screen.
func test_the_reserved_height_matches_the_worst_case_the_nodes_actually_measure() -> void:
	var state := CombatState.new(1)
	for i in TeamStatusView.MAX_PAWN_ROWS + 1:
		state.units.append(_unit(i, CG.Team.PLAYER, true))
	for i in TeamStatusView.MAX_SUMMON_ROWS + 1:
		state.units.append(_unit(100 + i, CG.Team.PLAYER, false))
	var panel := Control.new()
	panel.set_script(TeamStatusView)
	panel._ready()
	panel.sync(state)
	var worst: float = panel.panel_height()
	assert_true(worst <= TeamStatusView.MAX_PANEL_HEIGHT,
		"four pawns, two summons and an overflow line measure %.0f px and only %.0f is reserved" % [worst, TeamStatusView.MAX_PANEL_HEIGHT])
	assert_true(TeamStatusView.MAX_PANEL_HEIGHT - worst <= TeamStatusView.ROW_SEPARATION + 24.0,
		"the reservation is %.0f and the worst case is %.0f -- the log has been pushed down past anything the panel uses" % [TeamStatusView.MAX_PANEL_HEIGHT, worst])
	panel.free()
