extends SceneTree

## Issue #197, option B. **Is the bearing of an inward impact mark still true by
## the time the mark fades?**
##
##   godot --headless --path . --script res://Tools/ImpactMarkProbe.gd
##
## OWNED BY sable. Measurement only: it reads the real simulation and prints
## numbers. Nothing here draws, and nothing here is in the shipped path.
##
## WHAT IS BEING MEASURED, AND WHY IT IS THE MEASURE THAT MATTERS
##
## Option B draws a short arc on the side of the target the hit came from. The
## bearing is taken once, at the tick the hit lands, from `e.source_id`. The
## flash node is then parented to the arena at a FIXED position
## (`BattleView._spawn_impact_flash` sets `flash.position = target.position` and
## never updates it) and lives `ImpactFlash.LIFETIME_SECONDS` = 0.35s. At
## `CG.TICKS_PER_SECOND` that is about five ticks of movement.
##
## So the question is not "did anybody move". It is: **from the fixed point the
## mark is drawn at, has the attacker moved far enough around it that the arc is
## now pointing somewhere the attacker is not?** That is one angle, measured at
## the spawn point, between the attacker then and the attacker at the end of the
## mark's life. Everything below reports that angle.
##
## A second column reports how far the TARGET moved, because a target that has
## walked out from under its own impact mark is a separate legibility problem
## that option B does not create and does not fix. It is printed so nobody reads
## the first column as covering it.
##
## The threshold: an arc of ~120 degrees spans 60 degrees either side of its
## bearing. A drift under 30 degrees leaves the attacker comfortably inside the
## arc; over 60 and the arc no longer covers the attacker at all.

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const BattleView := preload("res://Scripts/UI/BattleView.gd")
const UnitViewScript := preload("res://Scripts/UI/UnitView.gd")

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
	for cid in Registry.all_class_ids():
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
	var class_ids := Registry.all_class_ids()
	var totals := []
	var target_moves := []
	var melee_only := []
	var source_moves := []
	for encounter_id in Registry.all_encounter_ids():
		var enc = Registry.get_encounter(encounter_id)
		var drifts := []
		for s in SEEDS:
			var party: Array[PawnData] = []
			for i in mini(4, class_ids.size()):
				var cid = class_ids[i]
				party.append(PawnFactory.make_starter_pawn(cid, StringName("%s_%d" % [cid, i]), String(cid)))
			var one := _run_one(party, enc, s, life_ticks)
			drifts.append_array(one["drift"])
			target_moves.append_array(one["target_move"])
			melee_only.append_array(one["melee_drift"])
			source_moves.append_array(one["source_move"])
		totals.append_array(drifts)
		print("  %-24s hits %4d   drift median %5.1f deg  p90 %5.1f  max %5.1f  over 60deg: %.1f%%" % [
			encounter_id, drifts.size(), _median(drifts), _pct(drifts, 90), _max(drifts),
			100.0 * _fraction_over(drifts, 60.0),
		])
	print("")
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
	var drift := []
	var source_move := []
	var target_move := []
	var melee_drift := []
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
				"melee": src.position.distance_to(tgt.position) <= (src.radius + tgt.radius) * 2.0,
				"due": state.tick + life_ticks,
			})
		var still := []
		for p in pending:
			if state.tick < p["due"]:
				still.append(p)
				continue
			_close(state, p, drift, target_move, melee_drift, source_move)
		pending = still
	# Anything still open when the fight ends is measured against the final
	# frame rather than dropped: dropping them would bias the sample toward
	# hits followed by five quiet ticks, which is the calm case.
	for p in pending:
		_close(state, p, drift, target_move, melee_drift, source_move)
	return {
		"drift": drift, "target_move": target_move,
		"melee_drift": melee_drift, "source_move": source_move,
	}

func _close(state: CombatState, p: Dictionary, drift: Array, target_move: Array, melee_drift: Array, source_move: Array) -> void:
	var src := state.unit(p["src"])
	var tgt := state.unit(p["tgt"])
	if src == null:
		return
	source_move.append(src.position.distance_to(p["src_at"]))
	var anchor: Vector2 = p["anchor"]
	if anchor.distance_squared_to(src.position) < 0.0001:
		return
	var now := anchor.angle_to_point(src.position)
	var d := absf(rad_to_deg(angle_difference(p["bearing"], now)))
	drift.append(d)
	if p["melee"]:
		melee_drift.append(d)
	if tgt != null:
		target_move.append(anchor.distance_to(tgt.position))

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
