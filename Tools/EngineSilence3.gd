extends SceneTree

## Issue 567, third pass: given a fight long enough, does the engine EVER fire?
## If it does, the kit is too slow for the fights that exist -- a finding.
## If it never does, there is a bug in the marked-only path.
##
## The party is made tanky here so the fight does not end; nothing in content is
## touched. Drives `step()` itself, so the cap is the tool's.

const LONG_CAP := 6000

func _init() -> void:
	var encounter := Registry.get_encounter(CG.DEFAULT_ENCOUNTER)
	var party: Array[PawnData] = []
	for spec in [[&"siege_master", &"sm"], [&"warrior", &"wa"]]:
		var p := PawnFactory.make_preset_pawn(spec[0], spec[1], String(spec[0]))
		p.attribute_bonus[CG.Attribute.CON] = 400
		party.append(p)
	var state := CombatSim.build(party, encounter, 0)
	while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < LONG_CAP:
		CombatSim.step(state)
	var engines := {}
	for u in state.units:
		if u.pawn == null and u.team == CG.Team.PLAYER:
			engines[u.id] = u
	var marks := 0
	for e in state.events:
		if e.kind == CG.EventKind.STATUS_APPLIED and e.status == CG.Status.MARKED:
			marks += 1
	print("fight ran %d ticks, outcome %s, marks applied %d, engines %d" % [
		state.tick, str(state.outcome), marks, engines.size()])
	for id in engines:
		var counts := {}
		var dmg := 0
		for e in state.events:
			if e.source_id != id:
				continue
			counts[e.kind] = int(counts.get(e.kind, 0)) + 1
			if e.kind == CG.EventKind.DAMAGE:
				dmg += e.amount
		var named := {}
		for k in counts:
			named[CG.EventKind.keys()[k]] = counts[k]
		print("  engine %d: alive=%s hp=%d  events=%s  damage dealt=%d" % [
			id, str(engines[id].alive), engines[id].hp, str(named), dmg])
	quit(0)
