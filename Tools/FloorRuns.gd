extends SceneTree

## How far does a party get down a floor, rather than how one fight goes.
##
##   godot --headless --path . --script res://Tools/FloorRuns.gd
##
## MANAGER-OWNED. Not part of the game and not part of the gate.
##
## Every balance number this project owns describes **one fight, from full
## health**. The player pointed out the thing that makes those numbers
## incomplete: a run is several fights in a row, and a party does not
## necessarily heal between them.
##
## `FloorRun` carries hp and resource forward exactly and restores nothing --
## checked in the file rather than assumed -- and a dead pawn stays dead. So a
## party that wins a room on 23% of its health starts the next one on 23%. The
## single-fight table says that is a good fight. This tool asks what it does to
## a run, which is a different question and the one that decides whether a floor
## is playable.
##
## Reports rooms cleared, not win rate, because "won the fight and then died in
## the next one" is not a win in any sense the player cares about.
##
## **TRUST THIS TOOL'S DEPTH NUMBERS ONLY AFTER SOMEBODY EXPLAINS THIS.** On its
## first run, three different parties produced byte-identical room histograms
## (1:2 2:3 3:11 4:3 5:1) while differing in how often they cleared the floor
## (0, 0 and 0 against 8 and 9 for the other two). Identical outcomes across
## different parties is the exact signature of the "the seed does nothing" bug
## this project spent hours on, and it may equally be an artifact of how few
## rooms a floor has. I do not know which, so I am not quoting the depths.
##
## What the same run established and *is* solid, read out of the source rather
## than inferred: `FloorRun.record_result` stores hp and resource after every
## fight, `hp_for` returns the carried value, nothing anywhere restores any of
## it, and a dead pawn stays dead. And party health reads 100% entering the
## second fight because `_encounter_for` slices the enemy list to
## `room.difficulty`, so early rooms hold one or two enemies and cost nothing.
## That is real, not a measurement error.

const CG := preload("res://Scripts/Core/CG.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const FloorGenerator := preload("res://Scripts/Floor/FloorGenerator.gd")
const FloorRun := preload("res://Scripts/Floor/FloorRun.gd")
const FloorRoom := preload("res://Scripts/Floor/FloorRoom.gd")
const FloorFightRunner := preload("res://Scripts/Floor/FloorFightRunner.gd")
const Balance := preload("res://Scripts/Content/Balance.gd")

const SEEDS := 20

func _init() -> void:
	var class_ids := Registry.all_class_ids()
	if class_ids.size() < 5:
		printerr("need five classes")
		quit(1)
		return

	print("Floor runs: how many rooms deep a party gets before it is wiped.")
	print("%d seeds per party. Nothing heals between rooms.\n" % SEEDS)

	for skip in class_ids.size():
		var ids := []
		for i in class_ids.size():
			if i != skip:
				ids.append(class_ids[i])
		_run_party(ids, String(class_ids[skip]))
	quit(0)

func _run_party(ids: Array, left_out: String) -> void:
	var depths: Array[int] = []
	var cleared_floor := 0
	var entry_hp_by_depth := {}

	for s in range(SEEDS):
		var plan := FloorGenerator.generate(s)
		var run := FloorRun.new(plan)
		var party: Array[PawnData] = []
		for cid in ids:
			var c := StringName(cid)
			party.append(PawnFactory.make_starter_pawn(
				c, StringName("%s" % cid), Registry.get_class_def(c).display_name
			))

		var depth := 0
		var wiped := false
		for room_id in plan.reachable_from_entrance():
			var room := plan.room(room_id)
			run.enter(room_id)
			if not FloorFightRunner.is_fight_room(room.type):
				# Only TREASURE has a resolution path; the runner push_errors on
				# anything else, and TRAP/LIBRARY/CELL have none yet.
				if room.type == FloorRoom.Type.TREASURE:
					FloorFightRunner.play_treasure_room(run, room)
				else:
					run.enter(room_id)
				continue
			# Party health entering this room, before the fight resolves.
			var pct := _entry_percent(run, party)
			if not entry_hp_by_depth.has(depth):
				entry_hp_by_depth[depth] = []
			entry_hp_by_depth[depth].append(pct)

			var outcome := FloorFightRunner.play_room(run, room, party)
			if outcome == FloorFightRunner.Outcome.DEFEAT:
				wiped = true
				break
			depth += 1
		depths.append(depth)
		if not wiped:
			cleared_floor += 1

	print("party without the %s" % left_out)
	print("  rooms cleared  %s" % _histogram(depths))
	print("  cleared the whole floor: %d of %d" % [cleared_floor, SEEDS])
	var line := "  party health entering room:"
	for d in range(6):
		if entry_hp_by_depth.has(d) and not entry_hp_by_depth[d].is_empty():
			line += "  %d:%d%%" % [d + 1, _median(entry_hp_by_depth[d])]
	print(line)
	print("")

func _entry_percent(run: FloorRun, party: Array[PawnData]) -> int:
	var hp := 0
	var hp_max := 0
	for p in party:
		# hp_for returns full health for a pawn with no recorded result yet,
		# which is what an unfought pawn should read as.
		# PawnData has no hp_max; it is derived from attributes by Balance.
		var full := Balance.max_hp(p)
		hp += maxi(0, run.hp_for(p.id, full) if run.is_alive(p.id) else 0)
		hp_max += full
	if hp_max <= 0:
		return 0
	return int(round(100.0 * float(hp) / float(hp_max)))

func _histogram(values: Array[int]) -> String:
	var counts := {}
	for v in values:
		counts[v] = int(counts.get(v, 0)) + 1
	var keys := counts.keys()
	keys.sort()
	var out := ""
	for k in keys:
		out += "%d:%-3d " % [k, counts[k]]
	return out

func _median(values: Array) -> int:
	if values.is_empty():
		return 0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]
