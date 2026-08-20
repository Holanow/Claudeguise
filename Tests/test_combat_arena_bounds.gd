extends "res://Tests/TestCase.gd"


## Issue 16's own criterion 3, against real content rather than hand-built
## fixtures: "the four-class party on seed 0000002A reaches a real outcome
## well before CG.MAX_TICKS." Before this issue's fix, this seed drew at
## the cap with survivors twenty arena widths off the map -- pasted in the
## issue itself. A permanent regression test rather than a one-off
## measurement: if the stalemate ever comes back, this is where it shows up.

func test_the_measured_stalemate_seed_now_resolves_well_before_the_cap() -> void:
	var encounter_ids := Registry.all_encounter_ids()
	assert_false(encounter_ids.is_empty(), "no encounter registered")
	if encounter_ids.is_empty():
		return
	var encounter := Registry.get_encounter(encounter_ids[0])

	var party: Array[PawnData] = [
		PawnFactory.make_starter_pawn(&"warrior", &"warrior", "Warrior"),
		PawnFactory.make_starter_pawn(&"priest", &"priest", "Priest"),
		PawnFactory.make_starter_pawn(&"geysermancer", &"geysermancer", "Geysermancer"),
		PawnFactory.make_starter_pawn(&"siege_master", &"siege_master", "Siege Master"),
	]

	var seed := 0x0000002A
	var state := CombatSim.build(party, encounter, seed)
	var outcome := CombatSim.run(state)

	print("issue 16, seed 0000002A: outcome=%s ticks=%d (was DRAW at %d, the cap)" % [
		CombatState.Outcome.keys()[outcome], state.tick, CG.MAX_TICKS
	])

	assert_ne(outcome, CombatState.Outcome.DRAW, "the measured stalemate seed must no longer draw at the cap")
	assert_true(state.tick < CG.MAX_TICKS / 2, "should resolve well before the cap, not just before it: took %d ticks" % state.tick)

	for u in state.units:
		assert_true(
			absf(u.position.x) <= CG.ARENA_HALF_WIDTH and absf(u.position.y) <= CG.ARENA_HALF_HEIGHT,
			"unit %d ended outside the arena at %s -- the exact defect this issue fixes" % [u.id, u.position]
		)

## The other half of criterion 3: a fight that genuinely cannot resolve must
## still draw at the cap, so the safety net has not been disabled along with
## the stalemate this issue targets.
func test_a_fight_that_truly_cannot_resolve_still_draws_at_the_cap() -> void:
	var state := CombatState.new(999)
	var deps := preload("res://Scripts/Combat/SimDeps.gd").new()
	deps.default_decide = func(_s, _u): return preload("res://Scripts/Core/Intent.gd").idle()
	var CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")
	var a := CombatUnit.new()
	a.id = 0
	a.team = CG.Team.PLAYER
	a.hp_max = 10
	a.hp = 10
	a.position = Vector2(-400, 0)
	var b := CombatUnit.new()
	b.id = 1
	b.team = CG.Team.ENEMY
	b.hp_max = 10
	b.hp = 10
	b.position = Vector2(400, 0)
	state.units.append(a)
	state.units.append(b)

	CombatSim.run(state, deps)

	assert_eq(state.outcome, CombatState.Outcome.DRAW, "two units that never act must still draw at the cap")
	assert_eq(state.tick, CG.MAX_TICKS)
