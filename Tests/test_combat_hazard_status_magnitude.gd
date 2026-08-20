extends "res://Tests/TestCase.gd"


## ISSUE 204: a hazard declares the magnitude its status hits for.

const _SEED := 20400

## Every status whose damage is entirely magnitude-scaled, measured off the real
## `SimDeps` rather than typed in here. A hand-written list would agree with
## itself forever and say nothing about the game -- the failure mode #144
## records.
func _magnitude_only_statuses() -> Array:
	var deps := SimDeps.new()
	var u := _unit(0, CG.Team.PLAYER, 500, Vector2.ZERO)
	var out: Array = []
	for status in [CG.Status.BURN, CG.Status.POISON, CG.Status.BLEED]:
		var flat: float = deps.status_damage_per_tick.call(u, status)
		var per_magnitude: float = deps.status_damage_per_magnitude.call(u, status)
		if flat <= 0.0 and per_magnitude > 0.0:
			out.append(status)
	return out

func _unit(id: int, team: CG.Team, hp: int, pos: Vector2) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.hp_max = hp
	u.hp = hp
	u.position = pos
	u.move_speed = 0.0
	return u

func _idle_deps() -> SimDeps:
	var deps := SimDeps.new()
	deps.default_decide = func(_s: CombatState, _u: CombatUnit) -> Intent: return Intent.idle()
	deps.plan_decide = func(_s: CombatState, _u: CombatUnit) -> Intent: return null
	return deps

## One victim standing in one hazard, and one distant enemy so the fight does
## not end before the status has ticked.
func _stand_in(pit: Terrain.Feature, ticks: int) -> CombatUnit:
	var state := CombatState.new(_SEED)
	state.terrain = [pit]
	state.units.append(_unit(0, CG.Team.PLAYER, 500, Vector2.ZERO))
	state.units.append(_unit(1, CG.Team.ENEMY, 500, Vector2(600.0, 0.0)))
	var deps := _idle_deps()
	for _i in ticks:
		CombatSim.step(state, deps)
	return state.unit(0)

## A magnitude big enough that every damage tick lands a whole point, so the
## stochastic rounding cannot make the assertion below a coin flip. Derived from
## Balance rather than typed, so it survives a change to the burn rate.
func _magnitude_for_a_whole_point(status: CG.Status) -> float:
	var deps := SimDeps.new()
	var u := _unit(0, CG.Team.PLAYER, 500, Vector2.ZERO)
	var per_magnitude: float = deps.status_damage_per_magnitude.call(u, status)
	return ceil(1.0 / per_magnitude)

func _burn_pit(magnitude: float) -> Terrain.Feature:
	var pit := Terrain.make(Terrain.Kind.HAZARD, Rect2(-50.0, -50.0, 100.0, 100.0))
	pit.applies_status_enabled = true
	pit.applies_status = _magnitude_only_statuses()[0]
	pit.status_duration_ticks = 120
	pit.status_magnitude = magnitude
	return pit

# ---------------------------------------------------------------------------

## The set is not empty. Without this every test below would pass vacuously the
## day BURN, POISON and BLEED all regain a flat base.
func test_at_least_one_status_is_magnitude_only() -> void:
	assert_true(_magnitude_only_statuses().size() > 0,
		"no status is magnitude-only any more; issue 204 is moot and this file can go")

## THE FIX. A hazard that declares a magnitude burns for it.
func test_a_hazard_that_declares_a_magnitude_deals_damage() -> void:
	var status: CG.Status = _magnitude_only_statuses()[0]
	var magnitude := _magnitude_for_a_whole_point(status)
	var victim := _stand_in(_burn_pit(magnitude), 120)
	assert_true(victim.has_status(status), "the hazard did apply the status")
	assert_almost_eq(float(victim.status_magnitude.get(status, 0.0)), magnitude, 0.0001,
		"the hazard's declared magnitude is what the status carries")
	assert_true(victim.hp < victim.hp_max,
		"a hazard-applied magnitude-only status still deals nothing; issue 204 is not fixed")

## The negative half. Declaring nothing still ticks for nothing, which is why
## the authoring assertion below has to exist.
func test_a_hazard_that_declares_no_magnitude_still_deals_nothing() -> void:
	var victim := _stand_in(_burn_pit(0.0), 60)
	var status: CG.Status = _magnitude_only_statuses()[0]
	assert_true(victim.has_status(status), "the hazard did apply the status")
	assert_eq(victim.hp, victim.hp_max,
		"a hazard with no declared magnitude has nothing to scale its damage by")

## A fiercer burn from a hit is not watered down by standing in a weak fire.
func test_a_weak_hazard_never_lowers_a_magnitude_already_carried() -> void:
	var status: CG.Status = _magnitude_only_statuses()[0]
	var pit := _burn_pit(2.0)
	var state := CombatState.new(_SEED)
	state.terrain = [pit]
	state.units.append(_unit(0, CG.Team.PLAYER, 500, Vector2.ZERO))
	state.units.append(_unit(1, CG.Team.ENEMY, 500, Vector2(600.0, 0.0)))
	var victim := state.unit(0)
	victim.statuses[status] = 9999
	victim.status_magnitude[status] = 30.0
	var deps := _idle_deps()
	for _i in 10:
		CombatSim.step(state, deps)
	assert_almost_eq(float(victim.status_magnitude.get(status, 0.0)), 30.0, 0.0001,
		"the weaker hazard overwrote a fiercer burn")

## A status with no magnitude term is untouched by the field: the tar pit's
## SLOWED reads the same before and after issue 204.
func test_a_magnitude_less_status_is_unaffected() -> void:
	var pit := Terrain.make(Terrain.Kind.HAZARD, Rect2(-50.0, -50.0, 100.0, 100.0))
	pit.applies_status_enabled = true
	pit.applies_status = CG.Status.SLOWED
	pit.status_duration_ticks = 120
	var victim := _stand_in(pit, 20)
	assert_true(victim.has_status(CG.Status.SLOWED), "the tar pit still slows")
	assert_eq(victim.hp, victim.hp_max, "SLOWED never dealt damage and still does not")

## THE AUTHORING RULE, replacing #204's tripwire. Terrain may now apply a
## magnitude-scaled status -- but only if it says how hard.
func test_authored_terrain_that_applies_a_scaled_dot_declares_its_magnitude() -> void:
	var magnitude_only := _magnitude_only_statuses()
	var checked := 0
	for encounter_id in Registry.all_encounter_ids():
		var encounter := Registry.get_encounter(encounter_id)
		if encounter == null:
			continue
		for feature in encounter.terrain:
			checked += 1
			if not feature.applies_status_enabled:
				continue
			if not magnitude_only.has(feature.applies_status):
				continue
			assert_true(feature.status_magnitude > 0.0,
				("%s applies status %d from terrain and declares no magnitude. That "
				+ "status's whole damage rate is a multiple of one, so it will tick "
				+ "for zero. Set `status_magnitude` on the feature.") % [encounter_id, feature.applies_status])
	assert_true(checked > 0, "no terrain features found at all; this test measured nothing")
