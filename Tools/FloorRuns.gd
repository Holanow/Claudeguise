extends SceneTree

## How far does a party get down a floor, rather than how one fight goes.


const SEEDS := 20

func _init() -> void:
	var class_ids := ClassLibrary.all_ids()
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
	var entry_res_by_depth := {}

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
			# Resource, because reporting only hp hid a real cause for hours.
			if not entry_res_by_depth.has(depth):
				entry_res_by_depth[depth] = []
			entry_res_by_depth[depth].append(_entry_resource_percent(run, party))

			var result := FloorFightRunner.play_room(run, room, party)
			var outcome: FloorFightRunner.Outcome = result.outcome
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
	var res_line := "  party resource entering room:"
	for d in range(6):
		if entry_res_by_depth.has(d) and not entry_res_by_depth[d].is_empty():
			res_line += "  %d:%d%%" % [d + 1, _median(entry_res_by_depth[d])]

	var line := "  party health entering room:"
	for d in range(6):
		if entry_hp_by_depth.has(d) and not entry_hp_by_depth[d].is_empty():
			line += "  %d:%d%%" % [d + 1, _median(entry_hp_by_depth[d])]
	print(line)
	print(res_line)
	print("")

## Resource, not hp. `Balance.between_room_heal` restores health and **never
## touches resource**, so a party can walk into a boss at 85% hp with its casters
## on 2 of 102 mana -- which is exactly what was happening to one real party for
## hours while this tool reported it as healthy.
func _entry_resource_percent(run: FloorRun, party: Array[PawnData]) -> int:
	var res := 0
	var res_max := 0
	for p in party:
		var full := Balance.max_resource(p)
		if full <= 0:
			continue
		res += maxi(0, run.resource_for(p.id, full) if run.is_alive(p.id) else 0)
		res_max += full
	if res_max <= 0:
		return 100
	return int(round(100.0 * float(res) / float(res_max)))

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
