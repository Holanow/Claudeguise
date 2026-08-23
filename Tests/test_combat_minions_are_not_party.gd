extends "res://Tests/TestCase.gd"


## ISSUE 445, and it overturns issue 233. A minion is not part of the party: the
## fight is lost when the last pawn dies whatever else is still standing, and a
## summon dies with its summoner. `CombatSim.is_party_member` is the only
## definition of "your party" in the game and every other reader asks it.

const ENCOUNTER := &"floor1_warden"
const SEEDS := 40

func _party(skip: StringName) -> Array[PawnData]:
	var out: Array[PawnData] = []
	for cid in Registry.all_class_ids():
		if cid == skip:
			continue
		out.append(PawnFactory.make_preset_pawn(
			cid, StringName("%s_%d" % [cid, out.size()]), String(cid)))
	return out

func _pawn(id: int, alive: bool) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = CG.Team.PLAYER
	u.pawn = PawnData.new()
	u.alive = alive
	return u

func _summon(id: int, team: CG.Team) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.enemy_id = &"siege_engine"
	return u

# --- the one definition -----------------------------------------------------

func test_a_summon_is_not_a_party_member() -> void:
	assert_true(CombatSim.is_party_member(_pawn(0, true)), "a pawn the player picked")
	assert_false(CombatSim.is_party_member(_summon(1, CG.Team.PLAYER)),
		"a siege engine stands on the player's team and is still not one of the four")
	assert_false(CombatSim.is_party_member(_summon(2, CG.Team.ENEMY)), "an enemy is not a party member")

func test_living_party_counts_pawns_only() -> void:
	var state := CombatState.new(0)
	state.units.append(_pawn(0, false))
	state.units.append(_pawn(1, true))
	state.units.append(_summon(2, CG.Team.PLAYER))
	assert_eq(CombatSim.living_party(state).size(), 1, "one pawn up, one down, one engine")

func test_a_party_with_one_pawn_standing_is_not_wiped() -> void:
	var state := CombatState.new(0)
	state.units.append(_pawn(0, false))
	state.units.append(_pawn(1, true))
	assert_false(CombatSim.party_was_wiped(state), "one pawn is still up")

func test_a_party_of_corpses_is_wiped_even_with_summons_standing() -> void:
	var state := CombatState.new(0)
	state.units.append(_pawn(0, false))
	state.units.append(_pawn(1, false))
	state.units.append(_summon(2, CG.Team.PLAYER))
	assert_true(CombatSim.party_was_wiped(state),
		"a live summon is not a survivor; it was never one of the four the player picked")

## The half that stops the banner reading Defeat on every level-editor test
## fight, which can be built with no party at all.
func test_a_fight_with_no_pawns_at_all_is_not_a_wipe() -> void:
	var state := CombatState.new(0)
	state.units.append(_summon(0, CG.Team.PLAYER))
	state.units.append(_summon(1, CG.Team.ENEMY))
	assert_false(CombatSim.party_was_wiped(state),
		"no pawn ever existed here, so no pawn was wiped")

# --- the same question, asked of the real game ------------------------------

## Issue 233 measured 11 pawnless wins in these same 40 fights. The ruling says
## every one of them is a loss, so the count must now be zero.
func test_no_win_survives_the_last_pawn() -> void:
	var encounter := Registry.get_encounter(ENCOUNTER)
	assert_true(encounter != null, "floor1_warden is registered")
	var wins := 0
	for s in SEEDS:
		var state := CombatSim.build(_party(&"abomination"), encounter, s)
		CombatSim.run(state)
		if state.outcome != CombatState.Outcome.PLAYER_WIN:
			continue
		wins += 1
		assert_false(CombatSim.party_was_wiped(state),
			"seed %d won with no pawn alive; the fight should have ended when the last one fell" % s)
	assert_true(wins > 0, "no wins at all in %d fights; this test measured nothing" % SEEDS)

## The other half of the ruling, asked of every death in a real fight: a summon
## may not outlive the unit that made it, on either team.
func test_a_summon_never_outlives_its_summoner() -> void:
	var encounter := Registry.get_encounter(ENCOUNTER)
	var checked := 0
	for s in SEEDS:
		var state := CombatSim.build(_party(&"abomination"), encounter, s)
		CombatSim.run(state)
		var death_tick := {}
		for e in state.events:
			if e.kind == CG.EventKind.DEATH and not death_tick.has(e.target_id):
				death_tick[e.target_id] = e.tick
		for e in state.events:
			if e.kind != CG.EventKind.SUMMONED:
				continue
			if not death_tick.has(e.source_id):
				continue
			checked += 1
			assert_true(death_tick.has(e.target_id),
				"seed %d: summoner %d died and its summon %d never did" % [s, e.source_id, e.target_id])
			assert_true(int(death_tick.get(e.target_id, 1 << 30)) <= int(death_tick[e.source_id]),
				"seed %d: summon %d outlived summoner %d" % [s, e.target_id, e.source_id])
	assert_true(checked > 0,
		"no summoner died in %d fights on %s, so this test measured nothing" % [SEEDS, ENCOUNTER])
