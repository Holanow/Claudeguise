extends SceneTree

## Issue 504: peak terrain feature count against FIGHT LENGTH, which is the
## slice `PoolPeak` does not take. #496's mitigation is an accident of fights
## being short, so the question is what the curve does when one is not.
##
## Sampled between steps, the same bound `PoolPeak` documents: a count taken
## inside `step()` is not what the renderer or the terrain walks ever see.

const SEEDS := 5

## Past `CG.MAX_TICKS` on purpose. `CombatSim.run` stops at the cap; this drives
## `step()` itself, so the cap is the tool's and the fight is what ends it.
const LONG_CAP := 20000

const LONG_CON := 400

## Where the curve is printed, in ticks.
const MILESTONES := [200, 400, 800, 1200, 1800, 2400, 3600, 6000, 10000, 20000]

var _lines := PackedStringArray()

func _say(line: String = "") -> void:
	_lines.append(line)
	print(line)

func _fingerprint() -> void:
	var body := "\n".join(_lines) + "\n"
	print("lines: %d" % _lines.size())
	print("fingerprint: %s" % body.sha256_text())

func _init() -> void:
	_say("seeds: %d, tool tick cap: %d (CG.MAX_TICKS is %d)" % [SEEDS, LONG_CAP, CG.MAX_TICKS])
	_say("four preset Geysermancers, every pickable room, run until the fight ends or the tool cap")
	for encounter_id in Registry.all_encounter_ids():
		_sweep(encounter_id)
	_starter_arm()
	_long_fight_arm()
	_fingerprint()
	quit(0)

func _party() -> Array[PawnData]:
	var party: Array[PawnData] = []
	for i in 4:
		var p := PawnFactory.make_starter_pawn(&"geysermancer", StringName("g%d" % i), "G%d" % i)
		p.plans = PresetPlans.for_class(&"geysermancer")
		party.append(p)
	return party

func _sweep(encounter_id: StringName) -> void:
	var encounter := Registry.get_encounter(encounter_id)
	var authored := encounter.terrain.size()
	_say("")
	_say("=== %s   authored=%d" % [encounter_id, authored])
	for s in SEEDS:
		var state := CombatSim.build(_party(), encounter, s)
		var peak := 0
		var peak_tick := 0
		# tick -> [total, water, burning], filled the first time the tick is reached.
		var at_milestone := {}
		var next_milestone := 0
		while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < LONG_CAP:
			CombatSim.step(state)
			var total := state.terrain.size()
			if total > peak:
				peak = total
				peak_tick = state.tick
			while next_milestone < MILESTONES.size() and state.tick >= MILESTONES[next_milestone]:
				at_milestone[MILESTONES[next_milestone]] = _composition(state)
				next_milestone += 1
		var added := 0
		var removed := 0
		for e in state.events:
			if e.kind == CG.EventKind.TERRAIN_ADDED:
				added += 1
			elif e.kind == CG.EventKind.TERRAIN_REMOVED:
				removed += 1
		var final := _composition(state)
		_say("  seed %d  ticks=%d outcome=%s  peak=%d@%d  final total=%d water=%d burning=%d  added=%d removed=%d  water/100t=%.1f" % [
			s, state.tick, _outcome_name(state.outcome), peak, peak_tick,
			final[0], final[1], final[2], added, removed,
			0.0 if state.tick == 0 else 100.0 * float(final[1]) / float(state.tick),
		])
		var parts := PackedStringArray()
		for m in MILESTONES:
			if at_milestone.has(m):
				var c: Array = at_milestone[m]
				parts.append("t%d:%d/%dw" % [m, c[0], c[1]])
		if parts.size() > 0:
			_say("    curve  " + "  ".join(parts))

## The arm that produced #496's 168: starter pawns, no plans, on the burn room.
func _starter_arm() -> void:
	_say("")
	_say("=== STARTER pawns (no plans) on floor1_hazard -- the arm that read 168")
	var encounter := Registry.get_encounter(&"floor1_hazard")
	for s in SEEDS:
		var party: Array[PawnData] = []
		for i in 4:
			party.append(PawnFactory.make_starter_pawn(&"geysermancer", StringName("g%d" % i), "G%d" % i))
		var state := CombatSim.build(party, encounter, s)
		var peak := 0
		while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < LONG_CAP:
			CombatSim.step(state)
			peak = maxi(peak, state.terrain.size())
		var f := _composition(state)
		_say("  seed %d  ticks=%d %s  peak=%d  final total=%d water=%d burning=%d  water/100t=%.1f" % [
			s, state.tick, _outcome_name(state.outcome), peak, f[0], f[1], f[2],
			0.0 if state.tick == 0 else 100.0 * float(f[1]) / float(state.tick),
		])

## The pathological long fight, constructed rather than waited for. Tanky enough
## to survive The Warden and too weak to finish it quickly, so the fight runs
## until the tool cap rather than until somebody dies. Nothing here is content:
## it is a party built in this file.
func _long_fight_arm() -> void:
	_say("")
	_say("=== CONSTRUCTED LONG FIGHT: 4 tanky, feeble Geysermancers vs The Warden")
	_say("    CON +%d and INT floored, so the fight does not end. Tool cap %d ticks." % [LONG_CON, LONG_CAP])
	var encounter := Registry.get_encounter(&"floor1_warden")
	for s in 2:
		var party: Array[PawnData] = []
		for i in 4:
			var p := PawnFactory.make_starter_pawn(&"geysermancer", StringName("g%d" % i), "G%d" % i)
			p.plans = PresetPlans.for_class(&"geysermancer")
			p.attribute_bonus[CG.Attribute.CON] = LONG_CON
			p.attribute_bonus[CG.Attribute.INT] = -7
			party.append(p)
		var state := CombatSim.build(party, encounter, s)
		var peak := 0
		var at_milestone := {}
		var next_milestone := 0
		# Wall clock per 500-tick block, against the water count in that block.
		# The question "does 329 features cost anything" is not answerable from
		# the count alone.
		var block_us := {}
		var block_start := Time.get_ticks_usec()
		while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < LONG_CAP:
			CombatSim.step(state)
			peak = maxi(peak, state.terrain.size())
			if state.tick % 500 == 0:
				block_us[state.tick] = [Time.get_ticks_usec() - block_start, state.terrain.size()]
				block_start = Time.get_ticks_usec()
			while next_milestone < MILESTONES.size() and state.tick >= MILESTONES[next_milestone]:
				at_milestone[MILESTONES[next_milestone]] = _composition(state)
				next_milestone += 1
		var f := _composition(state)
		_say("  seed %d  ticks=%d %s  peak=%d  final total=%d water=%d  water/100t=%.1f" % [
			s, state.tick, _outcome_name(state.outcome), peak, f[0], f[1],
			0.0 if state.tick == 0 else 100.0 * float(f[1]) / float(state.tick),
		])
		var parts := PackedStringArray()
		for m in MILESTONES:
			if at_milestone.has(m):
				var c: Array = at_milestone[m]
				parts.append("t%d:%dw" % [m, c[1]])
		_say("    curve  " + "  ".join(parts))
		var cost := PackedStringArray()
		for t in block_us.keys():
			var b: Array = block_us[t]
			cost.append("t%d:%.1fms@%df" % [t, float(b[0]) / 1000.0, b[1]])
		## Printed, NOT buffered: wall clock is not the fight, and a digest over
		## it moves between two identical runs. The fingerprint must cover only
		## what the simulation decided.
		print("    cost per 500 ticks  " + "  ".join(cost))
		var red := _water_redundancy(state)
		_say("    %d water stamps form %d puddle(s); %.0f area of rect summed over %.0f actually covered = %.1fx redundant" % [
			f[1], _water_clusters(state), red[0], red[1], 0.0 if red[1] <= 0.0 else red[0] / red[1],
		])

## Sum of the water rect areas against the area they actually cover, rasterised
## at 5 units. "One connected cluster" is not "one rectangle" -- a blob of 329
## squares has no Rect2 -- so the honest measure of what merging could win is
## how much of the pile is redundant cover.
func _water_redundancy(state: CombatState) -> Array:
	var rects: Array[Rect2] = []
	var sum_area := 0.0
	for f in state.terrain:
		if f.kind == Terrain.Kind.WATER:
			for r in f.regions():
				rects.append(r)
				sum_area += r.size.x * r.size.y
	if rects.is_empty():
		return [0.0, 0.0]
	var cells := {}
	for r in rects:
		var x := snappedf(r.position.x, 5.0)
		while x < r.end.x:
			var y := snappedf(r.position.y, 5.0)
			while y < r.end.y:
				cells[Vector2i(int(x / 5.0), int(y / 5.0))] = true
				y += 5.0
			x += 5.0
	return [sum_area, float(cells.size()) * 25.0]

## How many distinct puddles the water features actually form, by overlap.
## #504's cheapest proposed fix is to merge a new pool into an overlapping
## existing one instead of appending, and its value depends entirely on how much
## of this pile is overlap rather than spread. Union-find over the water rects.
func _water_clusters(state: CombatState) -> int:
	var rects: Array[Rect2] = []
	for f in state.terrain:
		if f.kind == Terrain.Kind.WATER:
			rects.append_array(f.regions())
	var parent: Array[int] = []
	for i in rects.size():
		parent.append(i)
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			if rects[i].intersects(rects[j]):
				var a := _find(parent, i)
				var b := _find(parent, j)
				if a != b:
					parent[a] = b
	var roots := {}
	for i in rects.size():
		roots[_find(parent, i)] = true
	return roots.size()

func _find(parent: Array[int], i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i

## [total, water, burning] right now.
## [total features, water STAMPS, burning]. Issue 554 made a pool one feature
## holding many rects, so counting features would report 1 however much ground
## is painted. The stored rect count is what the cost actually tracks.
func _composition(state: CombatState) -> Array:
	var water := 0
	var burning := 0
	for f in state.terrain:
		if f.kind == Terrain.Kind.WATER:
			water += f.regions().size()
		elif Terrain.is_burning(f):
			burning += 1
	return [state.terrain.size(), water, burning]

func _outcome_name(o: int) -> String:
	match o:
		CombatState.Outcome.PLAYER_WIN: return "WIN"
		CombatState.Outcome.ENEMY_WIN: return "LOSS"
		_: return "UNRESOLVED"
