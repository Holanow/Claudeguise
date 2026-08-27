extends SceneTree

## Issue 567: why a Siege Engine starts an action and never fires.
##
## Reproduces #567's fight, then prints one timeline per engine: when it was
## built, when it started a bolt, whether anything was marked at that moment,
## and when it died. Reads `state.events` and unit fields only; it never calls
## `decide`, so it cannot perturb the fight.

const SEEDS := 12

func _init() -> void:
	var encounter := RoomLibrary.get_room(CG.DEFAULT_ENCOUNTER)
	var bolt := ActionLibrary.get_action(&"siege_engine_bolt")
	var mark := ActionLibrary.get_action(&"spotter_mark")
	print("bolt: wind_up=%d recover=%d range=%.0f marked_only=%s" % [
		bolt.wind_up_ticks, bolt.recover_ticks, bolt.range_units, str(bolt.requires_marked_target)])
	print("mark: cost=%d duration=%d range=%.0f" % [
		mark.resource_cost, mark.status_duration_ticks, mark.range_units])
	var built := 0
	var fired := 0
	var died_winding := 0
	for s in SEEDS:
		var party: Array[PawnData] = [
			PawnFactory.make_preset_pawn(&"siege_master", &"sm", "SM"),
			PawnFactory.make_preset_pawn(&"warrior", &"wa", "WA"),
		]
		var state := CombatSim.build(party, encounter, s)
		CombatSim.run(state)
		var engines := {}
		for u in state.units:
			if u.pawn == null and u.team == CG.Team.PLAYER:
				engines[u.id] = u
		var marks: Array[int] = []
		for e in state.events:
			if e.kind == CG.EventKind.STATUS_APPLIED and e.status == CG.Status.MARKED:
				marks.append(e.tick)
		var lines := PackedStringArray()
		for id in engines:
			var starts: Array[int] = []
			var fires := 0
			var death := -1
			var summoned := -1
			for e in state.events:
				if e.kind == CG.EventKind.SUMMONED and e.target_id == id:
					summoned = e.tick
				if e.source_id != id:
					if e.kind == CG.EventKind.DEATH and e.target_id == id:
						death = e.tick
					continue
				match e.kind:
					CG.EventKind.ACTION_START: starts.append(e.tick)
					CG.EventKind.ACTION_FIRE: fires += 1
			built += 1
			fired += fires
			var last_start := -1 if starts.is_empty() else starts[starts.size() - 1]
			if fires == 0 and last_start >= 0 and death >= 0 and death - last_start < bolt.wind_up_ticks:
				died_winding += 1
			lines.append("    engine %d: built@%s starts=%s fires=%d death@%s  (needed %d ticks of wind-up)" % [
				id, str(summoned), str(starts), fires, str(death), bolt.wind_up_ticks])
		print("seed %d  ticks=%d  marks_applied=%d %s" % [s, state.tick, marks.size(), str(marks.slice(0, 6))])
		for l in lines:
			print(l)
	print("")
	print("TOTAL engines %d, bolts fired %d, died mid-wind-up %d" % [built, fired, died_winding])
	quit(0)
