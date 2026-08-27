extends SceneTree

## Issue 642: the Siege Engine's end-screen credit, in the exact fight
## `test_a_real_siege_engines_damage_never_reaches_the_card_see_576`
## runs.

func _init() -> void:
	var party: Array[PawnData] = []
	for cid in [&"siege_master", &"warrior"]:
		party.append(PawnFactory.make_preset_pawn(cid, cid, String(cid)))
	var state := CombatSim.build(party, Registry.get_encounter(CG.DEFAULT_ENCOUNTER), 5)
	CombatSim.run(state)
	var engines := {}
	var built_tick := -1
	for e in state.events:
		if e.kind == CG.EventKind.SUMMONED:
			engines[e.target_id] = true
			if built_tick < 0:
				built_tick = e.tick
	var fired := 0
	var dealt := 0
	for e in state.events:
		if e.kind == CG.EventKind.ACTION_FIRE and engines.has(e.source_id):
			fired += 1
		if e.kind == CG.EventKind.DAMAGE and engines.has(e.source_id):
			dealt += e.amount
	for e in state.events:
		if engines.has(e.source_id) or engines.has(e.target_id):
			print("  tick %4d kind %2d src %d tgt %d action %s amount %d"
				% [e.tick, e.kind, e.source_id, e.target_id, e.action_id, e.amount])
	print("ticks %d outcome %d  engines %d  first built tick %d  engine FIRED %d  engine DEALT %d"
		% [state.tick, state.outcome, engines.size(), built_tick, fired, dealt])
	quit(0)
