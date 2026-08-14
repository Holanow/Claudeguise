extends "res://Tests/TestCase.gd"

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")
const BattleScene := preload("res://Scenes/Battle.tscn")

## Issue 19: the outcome used to be a small toolbar label reading
## "Victory (197 ticks)" — a number nobody playing has ever seen, at the
## same visual weight as the seed display, visible identically during and
## after the fight. This checks the three things the issue actually asks
## for: no raw ticks anywhere a player reads, the banner is silent until
## the fight resolves, and it names what the fight cost without asking the
## player to count bars.

func _make_unit(id: int, team: CG.Team, hp: int, hp_max: int, alive: bool = true) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.hp = hp
	u.hp_max = hp_max
	u.alive = alive
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
	assert_eq(view._cost_summary(), "Your whole party survived.")
	view.free()

func test_a_total_wipe_reads_as_none_survived() -> void:
	var view = _spawn()
	var state := CombatState.new(0)
	state.units.append(_make_unit(0, CG.Team.PLAYER, 0, 10, false))
	state.units.append(_make_unit(1, CG.Team.PLAYER, 0, 10, false))
	view.state = state
	assert_eq(view._cost_summary(), "None of your party survived.")
	view.free()

func test_a_partial_loss_counts_survivors_against_the_starting_party() -> void:
	var view = _spawn()
	var state := CombatState.new(0)
	state.units.append(_make_unit(0, CG.Team.PLAYER, 6, 10))
	state.units.append(_make_unit(1, CG.Team.PLAYER, 0, 10, false))
	state.units.append(_make_unit(2, CG.Team.PLAYER, 3, 10))
	view.state = state
	assert_eq(view._cost_summary(), "2 of 3 survived.")
	view.free()

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
	assert_eq(view._cost_summary(), "Your whole party survived.", "one real pawn, full health -- the summon must not appear as a second party member")
	view.free()

func test_cost_summary_does_not_let_a_dead_summon_read_as_a_party_loss() -> void:
	var view = _spawn()
	var state := CombatState.new(0)
	state.units.append(_make_unit(0, CG.Team.PLAYER, 10, 10))
	var summon := _make_unit(1, CG.Team.PLAYER, 0, 10, false)
	summon.enemy_id = &"siege_engine"
	state.units.append(summon)
	view.state = state
	assert_eq(view._cost_summary(), "Your whole party survived.", "the summon dying must not read as the player losing a pawn")
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

