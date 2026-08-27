extends SceneTree

## Issue 97: how much the automatic kite band costs, counted rather than argued.

const SEEDS := 6
const ROOMS := [&"floor1_room1", &"floor1_cover", &"floor1_hazard", &"floor1_chokepoint", &"floor1_rat_king", &"floor1_ghoul_den"]

func _init() -> void:
	var totals := {}
	var wins := {}
	var fights := {}
	var lash := 0
	var lash_fights := 0
	for room_id in ROOMS:
		var enc := Registry.get_encounter(room_id)
		if enc == null:
			continue
		for party in _parties():
			var key := "%s|%s" % [room_id, ",".join(party)]
			for seed in SEEDS:
				var state := CombatSim.build(_pawns(party, seed), enc, seed, SimDeps.new())
				while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
					var before := {}
					for u in state.units:
						if u.alive:
							before[u.id] = u.position
					CombatSim.step(state)
					_sample_tick(state, totals, before)
				fights[key] = int(fights.get(key, 0)) + 1
				if state.outcome == CombatState.Outcome.PLAYER_WIN:
					wins[key] = int(wins.get(key, 0)) + 1
				if room_id == &"floor1_rat_king":
					lash_fights += 1
					for e in state.events:
						if e.kind == CG.EventKind.ACTION_FIRE and e.action_id == &"rat_king_lash":
							lash += 1

	print("")
	print("== KITE BAND ==")
	for side in ["pawn", "enemy"]:
		var alive := int(totals.get(side + ":alive", 0))
		var shot := int(totals.get(side + ":in_range", 0))
		var ret := int(totals.get(side + ":retreat_in_range", 0))
		print("%s: %d alive ticks, %d with a target inside its own best attack range, %d of those spent MOVING AWAY (%.1f%% of in-range ticks)" % [
			side, alive, shot, ret, 100.0 * float(ret) / float(maxi(1, shot))])
	print("rat_king_lash fires per fight: %.2f over %d fights" % [float(lash) / float(maxi(1, lash_fights)), lash_fights])

	print("")
	print("== WIN RATES ==")
	var keys := wins.keys()
	for key in fights.keys():
		if not wins.has(key):
			wins[key] = 0
	keys = fights.keys()
	keys.sort()
	for key in keys:
		print("%-60s %d/%d" % [key, int(wins[key]), int(fights[key])])
	quit(0)

## What each unit DID this tick, read from positions rather than from a decision.
##
## **Never calls `decide`.** `DefaultBehavior.decide` draws from `state.rng` in
## `_choose_target`, so an observer that calls it perturbs the fight it measures.
func _sample_tick(state: CombatState, totals: Dictionary, before: Dictionary) -> void:
	for unit in state.units:
		if not unit.alive or not before.has(unit.id):
			continue
		var was: Vector2 = before[unit.id]
		var side := "pawn" if unit.pawn != null else "enemy"
		totals[side + ":alive"] = int(totals.get(side + ":alive", 0)) + 1

		var reach := _best_attack_range(unit)
		if reach <= 0.0:
			continue
		var foe := _nearest_foe(state, unit)
		if foe == null or was.distance_to(foe.position) > reach:
			continue
		totals[side + ":in_range"] = int(totals.get(side + ":in_range", 0)) + 1

		if unit.position.distance_to(foe.position) > was.distance_to(foe.position) + 0.01:
			totals[side + ":retreat_in_range"] = int(totals.get(side + ":retreat_in_range", 0)) + 1

func _best_attack_range(unit: CombatUnit) -> float:
	var best := -1.0
	for id in unit.actions:
		var a: ActionDef = Registry.get_action(id)
		if a == null or a.heals or a.power_scale <= 0.0:
			continue
		best = maxf(best, a.range_units)
	return best

func _nearest_foe(state: CombatState, unit: CombatUnit) -> CombatUnit:
	var team := CG.Team.ENEMY if unit.team == CG.Team.PLAYER else CG.Team.PLAYER
	var best: CombatUnit = null
	var best_d := INF
	for u in state.living(team):
		var d := unit.position.distance_to(u.position)
		if d < best_d:
			best_d = d
			best = u
	return best

func _parties() -> Array:
	var ids := ClassLibrary.all_ids()
	var out := []
	for skip in ids.size():
		var party := []
		for i in ids.size():
			if i != skip:
				party.append(String(ids[i]))
		out.append(party)
	return out

func _pawns(party: Array, seed: int) -> Array[PawnData]:
	var out: Array[PawnData] = []
	var i := 0
	for class_id in party:
		out.append(PawnFactory.make_starter_pawn(StringName(class_id), StringName("p%d_%d" % [i, seed]), "P%d" % i))
		i += 1
	return out
