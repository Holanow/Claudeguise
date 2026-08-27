extends SceneTree

## Issue 567, second pass: why the first mark lands at tick 213 when the first
## engine is built at 83. Samples the Siege Master BEFORE each step, which is
## the rule this repo keeps paying for breaking, and never calls `decide`.

func _init() -> void:
	var encounter := RoomLibrary.get_room(CG.DEFAULT_ENCOUNTER)
	var party: Array[PawnData] = [
		PawnFactory.make_preset_pawn(&"siege_master", &"sm", "SM"),
		PawnFactory.make_preset_pawn(&"warrior", &"wa", "WA"),
	]
	var state := CombatSim.build(party, encounter, 0)
	var sm: CombatUnit = null
	for u in state.units:
		if u.pawn != null and u.pawn.pawn_class.id == &"siege_master":
			sm = u
	print("Siege Master: resource %d/%d  kind=%s" % [sm.resource, sm.resource_max, CG.ResourceKind.keys()[sm.resource_kind]])
	print("mark costs 15, build costs 20, mark needs an enemy within 220\n")
	var first_in_range := -1
	var first_afford_mark := -1
	var first_afford_build := -1
	var marked_at := -1
	var prev_res := -1
	while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
		var nearest := 99999.0
		for u in state.units:
			if u.team == CG.Team.ENEMY and u.alive:
				nearest = minf(nearest, sm.position.distance_to(u.position))
		if first_in_range < 0 and nearest <= 220.0:
			first_in_range = state.tick
		if first_afford_mark < 0 and sm.resource >= 15:
			first_afford_mark = state.tick
		if first_afford_build < 0 and sm.resource >= 25:
			first_afford_build = state.tick
		if state.tick % 20 == 0 or (prev_res >= 0 and absi(sm.resource - prev_res) >= 10):
			print("  t%-4d res=%-3d nearest_enemy=%.0f  busy=%s current=%s" % [
				state.tick, sm.resource, nearest, str(sm.is_busy()), String(sm.current_action)])
		prev_res = sm.resource
		CombatSim.step(state)
		if marked_at < 0:
			for e in state.events:
				if e.kind == CG.EventKind.STATUS_APPLIED and e.status == CG.Status.MARKED:
					marked_at = e.tick
					break
	print("")
	print("first tick an enemy was within mark range (220): %d" % first_in_range)
	print("first tick the Siege Master could afford a mark (15): %d" % first_afford_mark)
	print("first tick it could afford a build (25): %d" % first_afford_build)
	print("first MARKED applied: %d" % marked_at)
	print("fight ended: %d" % state.tick)
	quit(0)
