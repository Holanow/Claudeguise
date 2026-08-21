extends "res://Tests/TestCase.gd"

const BattleScene := preload("res://Scenes/Battle.tscn")

## Issue 19: the outcome used to be a small toolbar label reading
## "Victory (197 ticks)" — a number nobody playing has ever seen, at the
## same visual weight as the seed display, visible identically during and
## after the fight. This checks the three things the issue actually asks
## for: no raw ticks anywhere a player reads, the banner is silent until
## the fight resolves, and it names what the fight cost without asking the
## player to count bars.

func _make_unit(id: int, team: CG.Team, hp: int, hp_max: int, alive: bool = true, display_name: String = "") -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.hp = hp
	u.hp_max = hp_max
	u.alive = alive
	u.display_name = display_name if display_name != "" else "Pawn %d" % id
	return u

func _spawn() -> Node2D:
	var view = BattleScene.instantiate()
	view._ready()
	return view

func test_duration_reads_in_seconds_not_ticks() -> void:
	# Derived from CG.TICKS_PER_SECOND rather than hardcoded. This test read
	# "2.0s" for 60 ticks until the fight-speed change halved the tick rate,
	# at which point 60 ticks genuinely became 4.0s and the test was simply
	# wrong about the world. What it actually cares about is that the banner
	# says seconds instead of ticks, which is a claim about the unit, not
	# about any particular rate.
	var two_seconds := CG.TICKS_PER_SECOND * 2
	assert_eq(BattleScene.instantiate()._format_duration(two_seconds), "2.0s")

func test_a_full_survival_reads_as_a_whole_party() -> void:
	var view = _spawn()
	var state := CombatState.new(0)
	state.units.append(_make_unit(0, CG.Team.PLAYER, 10, 10))
	state.units.append(_make_unit(1, CG.Team.PLAYER, 4, 10))
	state.units.append(_make_unit(2, CG.Team.ENEMY, 0, 10, false))
	view.state = state
	assert_eq(view._cost_summary(), "Every one of your pawns survived.")
	view.free()

func test_a_total_wipe_reads_as_none_survived() -> void:
	var view = _spawn()
	var state := CombatState.new(0)
	state.units.append(_make_unit(0, CG.Team.PLAYER, 0, 10, false, "Warrior"))
	state.units.append(_make_unit(1, CG.Team.PLAYER, 0, 10, false, "Priest"))
	view.state = state
	assert_eq(view._cost_summary(), "None of your pawns survived.  You lost Warrior and Priest.")
	view.free()

func test_a_partial_loss_counts_survivors_against_the_starting_party() -> void:
	var view = _spawn()
	var state := CombatState.new(0)
	state.units.append(_make_unit(0, CG.Team.PLAYER, 6, 10))
	state.units.append(_make_unit(1, CG.Team.PLAYER, 0, 10, false, "Warrior"))
	state.units.append(_make_unit(2, CG.Team.PLAYER, 3, 10))
	view.state = state
	assert_eq(view._cost_summary(), "2 of your 3 pawns survived.  You lost Warrior.")
	view.free()

## Issue 320, the playtester's own words: "Fight 1 said '3 of 4 survived' and
## named nobody ... twice I watched a party member die and the game never told
## me which one."
func test_the_cost_summary_names_every_pawn_that_died() -> void:
	var view = _spawn()
	var state := CombatState.new(0)
	state.units.append(_make_unit(0, CG.Team.PLAYER, 6, 10, true, "Priest"))
	state.units.append(_make_unit(1, CG.Team.PLAYER, 0, 10, false, "Warrior"))
	state.units.append(_make_unit(2, CG.Team.PLAYER, 0, 10, false, "Abomination"))
	state.units.append(_make_unit(3, CG.Team.ENEMY, 0, 10, false, "Goblin"))
	view.state = state
	var summary: String = view._cost_summary()
	assert_true(summary.contains("Warrior"), summary)
	assert_true(summary.contains("Abomination"), summary)
	assert_false(summary.contains("Goblin"), "an enemy death is not a cost the player paid: " + summary)
	assert_false(summary.contains("Priest"), "a survivor must not read as a casualty: " + summary)
	view.free()

## A summoned siege engine is a player-team unit with no pawn. It must not be
## named as a casualty for the same reason it is not counted as one.
func test_a_dead_summon_is_not_named_as_a_casualty() -> void:
	var view = _spawn()
	var state := CombatState.new(0)
	state.units.append(_make_unit(0, CG.Team.PLAYER, 0, 10, false, "Warrior"))
	var summon := _make_unit(1, CG.Team.PLAYER, 0, 10, false, "Siege Engine")
	summon.enemy_id = &"siege_engine"
	state.units.append(summon)
	view.state = state
	assert_eq(view._cost_summary(), "None of your pawns survived.  You lost Warrior.")
	view.free()

func test_name_list_reads_as_a_sentence_at_one_two_and_three() -> void:
	assert_eq(BattleView.name_list([] as Array[String]), "")
	assert_eq(BattleView.name_list(["Warrior"] as Array[String]), "Warrior")
	assert_eq(BattleView.name_list(["Warrior", "Priest"] as Array[String]), "Warrior and Priest")
	assert_eq(BattleView.name_list(["Warrior", "Priest", "Abomination"] as Array[String]),
		"Warrior, Priest and Abomination")

func test_end_banner_is_hidden_until_the_fight_resolves() -> void:
	var view = _spawn()
	assert_false(view._end_banner.visible)
	view.free()

## PLAYTEST-NOTES 21: a siege engine is a player-team unit (_spawn_summon
## puts it on the caster's team) built via _build_enemy_unit, same as any
## enemy -- it carries a real enemy_id and no pawn. "3 of 4 survived" must
## stay a count of the party the player actually picked at party select, not
## grow because something got summoned mid-fight.
func test_cost_summary_does_not_count_a_summoned_unit_as_a_party_member() -> void:
	var view = _spawn()
	var state := CombatState.new(0)
	state.units.append(_make_unit(0, CG.Team.PLAYER, 10, 10))
	var summon := _make_unit(1, CG.Team.PLAYER, 10, 10)
	summon.enemy_id = &"siege_engine"
	state.units.append(summon)
	view.state = state
	assert_eq(view._cost_summary(), "Every one of your pawns survived.", "one real pawn, full health -- the summon must not appear as a second party member")
	view.free()

func test_cost_summary_does_not_let_a_dead_summon_read_as_a_party_loss() -> void:
	var view = _spawn()
	var state := CombatState.new(0)
	state.units.append(_make_unit(0, CG.Team.PLAYER, 10, 10))
	var summon := _make_unit(1, CG.Team.PLAYER, 0, 10, false)
	summon.enemy_id = &"siege_engine"
	state.units.append(summon)
	view.state = state
	assert_eq(view._cost_summary(), "Every one of your pawns survived.", "the summon dying must not read as the player losing a pawn")
	view.free()

func test_end_banner_shows_and_names_the_outcome_on_resolution() -> void:
	var view = _spawn()
	var state := CombatState.new(0)
	state.tick = 90
	state.outcome = CombatState.Outcome.PLAYER_WIN
	state.units.append(_make_unit(0, CG.Team.PLAYER, 10, 10))
	view.state = state
	view._show_outcome()
	assert_true(view._end_banner.visible)
	assert_eq(view._end_outcome_label.text, "Victory")
	assert_false(view._end_outcome_label.text.contains("tick"))
	assert_false(view._end_cost_label.text.contains("tick"))
	view.free()


# ---------------------------------------------------------------------------
# Issue 218: the banner used to contradict the line under it
# ---------------------------------------------------------------------------


func _make_pawn_unit(id: int, hp: int, alive: bool) -> CombatUnit:
	var u := _make_unit(id, CG.Team.PLAYER, hp, 10, alive)
	u.pawn = PawnData.new()
	return u

## **Reproduced before it was fixed, and it is the whole issue**: the banner
## printed "Victory" and the line directly under it printed "None of your party
## survived." One fight, two sentences, in the same box.
func test_a_win_with_every_pawn_dead_reads_as_a_defeat() -> void:
	var view = _spawn()
	var state := CombatState.new(0)
	state.tick = 90
	state.outcome = CombatState.Outcome.PLAYER_WIN
	state.units.append(_make_pawn_unit(0, 0, false))
	state.units.append(_make_pawn_unit(1, 0, false))
	var summon := _make_unit(2, CG.Team.PLAYER, 8, 10)
	summon.enemy_id = &"siege_engine"
	state.units.append(summon)
	view.state = state
	view._show_outcome()
	assert_eq(view._end_outcome_label.text, "Defeat",
		"the party is gone and the engines finished the room; the banner still called it a win")
	assert_true(view._end_cost_label.text.contains("None of your pawns survived."),
		"the two halves of the banner must agree: %s" % view._end_cost_label.text)
	assert_eq(view._end_outcome_label.get_theme_color("font_color"), Palette.TEAM_ENEMY,
		"a Defeat drawn in the player's own colour is the contradiction in a second costume")
	assert_true(view._outcome_label.text.begins_with("Defeat"),
		"the top bar and the banner must not disagree either: %s" % view._outcome_label.text)
	view.free()

## The instrument check. If an ordinary win also read as a Defeat, the assertion
## above would be measuring nothing.
func test_a_win_with_a_pawn_still_standing_is_still_a_victory() -> void:
	var view = _spawn()
	var state := CombatState.new(0)
	state.outcome = CombatState.Outcome.PLAYER_WIN
	state.units.append(_make_pawn_unit(0, 0, false))
	state.units.append(_make_pawn_unit(1, 3, true))
	view.state = state
	view._show_outcome()
	assert_eq(view._end_outcome_label.text, "Victory")
	view.free()

## The level editor can build a fight with no party at all. Every pawn being
## dead must mean pawns existed, or that fight reports Defeat on every win.
func test_a_fight_with_no_pawns_at_all_is_not_a_pawnless_defeat() -> void:
	var view = _spawn()
	var state := CombatState.new(0)
	state.outcome = CombatState.Outcome.PLAYER_WIN
	var summon := _make_unit(0, CG.Team.PLAYER, 8, 10)
	summon.enemy_id = &"siege_engine"
	state.units.append(summon)
	view.state = state
	view._show_outcome()
	assert_eq(view._end_outcome_label.text, "Victory")
	view.free()

# ---------------------------------------------------------------------------
# Issue 249: what ended it, in words
# ---------------------------------------------------------------------------

func _ended(state: CombatState, reason: CG.EndReason) -> void:
	var e := CombatEvent.make(CG.EventKind.FIGHT_END, state.tick)
	e.end_reason = reason
	state.events.append(e)

## "CANNOT_ACT" is an enum. The player reads a sentence, and it names the side,
## because the reason is a fact about the loser and "nothing could fight any
## more" under a Defeat is ambiguous about whose side that was.
func test_a_fight_that_ended_because_a_side_was_furniture_says_so_in_words() -> void:
	var won := CombatState.new(0)
	won.outcome = CombatState.Outcome.PLAYER_WIN
	_ended(won, CG.EndReason.CANNOT_ACT)
	var sentence := BattleView.end_reason_sentence(won)
	assert_true(sentence.contains("enemy"), "the winning side's banner does not say whose side stopped: %s" % sentence)
	assert_false(sentence.contains("CANNOT"), "an enum reached the player: %s" % sentence)
	assert_false(sentence.contains("_"), "an enum reached the player: %s" % sentence)

	var lost := CombatState.new(0)
	lost.outcome = CombatState.Outcome.ENEMY_WIN
	_ended(lost, CG.EndReason.CANNOT_ACT)
	assert_true(BattleView.end_reason_sentence(lost).contains("your"),
		"a loss must say it was your own side: %s" % BattleView.end_reason_sentence(lost))
	assert_ne(sentence, BattleView.end_reason_sentence(lost),
		"a win and a loss cannot get the same sentence about who stopped")

## **The negative case, and it is the one that decides whether this is worth
## having.** The ordinary ending prints no reason at all. A line under every
## banner restating what Victory already means is furniture within two fights,
## and then the one ending that needed explaining wears the same clothes as the
## one that never did.
func test_the_ordinary_ending_adds_no_sentence_at_all() -> void:
	var state := CombatState.new(0)
	state.outcome = CombatState.Outcome.PLAYER_WIN
	_ended(state, CG.EndReason.NO_SURVIVORS)
	assert_eq(BattleView.end_reason_sentence(state), "")
	var silent := CombatState.new(0)
	silent.outcome = CombatState.Outcome.PLAYER_WIN
	assert_eq(BattleView.end_reason_sentence(silent), "",
		"a fight with no FIGHT_END event yet must not invent a reason")

## The banner really carries it, not just the formatter.
func test_the_banner_shows_the_reason_under_the_cost_line() -> void:
	var view = _spawn()
	var state := CombatState.new(0)
	state.tick = 90
	state.outcome = CombatState.Outcome.ENEMY_WIN
	state.units.append(_make_pawn_unit(0, 3, true))
	_ended(state, CG.EndReason.CANNOT_ACT)
	view.state = state
	view._show_outcome()
	assert_true(view._end_cost_label.text.contains("could fight any more"),
		"the reason never reached the banner: %s" % view._end_cost_label.text)
	assert_true(view._end_cost_label.text.contains("survived"),
		"the cost line was replaced rather than added to: %s" % view._end_cost_label.text)
	view.free()

## **UNSET prints nothing, and that silence must not be able to hide one.**
## `CG.EndReason` says a fight ending with UNSET is a defect in the setter rather
## than a fourth ending, so this runs a real fight to the end and asks what
## arrived at the banner -- the only place the consequence would be visible.
func test_a_real_fight_never_reaches_the_banner_without_a_reason() -> void:
	var CombatSim := load("res://Scripts/Combat/CombatSim.gd")
	var Registry := load("res://Scripts/Content/Registry.gd")
	var PawnFactory := load("res://Scripts/Content/PawnFactory.gd")
	var party: Array = []
	for id in [&"warrior", &"priest", &"geysermancer", &"siege_master"]:
		party.append(PawnFactory.make_starter_pawn(id, id, Registry.get_class_def(id).display_name))
	var typed: Array[PawnData] = []
	for p in party:
		typed.append(p)
	var state = CombatSim.build(typed, Registry.get_encounter(&"floor1_room1"), 3)
	CombatSim.run(state)
	assert_ne(state.outcome, CombatState.Outcome.UNRESOLVED, "the fight never finished, so this saw nothing")
	assert_ne(BattleView.end_reason_of(state), CG.EndReason.UNSET,
		"a real fight reached the end with no reason set, so the banner's silence is hiding one")
