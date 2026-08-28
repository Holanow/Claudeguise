extends SceneTree

## Issue 166. What the Channel does to a real fight, measured against the same
## fight without it. Nothing here decides a number; it reports one.
##
## Both arms run the same encounters and the same seeds. Arm B rebuilds the
## pre-166 starter pawn out of the shipped one -- the Channel row removed and
## the Robes taken back off -- so the only difference between the arms is the
## ability and the two points of WIS that pay for its row.
##
## Nothing is sampled mid-tick: every count below comes from `state.events`
## after the fight, so no probe reads a unit between decide and recover.

const SEEDS := 20
const CLASSES := ["warrior", "priest", "abomination", "geysermancer", "siege_master"]
const CHANNEL := &"channel_mana"
const CASTERS := [&"priest", &"geysermancer"]

func _init() -> void:
	print("seeds per party per encounter: ", SEEDS)
	var encounters := RoomLibrary.all_ids()
	for with_channel in [false, true]:
		print("")
		print("========================================================")
		print("ARM: ", "WITH the Channel (shipped)" if with_channel else "WITHOUT (pre-166 pawns)")
		print("========================================================")
		var wins := 0
		var losses := 0
		var draws := 0
		var fights := 0
		var fires := 0
		var channel_ticks := 0
		var interrupted := 0
		for skip in CLASSES:
			var party_ids := _party_without(skip)
			for enc_id in encounters:
				for s in SEEDS:
					var pair := _run(party_ids, enc_id, s, with_channel)
					var state: CombatState = pair[0]
					fights += 1
					match pair[1]:
						CombatState.Outcome.PLAYER_WIN: wins += 1
						CombatState.Outcome.ENEMY_WIN: losses += 1
						_: draws += 1
					for e in state.events:
						if e.action_id != CHANNEL:
							continue
						if e.kind == CG.EventKind.ACTION_FIRE:
							fires += 1
						elif e.kind == CG.EventKind.INTERRUPTED:
							interrupted += 1
							channel_ticks += e.amount
		var restored := fires * ActionLibrary.get_action(CHANNEL).restores_resource
		print("fights          %d" % fights)
		print("player wins     %d (%.1f%%)" % [wins, 100.0 * float(wins) / float(fights)])
		print("player losses   %d (%.1f%%)" % [losses, 100.0 * float(losses) / float(fights)])
		print("draws           %d" % draws)
		print("Channels landed %d  (%.2f a fight)" % [fires, float(fires) / float(fights)])
		print("Channels broken %d by a stun, %d wasted ticks" % [interrupted, channel_ticks])
		print("Mana restored   %d" % restored)
	quit(0)

func _party_without(skip: String) -> Array:
	var out := []
	for c in CLASSES:
		if c != skip:
			out.append(c)
	return out

func _run(ids: Array, enc_id: StringName, s: int, with_channel: bool) -> Array:
	var party: Array[PawnData] = []
	for cid in ids:
		var c := StringName(cid)
		## `make_preset_pawn`: since #399 a starter pawn has no plan rows, so the
		## Channel row this probe removes was never there and both arms were the
		## same party (#472).
		var pawn := PawnFactory.make_preset_pawn(
			c, StringName("%s_%d" % [cid, party.size()]), ClassLibrary.get_class_def(c).display_name)
		if not with_channel:
			_strip_channel(pawn, c)
		party.append(pawn)
	var state := CombatSim.build(party, RoomLibrary.get_room(enc_id), s)
	var outcome := CombatSim.run(state)
	return [state, outcome]

## The pre-166 pawn: no Channel row, and no armour on the two casters.
func _strip_channel(pawn: PawnData, class_id: StringName) -> void:
	var kept: Array[Plan] = []
	for p in pawn.plans:
		var uses_channel := false
		for b in p.blocks:
			var probed: ActionDef = (b as UseActionBlock).action if b is UseActionBlock else null
			if probed != null and probed.id == CHANNEL:
				uses_channel = true
		if not uses_channel:
			kept.append(p)
	pawn.plans = kept
	if CASTERS.has(class_id):
		pawn.body = null
