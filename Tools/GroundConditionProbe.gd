extends SceneTree

## Issue 384: what the new condition buys the player, measured on the room the
## complaint came from.
##
## Reads `state.events` after `run()` returns, so there is no mid-step sampling
## question here: an event is a record of a tick that is already over.

const _SEEDS := 24

func _init() -> void:
	var party := ["warrior", "priest", "geysermancer", "abomination"]
	var stock := _sweep(party, false)
	var gated := _sweep(party, true)
	print("issue 384 -- Floor 1, The Burn Pit, %d seeds" % _SEEDS)
	print("  %-8s  %8s  %10s  %8s" % ["plans", "wins", "ground dmg", "ticks"])
	for row in [["stock", stock], ["gated", gated]]:
		var r: Dictionary = row[1]
		print("  %-8s  %8s  %10d  %8d" % [row[0], "%d/%d" % [r["wins"], _SEEDS], r["ground"], r["ticks"]])
	quit(0)

func _sweep(party: Array, gate: bool) -> Dictionary:
	var wins := 0
	var ground := 0
	var ticks := 0
	for seed_value in _SEEDS:
		var pawns: Array[PawnData] = []
		for i in party.size():
			## `make_preset_pawn`: since #399 a starter pawn has no plan rows, so
			## the gated arm gated nothing and printed the stock arm's numbers
			## back, to the tick (#472).
			var p := PawnFactory.make_preset_pawn(party[i], "%s_%d" % [party[i], i], party[i])
			if gate:
				for plan in p.plans:
					if plan.condition == null:
						plan.condition = PlanBlock.new()
						plan.condition.kind = PlanBlock.Kind.CONDITION
					plan.condition.op = &"self_on_safe_ground"
					plan.condition.args = {}
			pawns.append(p)
		var state := CombatSim.build(pawns, Registry.get_encounter(&"floor1_hazard"), seed_value)
		CombatSim.run(state)
		ticks += state.tick
		if state.outcome == CombatState.Outcome.PLAYER_WIN:
			wins += 1
		for e in state.events:
			if e.kind == CG.EventKind.DAMAGE and e.source_id == -1:
				ground += e.amount
	return {"wins": wins, "ground": ground, "ticks": ticks}
