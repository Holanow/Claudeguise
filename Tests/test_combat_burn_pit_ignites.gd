extends "res://Tests/TestCase.gd"


## Issue 767: the Burn Pit ignites instead of ticking flat damage. One
## mechanism -- BURN, hit_scaled off the magnitude the pit declares -- instead
## of two. `Tools/BakeArenaTileSet.gd`'s EXTRA_TILES entry is authored to these
## exact numbers; this file is the production path, not a copy of them.

const _SEED := 76700

func _unit(id: int, team: CG.Team, pos: Vector2) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.hp_max = 500
	u.hp = 500
	u.position = pos
	u.move_speed = 0.0
	return u

## The pit as baked: no flat damage, BURN for 90 ticks off a magnitude of 20.
func _pit() -> TerrainFeature:
	var f := Terrain.make(Terrain.Kind.HAZARD, Rect2(-50.0, -50.0, 100.0, 100.0))
	f.damage_type = CG.DamageType.FIRE
	f.applies_status = CG.Status.BURN
	f.applies_status_enabled = true
	f.status_duration_ticks = 90
	f.status_magnitude = 20.0
	return f

func _state() -> CombatState:
	var state := CombatState.new(_SEED)
	state.grid.stamp_features([_pit()])
	state.units.append(_unit(0, CG.Team.PLAYER, Vector2.ZERO))
	state.units.append(_unit(1, CG.Team.ENEMY, Vector2(4000.0, 0.0)))
	return state

func _idle_deps() -> SimDeps:
	var deps := SimDeps.new()
	deps.default_decide = func(_s: CombatState, _u: CombatUnit) -> Intent: return Intent.idle()
	deps.plan_decide = func(_s: CombatState, _u: CombatUnit) -> Intent: return null
	return deps

## THE POINT: leaving the fire no longer puts you out.
func test_leaving_the_pit_the_burn_keeps_ticking() -> void:
	var state := _state()
	var deps := _idle_deps()
	CombatSim.step(state, deps)
	var victim := state.unit(0)
	assert_true(victim.has_status(CG.Status.BURN), "stepping in lights it")
	victim.position = Vector2(5000.0, 0.0)
	var hp_on_leaving := victim.hp
	for _i in 30:
		CombatSim.step(state, deps)
	assert_true(victim.hp < hp_on_leaving, "burn dealt damage after the unit left the pit")

## Standing in the pit deals no flat damage the instant you enter -- only the
## status, which is what the DOT then reads.
func test_the_pit_itself_declares_no_flat_damage() -> void:
	assert_eq(_pit().damage_per_tick, 0, "one mechanism, not two")

func test_a_hazard_that_ignites_deals_damage_over_time() -> void:
	var state := _state()
	var deps := _idle_deps()
	for _i in 90:
		CombatSim.step(state, deps)
	assert_true(state.unit(0).hp < 500, "the ignite is a reasonable amount of damage")

## Re-entering while already burning refreshes, it does not stack: a pit you
## cannot cross is a wall, not a hazard.
func test_re_entering_while_already_burning_does_not_raise_the_magnitude() -> void:
	var state := _state()
	var deps := _idle_deps()
	CombatSim.step(state, deps)
	var victim := state.unit(0)
	var first_magnitude := float(victim.status_magnitude.get(CG.Status.BURN, 0.0))
	CombatSim.step(state, deps)
	var second_magnitude := float(victim.status_magnitude.get(CG.Status.BURN, 0.0))
	assert_almost_eq(first_magnitude, second_magnitude, 0.0001,
		"standing in the same pit does not compound the burn")

func test_re_entering_refreshes_the_duration() -> void:
	var state := _state()
	var deps := _idle_deps()
	CombatSim.step(state, deps)
	var victim := state.unit(0)
	for _i in 89:
		CombatSim.step(state, deps)
	assert_true(victim.has_status(CG.Status.BURN), "still burning at 90 ticks in the pit")

## Forces one caster to fire one action at one target, once. Same shape as
## `Tools/DummyRoom.gd`'s own rig.
class _ForceOnce:
	var caster_id: int
	var action_id: StringName
	var target_id: int
	var used := false

	func decide(_state: CombatState, unit: CombatUnit) -> Intent:
		if unit.id == caster_id and not used:
			used = true
			return Intent.use_action(action_id, target_id)
		return null

## Geyser Blast's consume path, which #767 exists to feed: with a BURN already
## alight, the hit strips it and lands harder than the same power_scale
## without a consume declared.
func test_geyser_blast_consumes_the_ignite_it_created() -> void:
	var action := ActionLibrary.get_action(&"geyser_blast")
	assert_true(action.consumes_status_enabled and action.consumes_status == CG.Status.BURN,
		"geyser_blast no longer declares a BURN consume; this test measures the wrong thing")
	assert_true(action.consumed_power_scale > 0.0, "a consume with no bonus proves nothing")

	var caster := _unit(0, CG.Team.ENEMY, Vector2.ZERO)
	caster.actions = [action.id] as Array[StringName]
	caster.resource_max = 999999
	caster.resource = 999999
	var target := _unit(1, CG.Team.PLAYER, Vector2(200.0, 0.0))
	target.statuses[CG.Status.BURN] = 9999
	target.status_magnitude[CG.Status.BURN] = 20.0
	var state := CombatState.new(_SEED)
	state.units = [caster, target]
	var rig := _ForceOnce.new()
	rig.caster_id = caster.id
	rig.action_id = action.id
	rig.target_id = target.id
	var deps := SimDeps.new()
	deps.default_decide = Callable(rig, "decide")
	## A bare caster has no `pawn` and no `EnemyLibrary` entry, which is what
	## `Tools/DummyRoom.gd`'s own rig works around: derive attack power from
	## the action's own `power_scale` rather than floor every hit at 0.
	deps.attack_power = func(_u: CombatUnit, a: ActionDef, _r) -> float: return 100.0 * a.power_scale
	for _i in 60:
		CombatSim.step(state, deps)

	assert_false(target.has_status(CG.Status.BURN), "the consume path strips the ignite it fires against")
	assert_true(target.hp < target.hp_max, "geyser blast landed no damage at all")
