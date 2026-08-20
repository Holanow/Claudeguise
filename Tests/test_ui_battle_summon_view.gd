extends "res://Tests/TestCase.gd"

const BattleScene := preload("res://Scenes/Battle.tscn")

## Issue 75: the real cause of "siege engines are still invisible".

const _SIEGE_ENGINE := &"build_siege_engine"

## A Siege Master with exactly one action and the Mana to pay for it, so the
## default behaviour has nothing else it could pick. The engine's own 3-second
## wind-up (90 ticks) is the real one from `core_actions.gd`, not a fixture
## number -- if that action changes, this test follows it rather than asserting
## against a copy of it.
func _caster() -> CombatUnit:
	var u := CombatUnit.new()
	u.id = 0
	u.team = CG.Team.PLAYER
	u.display_name = "Siege Master"
	u.hp_max = 100
	u.hp = 100
	u.position = Vector2(-200.0, 0.0)
	u.actions = [_SIEGE_ENGINE]
	u.resource_kind = CG.ResourceKind.MANA
	u.resource_max = 60
	u.resource = 60
	return u

## Far enough away that it never reaches the caster and the fight stays
## UNRESOLVED for the whole run -- once outcome is set, `_process` returns
## immediately and would prove nothing.
func _far_enemy() -> CombatUnit:
	var u := CombatUnit.new()
	u.id = 1
	u.team = CG.Team.ENEMY
	u.display_name = "Distant"
	u.hp_max = 500
	u.hp = 500
	u.move_speed = 0.0
	u.position = Vector2(100000.0, 100000.0)
	return u

func _fight() -> Array:
	var state := CombatState.new(9)
	var caster := _caster()
	state.units.append(caster)
	state.units.append(_far_enemy())

	# The real Siege Master reaches this action through its preset plan
	# (PresetPlans.gd, target_self), not through the default behaviour --
	# build_siege_engine has range 0, so the melee commit branch would never
	# fire it against an enemy standing anywhere at all. Setting the intent
	# directly is the same door: CombatSim._decide_phase skips any unit that
	# already has one, so this is a plan's output without needing a plan.
	caster.intent = Intent.use_action(_SIEGE_ENGINE, caster.id)

	var view = BattleScene.instantiate()
	view._ready()
	view.state = state
	view.event_cursor = 0
	view._rebuild_units()
	return [view, state]

## Steps whole ticks through the same `_process` a real frame uses.
func _run_ticks(view, count: int) -> void:
	for i in count:
		view._process(CG.TICK_SECONDS)

func test_a_unit_summoned_mid_fight_gets_a_view() -> void:
	var pair := _fight()
	var view = pair[0]
	var state: CombatState = pair[1]

	assert_eq(view._unit_views.size(), 2, "sanity: two views at fight start")

	# 3s of wind-up plus slack for the decide/commit tick.
	_run_ticks(view, 120)

	assert_true(state.units.size() > 2, "sanity: the summon must actually have happened")
	var summon: CombatUnit = state.units[2]
	assert_true(view._unit_views.has(summon.id),
		"a unit appended after begin() must get a view -- this is the whole of issue 75")

	var summon_view = view._unit_views[summon.id]
	assert_eq(summon_view.unit_id, summon.id, "the new view must be bound to the summon")
	assert_true(summon_view.visible, "a living summon's view must be visible")
	assert_eq(summon_view.position, summon.position + UnitView.visual_offset(summon, state.units),
		"the new view must track the summon's own position like any other unit's")
	view.free()

## The negative half. Adding views per tick is only correct if it *adds*: a
## rebuild would be the obvious wrong fix, and it would silently reset every
## view's per-instance state (the label hysteresis PLAYTEST-NOTES 20 exists
## for) with nothing going red.
func test_existing_views_are_not_rebuilt_every_tick() -> void:
	var pair := _fight()
	var view = pair[0]

	var caster_view = view._unit_views[0]
	_run_ticks(view, 120)

	assert_true(is_instance_valid(caster_view), "an existing view must survive a stepped tick")
	assert_eq(view._unit_views[0].get_instance_id(), caster_view.get_instance_id(),
		"an existing unit must keep the same view node, not get a fresh one each tick")
	view.free()

## Acceptance 2: it works like any other unit's. A summon that draws but is
## never syncable is the same class of half-fix as a silhouette in a registry.
func test_a_summons_view_keeps_tracking_it_after_it_appears() -> void:
	var pair := _fight()
	var view = pair[0]
	var state: CombatState = pair[1]

	_run_ticks(view, 120)
	var summon: CombatUnit = state.units[2]
	var summon_view = view._unit_views[summon.id]

	summon.alive = false
	summon_view.sync(state)
	assert_false(summon_view.visible, "a dead summon must hide like any other dead unit")
	view.free()

## The other half of issue 75's "check while you are there": floaters, death
## markers and impact flashes look their target up by unit id. They resolve it
## through `CombatState.unit()`, not through `_unit_views`, so they were never
## affected by the missing node -- checked rather than assumed, and asserted so
## it stays true.
func test_a_summons_death_marker_resolves_without_needing_its_view() -> void:
	var pair := _fight()
	var view = pair[0]
	var state: CombatState = pair[1]

	_run_ticks(view, 120)
	var summon: CombatUnit = state.units[2]

	var arena_before: int = view.get_node("Arena").get_child_count()
	var death := CombatEvent.make(CG.EventKind.DEATH, state.tick)
	death.target_id = summon.id
	state.emit(death)
	view.consume_events()

	assert_eq(view.get_node("Arena").get_child_count(), arena_before + 1,
		"a summon's death must land as a marker like any other unit's")
	view.free()
