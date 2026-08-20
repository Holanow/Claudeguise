extends "res://Tests/TestCase.gd"


## ISSUE 204, ARMED AND NOT YET FIRED. A TRIPWIRE, NOT A FIX.

const _SEED := 20400

## Every status whose damage is entirely magnitude-scaled, measured off the real
## `SimDeps` rather than typed in here. A hand-written list would agree with
## itself forever and say nothing about the game -- the failure mode #144
## records. If content gives BURN a flat base back, this set shrinks on its own
## and the tripwire correctly stops firing for it.
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

# ---------------------------------------------------------------------------

## The set is not empty. Without this the two tests below would both pass
## vacuously the day BURN, POISON and BLEED all regain a flat base -- a tripwire
## measuring an empty list is the "X never happens is also passed by X can never
## be observed" rule, and it has bitten this project twice.
func test_at_least_one_status_is_magnitude_only() -> void:
	assert_true(_magnitude_only_statuses().size() > 0,
		"no status is magnitude-only any more; issue 204 is moot and this file can go")

## THE TRIPWIRE. Red the moment content arms it.
func test_no_authored_terrain_applies_a_magnitude_scaled_dot() -> void:
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
			assert_false(magnitude_only.has(feature.applies_status),
				("%s applies status %d from terrain, and that status's whole damage "
				+ "rate is a multiple of a magnitude a hazard never writes. It will "
				+ "tick for zero. See issue 204: give the feature a magnitude of its "
				+ "own, or give the status a flat base back.") % [encounter_id, feature.applies_status])
	assert_true(checked > 0, "no terrain features found at all; this test measured nothing")

## THE REASON. Red the moment #204 is fixed, which is when the tripwire above
## should be deleted along with this file.
func test_the_reason_the_tripwire_exists_is_still_true() -> void:
	var magnitude_only := _magnitude_only_statuses()
	if magnitude_only.is_empty():
		return
	var status: CG.Status = magnitude_only[0]

	var pit := Terrain.make(Terrain.Kind.HAZARD, Rect2(-50.0, -50.0, 100.0, 100.0))
	pit.applies_status_enabled = true
	pit.applies_status = status
	pit.status_duration_ticks = 120

	var state := CombatState.new(_SEED)
	state.terrain = [pit]
	state.units.append(_unit(0, CG.Team.PLAYER, 500, Vector2.ZERO))
	state.units.append(_unit(1, CG.Team.ENEMY, 500, Vector2(600.0, 0.0)))
	var victim := state.unit(0)

	var deps := _idle_deps()
	for _i in 60:
		CombatSim.step(state, deps)

	assert_true(victim.has_status(status), "the hazard did apply the status")
	assert_almost_eq(float(victim.status_magnitude.get(status, 0.0)), 0.0, 0.0001,
		"a hazard writes no magnitude -- it has no hit to take one from")
	assert_eq(victim.hp, victim.hp_max,
		("a hazard-applied magnitude-only status still deals nothing. If this line "
		+ "is red, issue 204 has been fixed and this whole file should be deleted, "
		+ "tripwire included."))
