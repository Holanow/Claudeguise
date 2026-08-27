extends SceneTree

## Issue 405: is `floor1_cover`'s 1-in-20 the room or the empty plan editor?
## One party, one room, and the same three arms `Tools/PlanGap.gd` uses, at
## enough seeds that a 5% rate is not a sampling story. Reads the finished
## outcome; nothing samples a live unit.

const SEEDS := 200

## The party #405 measured. It is the blind playtester's, and it is the one
## party of five with no Abomination in it.
const PARTY: Array[StringName] = [&"warrior", &"priest", &"geysermancer", &"siege_master"]

const ROOMS: Array[StringName] = [&"floor1_cover", &"floor1_room1"]

func _init() -> void:
	print("party: ", PARTY, "   seeds: ", SEEDS)
	for room_id in ROOMS:
		var encounter := RoomLibrary.get_room(room_id)
		print("")
		print("======== ", room_id, " ========")
		for arm in [&"unedited", &"first_row", &"library"]:
			print("  %-12s %s" % [arm, _run(encounter, arm)])
	quit(0)

func _run(encounter, arm: StringName) -> String:
	var wins := 0
	var hp_total := 0
	for s in SEEDS:
		var party: Array[PawnData] = []
		for cid in PARTY:
			party.append(_pawn(cid, StringName("%s_%d" % [cid, party.size()]), arm))
		var state := CombatSim.build(party, encounter, s)
		if CombatSim.run(state) == CombatState.Outcome.PLAYER_WIN:
			wins += 1
		hp_total += _party_hp_percent(state)
	return "%3d/%3d (%5.1f%%)   mean party hp %2d%%" % [
		wins, SEEDS, 100.0 * float(wins) / float(SEEDS), hp_total / SEEDS,
	]

func _pawn(class_id: StringName, pawn_id: StringName, arm: StringName) -> PawnData:
	if arm == &"unedited":
		return PawnFactory.make_starter_pawn(class_id, pawn_id, String(class_id))
	var pawn := PawnFactory.make_preset_pawn(class_id, pawn_id, String(class_id))
	if arm == &"first_row":
		var top: Array[Plan] = []
		if not pawn.plans.is_empty():
			top.append(pawn.plans[0])
		pawn.plans = top
	return pawn

static func _party_hp_percent(state: CombatState) -> int:
	var h := 0
	var h_max := 0
	for u in state.units:
		if u.team != CG.Team.PLAYER or u.pawn == null:
			continue
		h += maxi(0, u.hp)
		h_max += u.hp_max
	return 0 if h_max <= 0 else int(round(100.0 * float(h) / float(h_max)))
