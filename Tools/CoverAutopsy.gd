extends SceneTree

## Issue 818: floor1_cover kills 40% of arm B runs, more than any other room.
## This asks what does the killing, rather than assuming the count is the cause.
## Every four-class composition, fresh full-health party, so the room is
## measured on its own rather than through whatever a run carried in.

const SEEDS := 40
## `floor1_rat_king` is not one of the four ten-enemy rooms. It is here because
## it is the only other room that fields rats, so it is the control on issue
## 818's own warning: a change to the rat itself would land there too.
## Issue 830 adds `floor1_warden`: the boss room is measured beside its peers
## because it has been the second-easiest room on the floor.
const ROOMS := [&"floor1_cover", &"floor1_room1", &"floor1_hazard", &"floor1_chokepoint",
	&"floor1_rat_king", &"floor1_warden"]

func _init() -> void:
	print("CoverAutopsy -- fresh full-health preset party, no equipment beyond PawnFactory's")
	print("  rooms        %s" % [ROOMS])
	print("  seeds        %d per composition, seed = hash([s, room_id])" % [SEEDS])
	print("  parties      %d compositions of %d from %s" % [
		PartySpec.compositions().size(), PartySpec.PARTY_SIZE, ClassLibrary.all_ids()])
	print("  pawns        PawnFactory.make_preset_pawn (arm B, planned)")
	print("  RoomScale    %s, NOT APPLIED -- this tool measures the authored room" % [
		RoomScale.Mode.keys()[RoomScale.MODE]])
	print("  fights       %d per room" % [PartySpec.compositions().size() * SEEDS])
	print("  NOTE: the by-ability table is DIRECT HITS ONLY. DamageLedger routes")
	print("        status damage to by_dot, printed separately under each room.")
	for rid in ROOMS:
		var totals := {}
		var dots := {}
		var wins := 0
		var deaths := 0.0
		var runs := 0
		## Issue 830: how long the room lasts. A boss that dies in fourteen
		## seconds cannot be made harder by giving it more abilities, and
		## without this number that reads as the abilities not working.
		var ticks := 0
		for combo in PartySpec.compositions():
			for s in range(SEEDS):
				var party: Array[PawnData] = []
				for cid in combo:
					var c := StringName(cid)
					party.append(PawnFactory.make_preset_pawn(c, c, ClassLibrary.get_class_def(c).display_name))
				var state := CombatSim.build(party, RoomLibrary.get_room(rid), hash([s, rid]))
				CombatSim.run(state)
				runs += 1
				ticks += state.tick
				if state.outcome == CombatState.Outcome.PLAYER_WIN:
					wins += 1
				for j in party.size():
					if not state.unit(j).alive:
						deaths += 1.0
				var l := DamageLedger.build(state)
				for aid in l.by_ability.get(CG.Team.ENEMY, {}):
					var r = l.by_ability[CG.Team.ENEMY][aid]
					if not totals.has(aid):
						totals[aid] = {"total": 0, "hits": 0}
					totals[aid].total += int(r.total)
					totals[aid].hits += int(r.casts)
				for st in l.by_dot.get(CG.Team.ENEMY, {}):
					var r = l.by_dot[CG.Team.ENEMY][st]
					if not dots.has(st):
						dots[st] = {"total": 0, "ticks": 0}
					dots[st].total += int(r.total)
					dots[st].ticks += int(r.ticks)
		var rows := []
		for aid in totals:
			rows.append([totals[aid].total, String(aid), totals[aid].hits])
		rows.sort_custom(func(a, b): return a[0] > b[0])
		var grand := 0
		for r in rows:
			grand += r[0]
		print("\n=== %s  win %d/%d (%d%%)  deaths %.2f/fight" % [String(rid), wins, runs,
			int(round(100.0 * wins / runs)), deaths / float(runs)])
		for r in rows:
			print("   %-22s %6d  (%2d%% of the room's damage) over %d hits" % [
				r[1], r[0], int(round(100.0 * r[0] / maxf(1.0, grand))), r[2]])
		var dot_rows := []
		for st in dots:
			dot_rows.append([dots[st].total, String(CG.Status.keys()[st]), dots[st].ticks])
		dot_rows.sort_custom(func(a, b): return a[0] > b[0])
		for r in dot_rows:
			print("   DoT %-18s %6d  (+%d%% on top of the table above) over %d ticks" % [
				r[1], r[0], int(round(100.0 * r[0] / maxf(1.0, grand))), r[2]])
	quit(0)
