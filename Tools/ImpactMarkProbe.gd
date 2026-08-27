extends SceneTree

## Is the bearing of an inward impact mark still true by the time it fades?
const UnitViewScript := preload("res://Scripts/UI/UnitView.gd")
const ScreenSweepScript := preload("res://Tools/ScreenSweep.gd")

const SEEDS := 12
const LIFETIME_SECONDS := 0.35

func _init() -> void:
	_print_drawn_sizes()
	_measure_bearings()
	quit(0)

## The sizes the render sheet has to use, taken from the functions the real
## screen uses rather than typed. `ArtPreview` types its own scale and gets it
## wrong; this asks `BattleView.compute_layout`.
func _print_drawn_sizes() -> void:
	var layout := BattleView.compute_layout(Vector2(1280.0, 720.0))
	var scale: float = layout["scale"].x
	print("== DRAWN SIZES at 1280x720 ==")
	print("battle scale %.4f, DISPLAY_SCALE %.2f" % [scale, UnitViewScript.DISPLAY_SCALE])

	var rows := []
	for cid in ClassLibrary.all_ids():
		var pawn := PawnFactory.make_starter_pawn(cid, StringName("probe"), String(cid))
		rows.append([String(cid), _pawn_radius(pawn)])
	for eid in Registry.all_enemy_ids():
		var e := Registry.get_enemy(eid)
		rows.append([String(eid), e.radius])
	rows.sort_custom(func(a, b): return a[1] < b[1])
	for r in rows:
		var world: float = r[1] * UnitViewScript.DISPLAY_SCALE
		print("  %-22s radius %5.1f  ->  drawn %5.1f px across, current impact ring %5.1f..%5.1f px across" % [
			r[0], r[1], world * scale * 2.0,
			world * scale * 2.0 * 0.4, world * scale * 2.0 * 1.8,
		])
	print("")

func _pawn_radius(pawn) -> float:
	# Player pawns take CombatUnit's default radius; ask the built unit rather
	# than guessing, by building a one-pawn fight.
	var party: Array[PawnData] = [pawn]
	var enc = Registry.get_encounter(Registry.all_encounter_ids()[0])
	var state := CombatSim.build(party, enc, 0)
	for u in state.units:
		if u.team == CG.Team.PLAYER:
			return u.radius
	return 12.0

func _measure_bearings() -> void:
	var life_ticks := int(round(LIFETIME_SECONDS * float(CG.TICKS_PER_SECOND)))
	print("== BEARING STALENESS over the mark's life (%d ticks at %d ticks/s) ==" % [
		life_ticks, CG.TICKS_PER_SECOND,
	])
	var class_ids := ClassLibrary.all_ids()
	var totals := []
	var target_moves := []
	var melee_only := []
	var source_moves := []
	var follow_totals := []
	var follow_melee := []
	var target_died := []
	var attacker_died := []
	for encounter_id in Registry.all_encounter_ids():
		var enc = Registry.get_encounter(encounter_id)
		var drifts := []
		var follow_drifts := []
		for s in SEEDS:
			## Every class contributes hits, not the first four of an
			## alphabetical roster -- the Warrior is melee and was never in the
			## sample (#350).
			for party_ids in ScreenSweepScript.sweep_parties(class_ids):
				var party: Array[PawnData] = []
				for i in party_ids.size():
					var cid = party_ids[i]
					party.append(PawnFactory.make_starter_pawn(cid, StringName("%s_%d" % [cid, i]), String(cid)))
				var one := _run_one(party, enc, s, life_ticks)
				drifts.append_array(one["drift"])
				target_moves.append_array(one["target_move"])
				melee_only.append_array(one["melee_drift"])
				source_moves.append_array(one["source_move"])
				follow_drifts.append_array(one["follow_drift"])
				follow_melee.append_array(one["follow_melee"])
				target_died.append_array(one["target_died"])
				attacker_died.append_array(one["attacker_died"])
		totals.append_array(drifts)
		follow_totals.append_array(follow_drifts)
		print("  %-24s hits %4d   FIXED median %5.1f deg p90 %5.1f   FOLLOWING median %5.1f deg p90 %5.1f  over 60deg %.1f%%" % [
			encounter_id, drifts.size(), _median(drifts), _pct(drifts, 90),
			_median(follow_drifts), _pct(follow_drifts, 90),
			100.0 * _fraction_over(follow_drifts, 60.0),
		])
	print("")
	print("  -- FOLLOWING ANCHOR (what ships since #306: the mark rides the")
	print("     target's DRAWN body, so both ends of the bearing move) --")
	print("  ALL HITS      n %d   median %.1f deg  p75 %.1f  p90 %.1f  p99 %.1f  max %.1f" % [
		follow_totals.size(), _median(follow_totals), _pct(follow_totals, 75),
		_pct(follow_totals, 90), _pct(follow_totals, 99), _max(follow_totals),
	])
	print("  over 30 deg: %.1f%%    over 60 deg: %.1f%%    over 90 deg: %.1f%%" % [
		100.0 * _fraction_over(follow_totals, 30.0),
		100.0 * _fraction_over(follow_totals, 60.0),
		100.0 * _fraction_over(follow_totals, 90.0),
	])
	print("  MELEE-RANGE ONLY  n %d   median %.1f deg  p90 %.1f  over 60 deg: %.1f%%" % [
		follow_melee.size(), _median(follow_melee), _pct(follow_melee, 90),
		100.0 * _fraction_over(follow_melee, 60.0),
	])
	print("  no bearing to be right about, excluded above: target died inside the")
	print("  mark's life %.1f%% of hits, attacker died %.1f%%" % [
		100.0 * _fraction_over(target_died, 0.5),
		100.0 * _fraction_over(attacker_died, 0.5),
	])
	print("")
	print("  -- FIXED ANCHOR (the mark that existed when this was first measured;")
	print("     kept so the two numbers can be compared) --")
	print("  ALL HITS      n %d   median %.1f deg  p75 %.1f  p90 %.1f  p99 %.1f  max %.1f" % [
		totals.size(), _median(totals), _pct(totals, 75), _pct(totals, 90), _pct(totals, 99), _max(totals),
	])
	print("  over 30 deg: %.1f%%    over 60 deg: %.1f%%    over 90 deg: %.1f%%" % [
		100.0 * _fraction_over(totals, 30.0),
		100.0 * _fraction_over(totals, 60.0),
		100.0 * _fraction_over(totals, 90.0),
	])
	print("  MELEE-RANGE HITS ONLY (attacker within 2 body radii at impact -- the")
	print("  case where a small angular error is a large visual one)")
	print("    n %d   median %.1f deg  p90 %.1f  over 60 deg: %.1f%%" % [
		melee_only.size(), _median(melee_only), _pct(melee_only, 90),
		100.0 * _fraction_over(melee_only, 60.0),
	])
	# The honesty check on the numbers above. A drift of zero degrees is only
	# believable if the attacker did not move, so measure that directly rather
	# than inferring it: an angle that is zero because nothing moved and an
	# angle that is zero because of a bug in the probe look identical.
	print("  ATTACKER movement over the same window, world units:")
	print("    median %.1f  p75 %.1f  p90 %.1f  max %.1f   (moved at all: %.1f%%)" % [
		_median(source_moves), _pct(source_moves, 75), _pct(source_moves, 90),
		_max(source_moves), 100.0 * _fraction_over(source_moves, 0.01),
	])
	print("  TARGET drift out from under its own mark, world units, same window:")
	print("    median %.1f  p90 %.1f  max %.1f   (moved at all: %.1f%%)" % [
		_median(target_moves), _pct(target_moves, 90), _max(target_moves),
		100.0 * _fraction_over(target_moves, 0.01),
	])

## One fight, stepped a tick at a time, recording every DAMAGE event and
## re-reading the attacker's position `life_ticks` later.
func _run_one(party: Array[PawnData], enc, s: int, life_ticks: int) -> Dictionary:
	var state := CombatSim.build(party, enc, s)
	var seen := 0
	var pending := []
	var out := {
		"drift": [], "target_move": [], "melee_drift": [], "source_move": [],
		"follow_drift": [], "follow_melee": [], "target_died": [], "attacker_died": [],
	}
	while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
		CombatSim.step(state)
		var fresh := state.events_since(seen)
		seen = state.events.size()
		for e in fresh:
			if e.kind != CG.EventKind.DAMAGE or e.source_id < 0 or e.target_id < 0:
				continue
			var src := state.unit(e.source_id)
			var tgt := state.unit(e.target_id)
			if src == null or tgt == null or src.id == tgt.id:
				continue
			if src.position.distance_squared_to(tgt.position) < 0.0001:
				continue
			pending.append({
				"src": e.source_id, "tgt": e.target_id,
				"anchor": tgt.position,
				"src_at": src.position,
				"bearing": tgt.position.angle_to_point(src.position),
				"follow_bearing": UnitViewScript.drawn_position(tgt, state.units).angle_to_point(
					UnitViewScript.drawn_position(src, state.units)),
				"melee": src.position.distance_to(tgt.position) <= (src.radius + tgt.radius) * 2.0,
				"due": state.tick + life_ticks,
			})
		var still := []
		for p in pending:
			if state.tick < p["due"]:
				still.append(p)
				continue
			_close(state, p, out)
		pending = still
	# Anything still open when the fight ends is measured against the final
	# frame rather than dropped: dropping them would bias the sample toward
	# hits followed by five quiet ticks, which is the calm case.
	for p in pending:
		_close(state, p, out)
	return out

func _close(state: CombatState, p: Dictionary, out: Dictionary) -> void:
	var src := state.unit(p["src"])
	var tgt := state.unit(p["tgt"])
	if src == null:
		return
	out["source_move"].append(src.position.distance_to(p["src_at"]))
	_close_following(state, p, src, tgt, out)
	var anchor: Vector2 = p["anchor"]
	if anchor.distance_squared_to(src.position) < 0.0001:
		return
	var now := anchor.angle_to_point(src.position)
	var d := absf(rad_to_deg(angle_difference(p["bearing"], now)))
	out["drift"].append(d)
	if p["melee"]:
		out["melee_drift"].append(d)
	if tgt != null:
		out["target_move"].append(anchor.distance_to(tgt.position))

## Issue 306 made the mark follow its target's drawn body, so the anchor an arc
## would be struck from is `UnitView.drawn_position(target)` now and moves.
func _close_following(state: CombatState, p: Dictionary, src: CombatUnit, tgt: CombatUnit, out: Dictionary) -> void:
	# A death inside the mark's life leaves it with no bearing to be right
	# about: the target's body goes invisible under a ring that keeps drawing,
	# or the attacker it points at is gone. Counted separately, not measured.
	var target_gone := tgt == null or not tgt.alive
	var attacker_gone := not src.alive
	out["target_died"].append(1.0 if target_gone else 0.0)
	out["attacker_died"].append(1.0 if attacker_gone else 0.0)
	if target_gone or attacker_gone:
		return
	var anchor := UnitViewScript.drawn_position(tgt, state.units)
	var toward := UnitViewScript.drawn_position(src, state.units)
	if anchor.distance_squared_to(toward) < 0.0001:
		return
	var d := absf(rad_to_deg(angle_difference(p["follow_bearing"], anchor.angle_to_point(toward))))
	out["follow_drift"].append(d)
	if p["melee"]:
		out["follow_melee"].append(d)

func _median(a: Array) -> float:
	return _pct(a, 50)

func _pct(a: Array, p: int) -> float:
	if a.is_empty():
		return 0.0
	var c := a.duplicate()
	c.sort()
	var i := int(floor(float(p) / 100.0 * float(c.size() - 1)))
	return c[clampi(i, 0, c.size() - 1)]

func _max(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var m: float = a[0]
	for v in a:
		m = maxf(m, v)
	return m

func _fraction_over(a: Array, t: float) -> float:
	if a.is_empty():
		return 0.0
	var n := 0
	for v in a:
		if v > t:
			n += 1
	return float(n) / float(a.size())
