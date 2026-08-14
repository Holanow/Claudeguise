extends SceneTree

## Do siege engines actually fire, and how fast are they built?
##
##   godot --headless --path . --script res://Tools/EngineProbe.gd
##
## MANAGER-OWNED. Not part of the game and not part of the gate.
##
## The player reports engines never firing and being built too fast, and asks
## for a cap of 2. Measured rather than reasoned about: the last three times
## someone on this project explained a behaviour without a probe, the
## explanation was wrong.
##
## Counts, per fight: how many engines get built, on what tick, how many
## `siege_engine_bolt` events each one produces, and how long each lived.

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")

const SEEDS := 20
const PARTY := ["siege_master", "warrior", "priest", "geysermancer"]

func _init() -> void:
	var total_built := 0
	var total_bolts := 0
	var build_ticks: Array[int] = []
	var per_engine_bolts: Array[int] = []
	var lifespans: Array[int] = []
	var fights := 0
	var _in_range := 0
	var _built_checked := 0
	var _dists: Array[float] = []

	for enc_id in Registry.all_encounter_ids():
		for s in range(SEEDS):
			var state := _run(enc_id, s)
			fights += 1
			# Engines are appended after the initial roster, so any unit whose
			# enemy_id is siege_engine is one we built.
			var engine_ids: Array[int] = []
			for u in state.units:
				if u.enemy_id == &"siege_engine":
					engine_ids.append(u.id)
			total_built += engine_ids.size()

			var bolts := {}
			var born := {}
			var died := {}
			for e in state.events:
				if e.kind == CG.EventKind.ACTION_FIRE and e.action_id == &"build_siege_engine":
					build_ticks.append(e.tick)
				if e.kind == CG.EventKind.ACTION_FIRE and e.action_id == &"siege_engine_bolt":
					bolts[e.source_id] = int(bolts.get(e.source_id, 0)) + 1
					total_bolts += 1
				if e.kind == CG.EventKind.DEATH and engine_ids.has(e.target_id):
					died[e.target_id] = e.tick
			for id in engine_ids:
				var eu = state.unit(id)
				var nearest := 1e9
				for other in state.units:
					if other.team == CG.Team.ENEMY and other.enemy_id != &"siege_engine":
						nearest = minf(nearest, eu.position.distance_to(other.position))
				if nearest < 1e9:
					_built_checked += 1
					_dists.append(nearest)
					if nearest <= 200.0:
						_in_range += 1
				per_engine_bolts.append(int(bolts.get(id, 0)))
				lifespans.append(int(died.get(id, state.tick)))

	print("")
	print("%d fights, %d engines built, %d engine bolts fired total"
		% [fights, total_built, total_bolts])
	print("engines per fight: %.2f" % (float(total_built) / float(fights)))
	if per_engine_bolts.size() > 0:
		var silent := 0
		for b in per_engine_bolts:
			if b == 0:
				silent += 1
		print("engines that never fired once: %d of %d (%.0f%%)"
			% [silent, per_engine_bolts.size(), 100.0 * float(silent) / float(per_engine_bolts.size())])
		print("bolts per engine: %.2f mean" % _mean(per_engine_bolts))
	if build_ticks.size() > 0:
		print("first build at tick %d, mean build tick %.0f (%.1fs at %d tps)"
			% [_min(build_ticks), _mean(build_ticks), _mean(build_ticks) / float(CG.TICKS_PER_SECOND), CG.TICKS_PER_SECOND])
	print("")
	print("-- why: distance from each engine to the nearest live enemy, at build --")
	print("in range (<=200): %d of %d   out of range: %d" % [_in_range, _built_checked, _built_checked - _in_range])
	print("mean nearest-enemy distance at build: %.0f units" % _mean(_dists))
	print("engine bolt: range %.0f, wind-up %d ticks, cooldown %d"
		% [Registry.get_action(&"siege_engine_bolt").range_units,
			Registry.get_action(&"siege_engine_bolt").wind_up_ticks,
			Registry.get_action(&"siege_engine_bolt").cooldown_ticks])
	quit(0)

func _mean(a: Array) -> float:
	var t := 0.0
	for v in a:
		t += float(v)
	return t / float(a.size())

func _min(a: Array) -> int:
	var m: int = a[0]
	for v in a:
		if v < m:
			m = v
	return m

func _run(enc_id: StringName, s: int) -> CombatState:
	var party: Array[PawnData] = []
	for cid in PARTY:
		var c := StringName(cid)
		party.append(PawnFactory.make_starter_pawn(
			c, StringName("%s_%d" % [cid, party.size()]), Registry.get_class_def(c).display_name
		))
	var state := CombatSim.build(party, Registry.get_encounter(enc_id), s)
	CombatSim.run(state)
	return state
