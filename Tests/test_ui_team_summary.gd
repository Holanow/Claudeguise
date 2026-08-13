extends "res://Tests/TestCase.gd"

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")
const BattleScene := preload("res://Scenes/Battle.tscn")

## Issue 15: "you cannot tell who is winning" without parsing seven small
## bars. Two aggregate bars answer that at a glance. Needs the real
## Battle.tscn (_ready() called directly, same reasoning as
## Tests/test_ui_battle_pause.gd) because the bars are built in _ready().

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

func test_full_health_party_shows_a_full_bar() -> void:
	var view = _spawn()
	var state := CombatState.new(0)
	state.units.append(_make_unit(0, CG.Team.PLAYER, 10, 10))
	state.units.append(_make_unit(1, CG.Team.PLAYER, 10, 10))
	view.state = state
	view._update_team_summary()
	assert_almost_eq(view._party_summary_fill.size.x, view._SUMMARY_BAR_WIDTH, 0.01)
	view.free()

func test_half_health_party_shows_a_half_bar() -> void:
	var view = _spawn()
	var state := CombatState.new(0)
	state.units.append(_make_unit(0, CG.Team.PLAYER, 5, 10))
	state.units.append(_make_unit(1, CG.Team.PLAYER, 5, 10))
	view.state = state
	view._update_team_summary()
	assert_almost_eq(view._party_summary_fill.size.x, view._SUMMARY_BAR_WIDTH * 0.5, 0.01)
	view.free()

func test_a_dead_unit_still_counts_its_max_hp_against_the_total() -> void:
	# A dead pawn is not removed from the total: the bar reads as "how much
	# of this side's starting health is gone", so a lost pawn should visibly
	# shrink the bar, not vanish from the accounting.
	var view = _spawn()
	var state := CombatState.new(0)
	state.units.append(_make_unit(0, CG.Team.PLAYER, 10, 10))
	state.units.append(_make_unit(1, CG.Team.PLAYER, 0, 10, false))
	view.state = state
	view._update_team_summary()
	assert_almost_eq(view._party_summary_fill.size.x, view._SUMMARY_BAR_WIDTH * 0.5, 0.01)
	view.free()

func test_the_two_teams_are_tracked_independently() -> void:
	var view = _spawn()
	var state := CombatState.new(0)
	state.units.append(_make_unit(0, CG.Team.PLAYER, 10, 10))
	state.units.append(_make_unit(1, CG.Team.ENEMY, 3, 10))
	view.state = state
	view._update_team_summary()
	assert_almost_eq(view._party_summary_fill.size.x, view._SUMMARY_BAR_WIDTH * 1.0, 0.01)
	assert_almost_eq(view._enemy_summary_fill.size.x, view._SUMMARY_BAR_WIDTH * 0.3, 0.01)
	view.free()
