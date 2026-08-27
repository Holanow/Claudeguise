extends "res://Tests/TestCase.gd"


## ISSUE 445, and it overturns issue 233. A minion is not part of the party: the
## fight is lost when the last pawn dies whatever else is still standing, and a
## summon dies with its summoner. `CombatSim.is_party_member` is the only
## definition of "your party" in the game and every other reader asks it.

## Issue 592 pushed the two casters out to 350 units, and this party now WINS
## the Warden room on most seeds, so no summoner dies and the test measured
## nothing. Repointed at the nest, which is the room #592 made hardest -- same
## reasoning as the WINNABLE_ENCOUNTER split below, and the opposite direction.
const ENCOUNTER := &"floor1_rat_king"

## Issue 489 made the Warden unwinnable for this party, and a test that wins 0
## of 40 measures nothing. This one is about pawnless wins rather than about
## difficulty, so it asks an easier room instead of a looser threshold.
const WINNABLE_ENCOUNTER := &"floor1_room1"
const SEEDS := 40

func _party(skip: StringName) -> Array[PawnData]:
	var out: Array[PawnData] = []
	for cid in ClassLibrary.all_ids():
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