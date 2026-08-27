extends SceneTree

## Issue #421: how much of the arena the fight occupies at each tick, not over
## the whole fight. Samples positions before `CombatSim.step()`.
const SEEDS := 10
const CF_SEEDS := 6
const CLASSES := ["warrior", "priest", "abomination", "geysermancer", "siege_master"]

## Set true to measure pawns carrying their preset plans instead of the starter
## pawn the game actually ships, which since #399 has no plan rows (#417).
const USE_PRESET_PLANS := false

## The fifth playtester's 200x120px region, converted: their arena was 795x450px
## against 960x540 world units.
const WIN_HALF_W := 121.0
const WIN_HALF_H := 72.0

const KEYS := ["box", "core", "core_w", "core_h", "ink", "pack", "gap", "window"]
const WORST := ["worst_win", "worst_core", "melee_d", "ranged_d"]

var _arena_area := 0.0
var _per_enc := {}
var _by_count := {}

func _init() -> void:
	var aw := CG.ARENA_HALF_WIDTH * 2.0
	var ah := CG.ARENA_HALF_HEIGHT * 2.0
	_arena_area = aw * ah
	print("arena %.0f x %.0f world units, area %.0f" % [aw, ah, _arena_area])
	print("plans: %s" % ("preset" if USE_PRESET_PLANS else "starter (what the build ships)"))
	print("")

	for enc_id in Registry.pickable_encounter_ids():
		var a := _fresh()
		for left_out in CLASSES:
			for s in range(SEEDS):
				_run(_party_without(left_out), Registry.get_encounter(enc_id), s, a, _by_count)
		_sort_all(a)
		_per_enc[enc_id] = a

	_roster_table()
	_occupancy_table()
	_worst_table()
	_densest_moments()
	_standoff_table()
	_headcount_table()
	_roster_size_counterfactual()
	_scale_arithmetic()
	_verify()
	quit(0)

## Every fight again with sampling switched off, compared on tick, outcome and
## surviving health. A probe that reads positions must not move any of them.
func _verify() -> void:
	var perturbed := 0
	var checked := 0
	for enc_id in Registry.pickable_encounter_ids():
		for left_out in CLASSES:
			for s in range(SEEDS):
				var probed := _fingerprint(_party_without(left_out), Registry.get_encounter(enc_id), s, true)
				var bare := _fingerprint(_party_without(left_out), Registry.get_encounter(enc_id), s, false)
				checked += 1
				if probed != bare:
					perturbed += 1
	print("VERIFY: %d fights re-run unprobed, %d perturbed." % [checked, perturbed])

func _fingerprint(ids: Array, enc: Encounter, s: int, probe: bool) -> String:
	var acc := _fresh()
	var party: Array[PawnData] = []
	for cid in ids:
		var c := StringName(cid)
		var pid := StringName("%s_%d" % [cid, party.size()])
		var dn := ClassLibrary.get_class_def(c).display_name
		party.append(PawnFactory.make_preset_pawn(c, pid, dn) if USE_PRESET_PLANS else PawnFactory.make_starter_pawn(c, pid, dn))
	var state := CombatSim.build(party, enc, s)
	while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
		if probe:
			_sample(state, acc, {})
		CombatSim.step(state)
	var hp := 0
	for u in state.units:
		hp += maxi(0, u.hp)
	return "%d/%d/%d/%d" % [state.tick, state.outcome, hp, state.units.size()]

# --- tables ----------------------------------------------------------------

func _roster_table() -> void:
	print("ROSTER: an attack of more than %.0f units is ranged (DefaultBehavior)" % DefaultBehavior.MELEE_RANGE_THRESHOLD)
	print("%-18s %7s %7s %7s  %s" % ["encounter", "enemies", "melee", "ranged", "enemy spawn spread"])
	for enc_id in Registry.pickable_encounter_ids():
		var enc := Registry.get_encounter(enc_id)
		var melee := 0
		var lo := Vector2(1e9, 1e9)
		var hi := Vector2(-1e9, -1e9)
		for spawn in enc.enemy_spawns:
			if _longest_attack(EnemyLibrary.get_enemy(spawn["enemy_id"]).actions) <= DefaultBehavior.MELEE_RANGE_THRESHOLD:
				melee += 1
			var p: Vector2 = spawn["position"]
			lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
			hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
		var n := enc.enemy_spawns.size()
		print("%-18s %7d %7d %7d  %.0f x %.0f" % [enc_id, n, melee, n - melee, hi.x - lo.x, hi.y - lo.y])
	print("")
	print("party: 2 melee (warrior 40, abomination 45), 3 ranged (priest 220, geysermancer 200, siege_master 200); 4 of the 5 are fielded")
	print("")

func _occupancy_table() -> void:
	print("PER-TICK OCCUPANCY. 'core' is the box around the 60%% of living units")
	print("nearest the centroid, grown by one drawn body radius. 'window' is the")
	print("most units any %.0fx%.0f box holds that tick." % [WIN_HALF_W * 2.0, WIN_HALF_H * 2.0])
	print("")
	print("%-18s %4s %7s %7s %7s %7s %9s %7s %7s" % ["encounter", "n", "core10", "core50", "core90", "all50", "core p50 px", "win50", "win90"])
	print("%-18s %4s %7s %7s %7s %7s %9s %7s %7s" % ["---------", "----", "-------", "-------", "-------", "-------", "---------", "-------", "-------"])
	for enc_id in Registry.pickable_encounter_ids():
		var a: Dictionary = _per_enc[enc_id]
		var enc := Registry.get_encounter(enc_id)
		print("%-18s %4d %6.1f%% %6.1f%% %6.1f%% %6.1f%% %4.0fx%-4.0f %7.1f %7.1f"
			% [enc_id, enc.enemy_spawns.size() + 4,
				100.0 * _at(a["core"], 0.10), 100.0 * _at(a["core"], 0.50), 100.0 * _at(a["core"], 0.90),
				100.0 * _at(a["box"], 0.50), _at(a["core_w"], 0.50), _at(a["core_h"], 0.50),
				_at(a["window"], 0.50), _at(a["window"], 0.90)])
		print("%-18s %4s ink p50 %.1f%% of arena, bodies fill the core box %.0f%%, nearest-neighbour gap p50 %.0f world units"
			% ["", "", 100.0 * _at(a["ink"], 0.5), 100.0 * _at(a["pack"], 0.5), _at(a["gap"], 0.5)])
	print("")

## The playtester saw one moment, not a median. This is that moment: per fight,
## the tick where the most units shared the playtester's region.
func _worst_table() -> void:
	print("WORST TICK PER FIGHT. Each fight contributes one number: its densest tick.")
	print("%-18s %7s %7s %7s %7s %9s %9s" % ["encounter", "fights", "win p50", "win p90", "win max", "tightest core p50", "ticks >=6 in win"])
	for enc_id in Registry.pickable_encounter_ids():
		var a: Dictionary = _per_enc[enc_id]
		var w: Array[float] = a["window"]
		var over6 := 0
		var over8 := 0
		for v in w:
			if v >= 6.0:
				over6 += 1
			if v >= 8.0:
				over8 += 1
		print("%-18s %7d %7.0f %7.0f %7.0f %9.1f%% %8.0f%% (>=8: %.0f%%)"
			% [enc_id, (a["worst_win"] as Array[float]).size(),
				_at(a["worst_win"], 0.50), _at(a["worst_win"], 0.90), _at(a["worst_win"], 1.0),
				100.0 * _at(a["worst_core"], 0.50),
				100.0 * float(over6) / float(maxi(1, w.size())),
				100.0 * float(over8) / float(maxi(1, w.size()))])
	print("")

## The single densest tick found in each room, named so a screenshot can be
## taken of that exact moment.
func _densest_moments() -> void:
	print("DENSEST MOMENT PER ROOM: reproduce with this party, seed and tick.")
	for enc_id in Registry.pickable_encounter_ids():
		var best := {"win": -1}
		for left_out in CLASSES:
			for s in range(SEEDS):
				var ids := _party_without(left_out)
				var found := _peak(ids, Registry.get_encounter(enc_id), s)
				if found["win"] > best["win"]:
					best = found
					best["party"] = ", ".join(ids)
					best["seed"] = s
		print("  %-18s %d units in the window at tick %d, seed %d, party [%s]"
			% [enc_id, best["win"], best["tick"], best["seed"], best["party"]])
	print("")

func _peak(ids: Array, enc: Encounter, s: int) -> Dictionary:
	var acc := _fresh()
	var party: Array[PawnData] = []
	for cid in ids:
		var c := StringName(cid)
		var pid := StringName("%s_%d" % [cid, party.size()])
		party.append(PawnFactory.make_starter_pawn(c, pid, ClassLibrary.get_class_def(c).display_name))
	var state := CombatSim.build(party, enc, s)
	var out := {"win": -1, "tick": 0}
	while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
		var t := state.tick
		var row := _sample(state, acc, {})
		if not row.is_empty() and int(row["window"]) > out["win"]:
			out = {"win": int(row["window"]), "tick": t}
		CombatSim.step(state)
	return out

## Where each unit stands relative to the nearest enemy, which is what sets the
## size of the box: melee close to contact, ranged stop at their commit fraction.
func _standoff_table() -> void:
	print("STANDOFF: distance from a unit to its nearest opponent, every tick.")
	print("%-18s %10s %10s %10s %10s %10s %10s" % ["encounter", "melee p10", "melee p50", "melee p90", "rng p10", "rng p50", "rng p90"])
	for enc_id in Registry.pickable_encounter_ids():
		var a: Dictionary = _per_enc[enc_id]
		print("%-18s %10.0f %10.0f %10.0f %10.0f %10.0f %10.0f"
			% [enc_id, _at(a["melee_d"], 0.10), _at(a["melee_d"], 0.50), _at(a["melee_d"], 0.90),
				_at(a["ranged_d"], 0.10), _at(a["ranged_d"], 0.50), _at(a["ranged_d"], 0.90)])
	print("")

func _headcount_table() -> void:
	print("OCCUPANCY BY LIVING HEADCOUNT, pooled over every tick of every fight.")
	print("Confounded: low counts are late-fight survivors, not a smaller room.")
	print("%-6s %8s %7s %7s %9s %7s" % ["alive", "ticks", "core10", "core50", "core p50 px", "win50"])
	print("%-6s %8s %7s %7s %9s %7s" % ["-----", "--------", "-------", "-------", "---------", "-------"])
	var by_count := _by_count
	var counts := by_count.keys()
	counts.sort()
	for c in counts:
		var a: Dictionary = by_count[c]
		if (a["core"] as Array[float]).size() < 200:
			continue
		_sort_all(a)
		print("%-6d %8d %6.1f%% %6.1f%% %4.0fx%-4.0f %7.1f"
			% [c, (a["core"] as Array[float]).size(),
				100.0 * _at(a["core"], 0.10), 100.0 * _at(a["core"], 0.50),
				_at(a["core_w"], 0.50), _at(a["core_h"], 0.50), _at(a["window"], 0.50)])
	print("")

## Lever 1, measured rather than guessed: the same rooms with the tail of the
## spawn list removed. Nothing in the content changes; the roster is trimmed here.
func _roster_size_counterfactual() -> void:
	print("LEVER 1 -- FEWER ENEMIES. The same room, spawn list truncated. PREDICTION.")
	print("%-18s %6s %7s %7s %9s %7s %7s" % ["encounter", "enemies", "core10", "core50", "core p50 px", "win50", "win90"])
	print("%-18s %6s %7s %7s %9s %7s %7s" % ["---------", "------", "-------", "-------", "---------", "-------", "-------"])
	for enc_id in Registry.pickable_encounter_ids():
		var base := Registry.get_encounter(enc_id)
		if base.enemy_spawns.size() < 10:
			continue
		for keep: int in [4, 6, 8, 10]:
			var a := _fresh()
			for left_out in CLASSES:
				for s in range(CF_SEEDS):
					_run(_party_without(left_out), _truncated(base, keep), s, a, {})
			_sort_all(a)
			print("%-18s %6d %6.1f%% %6.1f%% %4.0fx%-4.0f %7.1f %7.1f"
				% [enc_id if keep == 4 else "", keep,
					100.0 * _at(a["core"], 0.10), 100.0 * _at(a["core"], 0.50),
					_at(a["core_w"], 0.50), _at(a["core_h"], 0.50),
					_at(a["window"], 0.50), _at(a["window"], 0.90)])
	print("")

## Levers 2 and 3 are arithmetic on numbers already measured above, printed so
## nobody has to redo it: neither changes where a unit stands.
func _scale_arithmetic() -> void:
	var a := _fresh()
	for enc_id in ["floor1_room1", "floor1_cover", "floor1_hazard", "floor1_chokepoint"]:
		var src: Dictionary = _per_enc[StringName(enc_id)]
		for k in KEYS:
			(a[k] as Array[float]).append_array(src[k])
	_sort_all(a)
	var w := _at(a["core_w"], 0.5)
	var h := _at(a["core_h"], 0.5)
	var gap := _at(a["gap"], 0.5)
	print("LEVER 2 -- SMALLER ARENA. PREDICTION. Median core box over the four")
	print("ten-enemy rooms is %.0f x %.0f world units. Spawns and ranges are absolute," % [w, h])
	print("so the box does not shrink with the arena; only the empty margin does.")
	print("%-22s %9s %9s" % ["arena (world units)", "core%", "x current"])
	for f: float in [1.0, 0.8, 0.65, 0.5, 0.4]:
		var na := (CG.ARENA_HALF_WIDTH * 2.0 * f) * (CG.ARENA_HALF_HEIGHT * 2.0 * f)
		print("%-22s %8.1f%% %8.2f" % ["%.0f x %.0f" % [CG.ARENA_HALF_WIDTH * 2.0 * f, CG.ARENA_HALF_HEIGHT * 2.0 * f], 100.0 * w * h / na, (w * h / na) / (w * h / _arena_area)])
	print("")
	print("LEVER 3 -- BIGGER UNITS. PREDICTION. DISPLAY_SCALE is view-only;")
	print("CombatUnit.radius feeds TerrainGrid.move_blocked and changes fights.")
	print("Median nearest-neighbour gap between drawn bodies is %.0f world units at DISPLAY_SCALE %.1f." % [gap, UnitView.DISPLAY_SCALE])
	print("%-8s %9s %11s" % ["scale", "ink%", "gap (units)"])
	for sc: float in [1.5, 1.75, 2.0, 2.25, 2.5]:
		var ratio := sc / UnitView.DISPLAY_SCALE
		var ink := 100.0 * _at(a["ink"], 0.5) * ratio * ratio
		# A pair 22+22 apart at scale 1.5 loses 44*(ratio-1) of that gap.
		print("%-8.2f %8.1f%% %11.0f" % [sc, ink, gap - 44.0 * (ratio - 1.0)])
	print("")

# --- machinery -------------------------------------------------------------

func _truncated(base: Encounter, keep: int) -> Encounter:
	var e := Encounter.new()
	e.id = base.id
	e.display_name = base.display_name
	e.enemy_spawns = base.enemy_spawns.slice(0, keep)
	e.party_spawns = base.party_spawns
	e.terrain = base.terrain
	return e

## A unit whose longest attack outranges DefaultBehavior's melee threshold.
func _is_ranged(u: CombatUnit) -> bool:
	return _longest_attack(u.actions) > DefaultBehavior.MELEE_RANGE_THRESHOLD

func _longest_attack(ids: Array) -> float:
	var best := 0.0
	for id in ids:
		best = maxf(best, ActionLibrary.get_action(id).range_units)
	return best

func _party_without(left_out: String) -> Array:
	var ids: Array = []
	for c in CLASSES:
		if c != left_out:
			ids.append(c)
	return ids

func _fresh() -> Dictionary:
	var d := {}
	for k in KEYS + WORST:
		var arr: Array[float] = []
		d[k] = arr
	return d

func _sort_all(d: Dictionary) -> void:
	for k in KEYS + WORST:
		(d[k] as Array[float]).sort()

func _run(ids: Array, enc: Encounter, s: int, acc: Dictionary, by_count: Dictionary) -> void:
	var party: Array[PawnData] = []
	for cid in ids:
		var c := StringName(cid)
		var pid := StringName("%s_%d" % [cid, party.size()])
		var dn := ClassLibrary.get_class_def(c).display_name
		party.append(PawnFactory.make_preset_pawn(c, pid, dn) if USE_PRESET_PLANS else PawnFactory.make_starter_pawn(c, pid, dn))
	var state := CombatSim.build(party, enc, s)
	var worst_win := 0.0
	var worst_core := 1e9
	while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
		var row := _sample(state, acc, by_count)
		if not row.is_empty():
			worst_win = maxf(worst_win, row["window"])
			worst_core = minf(worst_core, row["core"])
		CombatSim.step(state)
	if worst_core < 1e9:
		(acc["worst_win"] as Array[float]).append(worst_win)
		(acc["worst_core"] as Array[float]).append(worst_core)

## Reads positions only. Nothing here writes state or draws from its rng.
func _sample(state: CombatState, acc: Dictionary, by_count: Dictionary) -> Dictionary:
	var live: Array[CombatUnit] = []
	for u in state.units:
		if u.hp > 0:
			live.append(u)
	if live.size() < 2:
		return {}

	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	var ink := 0.0
	var margin := 0.0
	var centroid := Vector2.ZERO
	for u in live:
		lo = Vector2(minf(lo.x, u.position.x), minf(lo.y, u.position.y))
		hi = Vector2(maxf(hi.x, u.position.x), maxf(hi.y, u.position.y))
		var r := UnitView.display_radius(u)
		ink += PI * r * r
		margin = maxf(margin, r)
		centroid += u.position
	centroid /= float(live.size())

	var best_win := 0
	var gaps := 0.0
	for u in live:
		var c := 0
		var nearest := 1e9
		for other in live:
			if absf(other.position.x - u.position.x) <= WIN_HALF_W and absf(other.position.y - u.position.y) <= WIN_HALF_H:
				c += 1
			if other != u:
				nearest = minf(nearest, u.position.distance_to(other.position) - (UnitView.display_radius(u) + UnitView.display_radius(other)))
		best_win = maxi(best_win, c)
		gaps += nearest

	# Subsampled: one tick in five is plenty for a distribution and keeps the
	# arrays small.
	if state.tick % 5 == 0:
		for u in live:
			var nearest_foe := 1e9
			for other in live:
				if other.team != u.team:
					nearest_foe = minf(nearest_foe, u.position.distance_to(other.position))
			if nearest_foe < 1e9:
				(acc["ranged_d" if _is_ranged(u) else "melee_d"] as Array[float]).append(nearest_foe)

	var dists: Array[float] = []
	for u in live:
		dists.append(u.position.distance_to(centroid))
	var ranked := dists.duplicate()
	ranked.sort()
	var k := maxi(2, int(ceil(0.6 * float(live.size()))))
	var limit: float = ranked[k - 1]
	var clo := Vector2(1e9, 1e9)
	var chi := Vector2(-1e9, -1e9)
	for i in range(live.size()):
		if dists[i] > limit:
			continue
		clo = Vector2(minf(clo.x, live[i].position.x), minf(clo.y, live[i].position.y))
		chi = Vector2(maxf(chi.x, live[i].position.x), maxf(chi.y, live[i].position.y))
	var cw := chi.x - clo.x + 2.0 * margin
	var ch := chi.y - clo.y + 2.0 * margin

	var row := {
		"box": (hi.x - lo.x + 2.0 * margin) * (hi.y - lo.y + 2.0 * margin) / _arena_area,
		"core": cw * ch / _arena_area,
		"core_w": cw,
		"core_h": ch,
		"ink": ink / _arena_area,
		"pack": ink / maxf(cw * ch, 1.0),
		"gap": gaps / float(live.size()),
		"window": float(best_win),
	}
	for key in KEYS:
		(acc[key] as Array[float]).append(row[key])
	var n := live.size()
	if not by_count.has(n):
		by_count[n] = _fresh()
	var b: Dictionary = by_count[n]
	for key in KEYS:
		(b[key] as Array[float]).append(row[key])
	return row

func _at(sorted: Array[float], q: float) -> float:
	if sorted.is_empty():
		return 0.0
	return sorted[clampi(int(round(q * float(sorted.size() - 1))), 0, sorted.size() - 1)]


