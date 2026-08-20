extends "res://Tests/TestCase.gd"


## #170: terrain that applies a status. The tar pit.

const _SEED := 8300
const _TICKS := 20

func _unit(id: int, team: CG.Team, pos: Vector2) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.hp_max = 200
	u.hp = 200
	u.position = pos
	u.move_speed = 6.0
	return u

func _pit(damage: int, status_ticks: int) -> Object:
	var f = Terrain.hazard(Rect2(-50.0, -50.0, 100.0, 100.0), damage, CG.DamageType.EARTH)
	if status_ticks > 0:
		f.applies_status = CG.Status.SLOWED
		f.applies_status_enabled = true
		f.status_duration_ticks = status_ticks
	return f

func _state(feature) -> CombatState:
	var state := CombatState.new(_SEED)
	state.terrain = [feature]
	state.units.append(_unit(0, CG.Team.PLAYER, Vector2.ZERO))
	state.units.append(_unit(1, CG.Team.ENEMY, Vector2(4000.0, 0.0)))
	return state

func _deps() -> SimDeps:
	var deps := SimDeps.new()
	deps.default_decide = func(_s: CombatState, _u: CombatUnit) -> Intent: return Intent.idle()
	deps.plan_decide = func(_s: CombatState, _u: CombatUnit) -> Intent: return null
	return deps

func _count(state: CombatState, kind: CG.EventKind) -> int:
	var n := 0
	for e in state.events:
		if e.kind == kind:
			n += 1
	return n

## The failing case. A pit with no damage at all was skipped entirely.
func test_a_pit_with_no_damage_still_slows() -> void:
	var state := _state(_pit(0, _TICKS))
	CombatSim.step(state, _deps())
	assert_true(state.unit(0).has_status(CG.Status.SLOWED), "a status-only hazard must still apply it")

func test_a_pit_that_also_damages_does_both() -> void:
	var state := _state(_pit(3, _TICKS))
	CombatSim.step(state, _deps())
	assert_true(state.unit(0).has_status(CG.Status.SLOWED))
	assert_eq(state.unit(0).hp, 197, "and still deals its damage")

## Refreshed every tick inside, so leaving is what ends it rather than a clock
## that started on entry.
func test_standing_in_the_pit_refreshes_the_status() -> void:
	var state := _state(_pit(0, _TICKS))
	var deps := _deps()
	for _i in _TICKS * 3:
		CombatSim.step(state, deps)
	assert_true(state.unit(0).has_status(CG.Status.SLOWED), "sixty ticks in a twenty-tick pit")

func test_leaving_the_pit_lets_the_status_expire() -> void:
	var state := _state(_pit(0, _TICKS))
	var deps := _deps()
	CombatSim.step(state, deps)
	state.unit(0).position = Vector2(500.0, 0.0)
	for _i in _TICKS + 2:
		CombatSim.step(state, deps)
	assert_false(state.unit(0).has_status(CG.Status.SLOWED), "it wears off once you are out")

## ON ENTRY ONLY. Per-tick would be 45 lines for one crossing, which is the
## stalker_mark flood again.
func test_the_event_fires_on_entry_and_not_once_per_tick() -> void:
	var state := _state(_pit(0, _TICKS))
	var deps := _deps()
	for _i in _TICKS * 2:
		CombatSim.step(state, deps)
	assert_eq(_count(state, CG.EventKind.STATUS_APPLIED), 1, "one line per crossing, not forty")

func test_re_entering_the_pit_speaks_again() -> void:
	var state := _state(_pit(0, 2))
	var deps := _deps()
	CombatSim.step(state, deps)
	state.unit(0).position = Vector2(500.0, 0.0)
	for _i in 5:
		CombatSim.step(state, deps)
	state.unit(0).position = Vector2.ZERO
	CombatSim.step(state, deps)
	assert_eq(_count(state, CG.EventKind.STATUS_APPLIED), 2, "a second crossing is a second event")

# --- the negative half -------------------------------------------------------

## An ordinary hazard applies nothing. Every feature in the game before this.
func test_an_ordinary_hazard_applies_no_status() -> void:
	var state := _state(_pit(3, 0))
	var deps := _deps()
	for _i in 5:
		CombatSim.step(state, deps)
	assert_eq(state.unit(0).statuses.size(), 0, "damage only, exactly as before")
	assert_eq(_count(state, CG.EventKind.STATUS_APPLIED), 0)

func test_a_unit_outside_the_pit_is_untouched() -> void:
	var state := _state(_pit(0, _TICKS))
	state.unit(0).position = Vector2(500.0, 0.0)
	for _i in 5:
		CombatSim.step(state, _deps())
	assert_false(state.unit(0).has_status(CG.Status.SLOWED))

func test_two_runs_from_one_seed_slow_identically() -> void:
	var a := _state(_pit(2, _TICKS))
	var b := _state(_pit(2, _TICKS))
	for _i in 30:
		CombatSim.step(a, _deps())
		CombatSim.step(b, _deps())
	assert_eq(a.unit(0).hp, b.unit(0).hp)
	assert_eq(a.events.size(), b.events.size())
