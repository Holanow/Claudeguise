extends SceneTree

## Issue 792. FloorRuns.gd reports depth and clear count only; this reports
## what a cleared arm B run's party looks like at the end, and what the
## deepest losing runs look like when there are no clears -- hp fraction and
## alive/dead per pawn, per #730's "winning narrowly" target. Planned pawns
## only, same 40 seeds FloorRuns.gd uses.

const SEEDS := 40

func _init() -> void:
	var comps := PartySpec.compositions()
	if comps.is_empty():
		printerr("no compositions to run")
		quit(1)
		return
	print("Cleared-run final state, issue 792/808, %d seeds, arm B (planned)." % SEEDS)
	print("%s\n" % ReviveArgs.apply())
	for ids in comps:
		print("PARTY OF %d: %s" % [ids.size(), PartySpec.label(ids)])
		_composition(ids)
		print("")
	quit(0)

func _composition(ids: Array) -> void:
	for s in range(SEEDS):
		var room_ids := FloorWalk.default_order(FloorGenerator.generate(s))
		var party := PartySpec.make(ids, true)
		var run := FloorRun.new()
		var wiped := false
		var last_state: CombatState = null
		var depth := 0
		for i in room_ids.size():
			var room_id: StringName = room_ids[i]
			var state := CombatSim.build(party, RoomLibrary.get_room(room_id), hash([s, room_id, i]))
			FloorRun.carry_into(run, state, party, i)
			CombatSim.run(state)
			last_state = state
			for j in party.size():
				var unit := state.unit(j)
				run.record_result(party[j].id, unit.hp, unit.resource, unit.alive)
			if state.outcome != CombatState.Outcome.PLAYER_WIN:
				wiped = true
				depth = i + 1
				break
		if not wiped:
			depth = room_ids.size()
		if wiped and depth < room_ids.size() - 1:
			continue
		print("  seed %d %s (depth %d/%d):" % [
			s, "CLEARED" if not wiped else "died", depth, room_ids.size()])
		for j in party.size():
			var unit := last_state.unit(j)
			var pct := 0
			if unit.hp_max > 0:
				pct = int(round(100.0 * unit.hp / unit.hp_max))
			print("    %-14s %s  hp %d/%d (%d%%)" % [
				String(party[j].id), "alive" if unit.alive else "DEAD",
				unit.hp, unit.hp_max, pct])
