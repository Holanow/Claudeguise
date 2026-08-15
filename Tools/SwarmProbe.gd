extends SceneTree

## Is the Rat King's swarm a swarm, and do the pickable rooms really run long?
##
##     godot --headless --path . --script res://Tools/SwarmProbe.gd
##
## Two questions, one instrument, because both are per-tick questions and a
## win table cannot answer either (announcement rule 1).
##
## **1. The swarm.** `RoomWatch` (PR #201) watched one seed of `floor1_rat_king`
## and saw peak 4 rats alive against 8 ever spawned -- the four the room starts
## with die and the king stands alone. That is one seed and one party, watched
## by eye. This counts the population **every tick**, so the answer is a curve
## rather than an anecdote: how many rats are alive at each moment, how long the
## room holds any rats at all, and how many the king ever produces.
##
## **2. The 90-second cap.** `RoomWatch` runs the real screen in real time and
## gives up at 90 seconds, which lands near tick 490. Three of five rooms hit
## that. "The fight is long" and "the instrument is short" are indistinguishable
## from inside `RoomWatch`, so this runs the same rooms headless to `MAX_TICKS`
## and reports where they actually finish.
##
## Measurement only. It changes nothing and is not part of the gate.

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")

const SEEDS := 12

## RoomWatch gave up here. Every room below is measured against it so the
## "short cap or long fight" question has a number rather than an impression.
const WATCH_CAP_TICKS := 493

const ROOMS := [
	&"floor1_room1",
	&"floor1_cover",
	&"floor1_hazard",
	&"floor1_chokepoint",
	&"floor1_rat_king",
]


func _init() -> void:
	var parties := _buildable_parties()
	print("SwarmProbe. %d seeds x %d buildable parties per room.\n" % [SEEDS, parties.size()])

	print("== 1. Where do the pickable rooms actually finish? ==")
	print("RoomWatch's real-time cap lands near tick %d." % WATCH_CAP_TICKS)
	print("%-20s %8s %8s %8s %10s %10s" % ["room", "median", "p90", "max", "past cap", "unresolved"])
	for room in ROOMS:
		var ticks: Array[int] = []
		var unresolved := 0
		for ids in parties:
			for s in range(SEEDS):
				var state := _run(room, ids, s)
				ticks.append(state.tick)
				if state.outcome == CombatState.Outcome.UNRESOLVED or state.outcome == CombatState.Outcome.DRAW:
					unresolved += 1
		var past := 0
		for t in ticks:
			if t > WATCH_CAP_TICKS:
				past += 1
		print("%-20s %8d %8d %8d %9d%% %9d%%" % [
			String(room), _quantile(ticks, 0.5), _quantile(ticks, 0.9), _quantile(ticks, 1.0),
			int(round(100.0 * float(past) / float(ticks.size()))),
			int(round(100.0 * float(unresolved) / float(ticks.size()))),
		])

	print("\n== 2. Is the swarm a swarm? floor1_rat_king, rats counted every tick ==")
	print("%-28s %6s %6s %7s %8s %9s %9s" % ["party", "peak", "ever", "mean", "median", "ticks>=4", "ticks==0"])
	var all_peak: Array[int] = []
	var all_ever: Array[int] = []
	for ids in parties:
		var peaks: Array[int] = []
		var evers: Array[int] = []
		var means: Array[int] = []
		var medians: Array[int] = []
		var four_plus: Array[int] = []
		var empty: Array[int] = []
		for s in range(SEEDS):
			var r := _watch_rats(ids, s)
			peaks.append(r["peak"])
			evers.append(r["ever"])
			means.append(r["mean_x100"])
			medians.append(r["median"])
			four_plus.append(r["pct_four_plus"])
			empty.append(r["pct_empty"])
		all_peak.append_array(peaks)
		all_ever.append_array(evers)
		print("%-28s %6d %6d %7.2f %8d %8d%% %8d%%" % [
			_party_label(ids), _quantile(peaks, 0.5), _quantile(evers, 0.5),
			float(_quantile(means, 0.5)) / 100.0, _quantile(medians, 0.5),
			_quantile(four_plus, 0.5), _quantile(empty, 0.5),
		])
	print("\nacross all %d fights: peak alive median %d / max %d, rats ever median %d / max %d" % [
		all_peak.size(), _quantile(all_peak, 0.5), _quantile(all_peak, 1.0),
		_quantile(all_ever, 0.5), _quantile(all_ever, 1.0),
	])

	print("\n== 3. WHY. Is it the spawn rate, the rat's life, or the king's? ==")
	print("%-28s %8s %9s %10s %10s %11s" % ["party", "lashes", "spawned", "rat life", "king dies", "fight ends"])
	var all_lashes: Array[int] = []
	var all_life: Array[int] = []
	for ids in parties:
		var lashes: Array[int] = []
		var spawned: Array[int] = []
		var life: Array[int] = []
		var king: Array[int] = []
		var ends: Array[int] = []
		for s in range(SEEDS):
			var r := _watch_rats(ids, s)
			lashes.append(r["lashes"])
			spawned.append(r["spawned"])
			life.append(r["median_life"])
			king.append(r["king_death"])
			ends.append(r["end_tick"])
		all_lashes.append_array(lashes)
		all_life.append_array(life)
		print("%-28s %8d %9d %10d %10d %11d" % [
			_party_label(ids), _quantile(lashes, 0.5), _quantile(spawned, 0.5),
			_quantile(life, 0.5), _quantile(king, 0.5), _quantile(ends, 0.5),
		])
	print("\nlash cycle is 20 wind-up + 22 recovery = 42 ticks. A fight of N ticks")
	print("affords about N/42 lashes if the king spends the whole fight lashing.")

	print("\n== 4. Can the king reach anything? Its range is 200. ==")
	print("%-28s %10s %11s %11s %11s" % ["party", "start gap", "closest", "ticks<=200", "% of fight"])
	for ids in parties:
		var starts: Array[int] = []
		var closest: Array[int] = []
		var in_range: Array[int] = []
		var pct: Array[int] = []
		for s in range(SEEDS):
			var r := _watch_king(ids, s)
			starts.append(r["start_gap"])
			closest.append(r["closest"])
			in_range.append(r["in_range"])
			pct.append(r["pct"])
		print("%-28s %10d %11d %11d %10d%%" % [
			_party_label(ids), _quantile(starts, 0.5), _quantile(closest, 0.5),
			_quantile(in_range, 0.5), _quantile(pct, 0.5),
		])
	print("\nking move_speed is 1.2 units/tick, the slowest in the game.")

	print("\n== 5. The king's own tick budget. Where do its 250 ticks go? ==")
	print("%-28s %8s %7s %7s %8s %9s %9s" % ["party", "alive", "starts", "fires", "misses", "in range", "walking"])
	for ids in parties:
		var rows := {"alive": [] as Array[int], "starts": [] as Array[int], "fires": [] as Array[int],
			"misses": [] as Array[int], "inr": [] as Array[int], "walk": [] as Array[int]}
		for s in range(SEEDS):
			var r := _king_budget(ids, s)
			rows["alive"].append(r["alive"])
			rows["starts"].append(r["starts"])
			rows["fires"].append(r["fires"])
			rows["misses"].append(r["misses"])
			rows["inr"].append(r["in_range"])
			rows["walk"].append(r["walking"])
		print("%-28s %8d %7d %7d %8d %9d %9d" % [
			_party_label(ids), _quantile(rows["alive"], 0.5), _quantile(rows["starts"], 0.5),
			_quantile(rows["fires"], 0.5), _quantile(rows["misses"], 0.5),
			_quantile(rows["inr"], 0.5), _quantile(rows["walk"], 0.5),
		])

	print("\n== 6. THE CAUSE. DefaultBehavior's ranged band, measured on the king. ==")
	print("A ranged unit fires only between range*0.6 and range*0.85. For a")
	print("200-range lash that is a 50-unit window, 120..170. Inside 120 it")
	print("RETREATS; beyond 170 it approaches.")
	print("%-28s %11s %11s %11s" % ["party", "<120 kite", "120-170 fire", ">170 walk"])
	for ids in parties:
		var kite: Array[int] = []
		var fire: Array[int] = []
		var walk: Array[int] = []
		for s in range(SEEDS):
			var r := _king_bands(ids, s)
			kite.append(r["kite"])
			fire.append(r["fire"])
			walk.append(r["walk"])
		print("%-28s %10d%% %10d%% %10d%%" % [
			_party_label(ids), _quantile(kite, 0.5), _quantile(fire, 0.5), _quantile(walk, 0.5),
		])

	print("\n== 7. Is the band a Rat King problem or a ranged problem? ==")
	print("Fires per enemy per 100 ticks of fight, every room, all five parties.")
	print("%-22s %8s %10s" % ["action", "range", "fires/100t"])
	var fired := {}
	var ranges := {}
	var total_ticks := 0
	for room in ROOMS:
		for ids in parties:
			for s in range(SEEDS):
				var state := _run(room, ids, s)
				total_ticks += state.tick
				for e in state.events:
					if e.kind != CG.EventKind.ACTION_FIRE:
						continue
					var by_enemy := false
					for u in state.units:
						if u.id == e.source_id and u.team == CG.Team.ENEMY:
							by_enemy = true
					if by_enemy:
						fired[e.action_id] = int(fired.get(e.action_id, 0)) + 1
	for aid in fired.keys():
		var a := Registry.get_action(aid)
		ranges[aid] = 0.0 if a == null else a.range_units
	var keys := PackedStringArray()
	for k in fired.keys():
		keys.append(String(k))
	keys.sort()
	for k in keys:
		var aid := StringName(k)
		print("%-22s %8.0f %10.2f" % [k, ranges[aid], 100.0 * float(fired[aid]) / float(maxi(1, total_ticks))])
	print("\nMELEE_RANGE_THRESHOLD decides which units the kite band applies to.")
	quit(0)


## The king's distance to its own chosen target, bucketed by which branch of
## `DefaultBehavior.decide` that distance selects. `_choose_target` with
## focus_bias 0.0 is the nearest living pawn, which is what this reproduces.
func _king_bands(ids: Array, fight_seed: int) -> Dictionary:
	var state := CombatSim.build(_pawns(ids, fight_seed), Registry.get_encounter(&"floor1_rat_king"), fight_seed)
	var kite := 0
	var fire := 0
	var walk := 0
	while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
		var king: CombatUnit = null
		for u in state.units:
			if u.enemy_id == &"rat_king":
				king = u
		if king == null or not king.alive:
			break
		var gap := INF
		for u in state.units:
			if u.team == CG.Team.PLAYER and u.alive:
				gap = minf(gap, king.position.distance_to(u.position))
		if gap == INF:
			break
		if gap < 200.0 * 0.6:
			kite += 1
		elif gap <= 200.0 * 0.85:
			fire += 1
		else:
			walk += 1
		CombatSim.step(state)
	var n := maxi(1, kite + fire + walk)
	return {
		"kite": int(round(100.0 * float(kite) / float(n))),
		"fire": int(round(100.0 * float(fire) / float(n))),
		"walk": int(round(100.0 * float(walk) / float(n))),
	}


## Every tick the king is alive, classified. A start that never becomes a fire
## is a wind-up abandoned; a fire that becomes a MISS is a rat that was never
## shed, since `_spawn_summon` sits on the effect path.
func _king_budget(ids: Array, fight_seed: int) -> Dictionary:
	var state := CombatSim.build(_pawns(ids, fight_seed), Registry.get_encounter(&"floor1_rat_king"), fight_seed)
	var alive_ticks := 0
	var in_range := 0
	var walking := 0
	while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
		var king: CombatUnit = null
		for u in state.units:
			if u.enemy_id == &"rat_king":
				king = u
		if king == null or not king.alive:
			break
		alive_ticks += 1
		var gap := 1 << 30
		for u in state.units:
			if u.team == CG.Team.PLAYER and u.alive:
				gap = mini(gap, int(round(king.position.distance_to(u.position))))
		var before := king.position
		CombatSim.step(state)
		if gap <= 200:
			in_range += 1
		if king.position.distance_to(before) > 0.01:
			walking += 1

	var starts := 0
	var fires := 0
	var misses := 0
	for e in state.events:
		if e.action_id != &"rat_king_lash":
			continue
		if e.kind == CG.EventKind.ACTION_START:
			starts += 1
		elif e.kind == CG.EventKind.ACTION_FIRE:
			fires += 1
		elif e.kind == CG.EventKind.MISS:
			misses += 1
	return {
		"alive": alive_ticks, "starts": starts, "fires": fires,
		"misses": misses, "in_range": in_range, "walking": walking,
	}


## Distance from the king to the nearest living pawn, every tick. `rat_king_lash`
## has range 200; `DefaultBehavior` walks a unit at its target until `dist` is
## inside the action's range, so a king that never gets inside 200 never lashes,
## and a king that never lashes never sheds a rat.
func _watch_king(ids: Array, fight_seed: int) -> Dictionary:
	var state := CombatSim.build(_pawns(ids, fight_seed), Registry.get_encounter(&"floor1_rat_king"), fight_seed)
	var start_gap := -1
	var closest := 1 << 30
	var in_range := 0
	var ticks := 0
	while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
		CombatSim.step(state)
		ticks += 1
		var king: CombatUnit = null
		for u in state.units:
			if u.enemy_id == &"rat_king" and u.alive:
				king = u
		if king == null:
			break
		var gap := 1 << 30
		for u in state.units:
			if u.team == CG.Team.PLAYER and u.alive:
				gap = mini(gap, int(round(king.position.distance_to(u.position))))
		if gap == 1 << 30:
			break
		if start_gap < 0:
			start_gap = gap
		closest = mini(closest, gap)
		if gap <= 200:
			in_range += 1
	var n := maxi(1, ticks)
	return {
		"start_gap": maxi(0, start_gap),
		"closest": closest if closest < (1 << 30) else 0,
		"in_range": in_range,
		"pct": int(round(100.0 * float(in_range) / float(n))),
	}


## The five parties `PartySelect` can build: five classes, four slots, so the
## leave-one-out set. Sorted as `String`, because `Array[StringName].sort()`
## compares interned pointers and is not alphabetical.
func _buildable_parties() -> Array:
	var names := PackedStringArray()
	for id in Registry.all_class_ids():
		names.append(String(id))
	names.sort()
	var out := []
	for skip in names.size():
		var party: Array[StringName] = []
		for i in names.size():
			if i != skip:
				party.append(StringName(names[i]))
		out.append(party)
	return out


func _party_label(ids: Array) -> String:
	var all := PackedStringArray()
	for id in Registry.all_class_ids():
		all.append(String(id))
	all.sort()
	for n in all:
		if not ids.has(StringName(n)):
			return "no_" + n
	return "?"


func _pawns(ids: Array, fight_seed: int) -> Array[PawnData]:
	var out: Array[PawnData] = []
	for i in ids.size():
		out.append(PawnFactory.make_starter_pawn(
			ids[i], StringName("%s_%d_%d" % [ids[i], fight_seed, i]), String(ids[i])
		))
	return out


func _run(room: StringName, ids: Array, fight_seed: int) -> CombatState:
	var state := CombatSim.build(_pawns(ids, fight_seed), Registry.get_encounter(room), fight_seed)
	CombatSim.run(state)
	return state


## Steps one tick at a time and counts live rats after each. `run()` cannot be
## used here: the population only exists between ticks and is gone by the time
## the fight ends, which is announcement rule 2 -- a thing that dies inside
## `step()` cannot be observed from outside it.
func _watch_rats(ids: Array, fight_seed: int) -> Dictionary:
	var state := CombatSim.build(_pawns(ids, fight_seed), Registry.get_encounter(&"floor1_rat_king"), fight_seed)
	var seen := {}
	var born := {}
	var died := {}
	var series: Array[int] = []
	while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
		CombatSim.step(state)
		var alive := 0
		for u in state.units:
			if u.enemy_id != &"rat":
				continue
			if not seen.has(u.id):
				seen[u.id] = true
				born[u.id] = state.tick
			if u.alive:
				alive += 1
			elif not died.has(u.id):
				died[u.id] = state.tick
		series.append(alive)

	var lashes := 0
	var king_death := state.tick
	for e in state.events:
		if e.kind == CG.EventKind.ACTION_FIRE and e.action_id == &"rat_king_lash":
			lashes += 1
		elif e.kind == CG.EventKind.DEATH:
			for u in state.units:
				if u.id == e.target_id and u.enemy_id == &"rat_king":
					king_death = e.tick

	var lives: Array[int] = []
	for rid in born.keys():
		lives.append(int(died.get(rid, state.tick)) - int(born[rid]))
	var peak := 0
	var total := 0
	var four_plus := 0
	var empty := 0
	for a in series:
		peak = maxi(peak, a)
		total += a
		if a >= 4:
			four_plus += 1
		if a == 0:
			empty += 1
	var n := maxi(1, series.size())
	return {
		"peak": peak,
		"ever": seen.size(),
		"mean_x100": int(round(100.0 * float(total) / float(n))),
		"median": _quantile(series, 0.5),
		"pct_four_plus": int(round(100.0 * float(four_plus) / float(n))),
		"pct_empty": int(round(100.0 * float(empty) / float(n))),
		"lashes": lashes,
		"spawned": maxi(0, seen.size() - 4),
		"median_life": _quantile(lives, 0.5),
		"king_death": king_death,
		"end_tick": state.tick,
	}


func _quantile(values: Array[int], q: float) -> int:
	if values.is_empty():
		return 0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[clampi(int(floor(q * float(sorted.size() - 1))), 0, sorted.size() - 1)]
