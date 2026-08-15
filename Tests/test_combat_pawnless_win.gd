extends "res://Tests/TestCase.gd"

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")

## ISSUE 218, and rook's ruling on it: **a fight where every pawn is dead is not
## a victory.** The enemies are gone, so the simulation says PLAYER_WIN and goes
## on saying it -- this changes nothing about `_check_outcome`. What it adds is
## the question the end banner has to ask to tell that ending apart from a real
## win: `CombatSim.is_pawnless_win`.
##
## The question rook asked me to answer first was whether the two endings are
## distinguishable from `CombatState` alone, or whether telling them apart needs
## a new field in Core. **They are distinguishable and it does not.** Dead units
## stay in `state.units` with `alive == false`, and a pawn is the one player-team
## unit with `pawn != null`. `test_the_ending_is_visible_in_a_real_fight` is the
## proof, run against real content rather than a fixture.

const ENCOUNTER := &"floor1_warden"
const SEEDS := 40

func _party(skip: StringName) -> Array[PawnData]:
	var out: Array[PawnData] = []
	for cid in Registry.all_class_ids():
		if cid == skip:
			continue
		out.append(PawnFactory.make_starter_pawn(
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

# --- the predicate ----------------------------------------------------------

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

func test_a_pawnless_win_needs_both_halves() -> void:
	var state := CombatState.new(0)
	state.units.append(_pawn(0, false))
	state.units.append(_summon(1, CG.Team.PLAYER))
	state.outcome = CombatState.Outcome.ENEMY_WIN
	assert_false(CombatSim.is_pawnless_win(state), "a defeat is not a pawnless win")
	state.outcome = CombatState.Outcome.PLAYER_WIN
	assert_true(CombatSim.is_pawnless_win(state), "party gone, enemies gone: this is the ending")

func test_an_ordinary_win_is_not_a_pawnless_one() -> void:
	var state := CombatState.new(0)
	state.units.append(_pawn(0, true))
	state.outcome = CombatState.Outcome.PLAYER_WIN
	assert_false(CombatSim.is_pawnless_win(state), "somebody the player picked is still standing")

# --- the same question, asked of the real game ------------------------------

## Fixtures above prove the predicate reads what it is given. This proves the
## ending it names actually happens, in real content, and that the predicate
## sees it there -- the two are different claims, and only the second one can
## tell rook whether a Core field was needed.
##
## It also asserts every ordinary win in the same 40 fights answers false, which
## is the negative half: a predicate that said true everywhere would pass a
## one-sided version of this test and turn every victory into a defeat.
func test_the_ending_is_visible_in_a_real_fight() -> void:
	var encounter := Registry.get_encounter(ENCOUNTER)
	assert_true(encounter != null, "floor1_warden is registered")
	var wins := 0
	var pawnless := 0
	for s in SEEDS:
		var state := CombatSim.build(_party(&"abomination"), encounter, s)
		CombatSim.run(state)
		if state.outcome != CombatState.Outcome.PLAYER_WIN:
			assert_false(CombatSim.is_pawnless_win(state),
				"only a PLAYER_WIN can be a pawnless win")
			continue
		wins += 1
		if CombatSim.party_was_wiped(state):
			pawnless += 1
		else:
			assert_false(CombatSim.is_pawnless_win(state),
				"a win with survivors must read as an ordinary win")
	assert_true(wins > 0, "no wins at all in %d fights; this test measured nothing" % SEEDS)
	assert_true(pawnless > 0,
		("no pawnless win in %d fights on %s. Issue 233 measured 11 of 40 here. If "
		+ "content has genuinely stopped producing this ending, that is a finding "
		+ "worth reporting before this file is deleted.") % [SEEDS, ENCOUNTER])
	assert_true(pawnless < wins,
		"every single win was pawnless, which means the predicate is not discriminating")
