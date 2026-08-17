extends SceneTree

## Issue 113, second measurement. How many rows does a team panel need?
##
##   godot --headless --path . --script res://Tools/TeamPanelLoad.gd
##
## OWNER: wren. Not part of the game and not part of the gate.
##
## `CooldownLoad.gd` answered "is a cooldown worth drawing". This answers the
## other question a fixed panel has to answer before it is drawn: **how tall is
## it.** A player-team unit is not always one of the four pawns -- the Siege
## Master's engines are player-team units built from an `EnemyDef`, and #75
## records what happens when the view forgets they exist. If a fight can put ten
## units on the player's side, a panel with one row each is a column of ten in a
## strip 260 px wide, and the design is wrong before it is written.

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const PartySelect := preload("res://Scripts/UI/PartySelect.gd")

const SEEDS := 10

func _init() -> void:
	print("=== issue 113: how many rows does the team panel need? ===")
	print("")

	var class_ids := Registry.all_class_ids()
	var parties: Array = []
	parties.append(class_ids.slice(0, mini(4, class_ids.size())))
	if class_ids.size() > 4:
		parties.append(class_ids.slice(class_ids.size() - 4))

	var peak := 0
	var peak_where := ""
	var histogram := {}
	var fights := 0
	for room_id in PartySelect.offered_rooms():
		var encounter := Registry.get_encounter(room_id)
		if encounter == null:
			continue
		for s in SEEDS:
			for party_ids in parties:
				fights += 1
				var most := _sample(encounter, party_ids, s)
				histogram[most] = int(histogram.get(most, 0)) + 1
				if most > peak:
					peak = most
					peak_where = "%s seed %d party %s" % [room_id, s, ", ".join(party_ids)]

	print("-- most player-team units alive at once, per fight, %d fights --" % fights)
	var counts := histogram.keys()
	counts.sort()
	for c in counts:
		print("  %2d units   %4d fights" % [c, int(histogram[c])])
	print("  peak %d  (%s)" % [peak, peak_where])
	quit(0)

## Most player-team units alive at any one tick of one fight. Sampled every
## tick: a summon that lives forty ticks and dies is not in the final state, and
## the panel has to have had a row for it while it was there.
func _sample(encounter, party_ids: Array, seed_value: int) -> int:
	var party: Array[PawnData] = []
	for cid in party_ids:
		party.append(PawnFactory.make_starter_pawn(
			cid, StringName("%s" % cid), Registry.get_class_def(cid).display_name))
	var state := CombatSim.build(party, encounter, seed_value)
	var most := 0
	while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
		CombatSim.step(state)
		var live := 0
		for u in state.units:
			if u.team == CG.Team.PLAYER and u.alive:
				live += 1
		most = maxi(most, live)
	return most
