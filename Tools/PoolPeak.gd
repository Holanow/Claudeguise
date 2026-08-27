extends SceneTree

## Issue 496. Peak terrain feature count during a fight, sampled every tick
## before `step()` returns is impossible from outside, so it is sampled between
## steps, which is the bound the renderer and the terrain walks actually see.

const SEEDS := 20

func _init() -> void:
	_sweep(false)
	_sweep(true)
	quit(0)

func _sweep(preset: bool) -> void:
	print("=== %s pawns ===" % ["preset" if preset else "starter"])
	for encounter_id in RoomLibrary.all_ids():
		var encounter := RoomLibrary.get_room(encounter_id)
		var authored := encounter.cells.size()
		var peak := 0
		var casts := 0
		var removed := 0
		for s in SEEDS:
			var party: Array[PawnData] = []
			for i in 4:
				var p := PawnFactory.make_starter_pawn(&"geysermancer", StringName("g%d" % i), "G%d" % i)
				if preset:
					p.plans = PresetPlans.for_class(&"geysermancer")
				party.append(p)
			var state := CombatSim.build(party, encounter, s)
			while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
				CombatSim.step(state)
				peak = maxi(peak, state.grid.count())
			for e in state.events:
				if e.kind == CG.EventKind.TERRAIN_ADDED:
					casts += 1
				elif e.kind == CG.EventKind.TERRAIN_REMOVED:
					removed += 1
		print("%s|authored=%d|peak=%d|added=%d|removed=%d" % [encounter_id, authored, peak, casts, removed])
