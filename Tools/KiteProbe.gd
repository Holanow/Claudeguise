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
					_sample_tick(state, totals)
					CombatSim.step(state)
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
		var free := int(totals.get(side + ":free", 0))
		var shot := int(totals.get(side + ":in_range", 0))
		var ret := int(totals.get(side + ":retreat_in_range", 0))
		print("%s: %d free ticks, %d with a target inside its own best attack range, %d of those spent RETREATING (%.1f%% of in-range free ticks)" % [
			side, free, shot, ret, 100.0 * float(ret) / float(maxi(1, shot))])
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

## Counts, for every unit the fallback layer owns on a free tick, whether it had
## a shot available and whether it walked away from it instead.
func _sample_tick(state: CombatState, totals: Dictionary) -> void:
	for unit in state.units:
		if not unit.alive or unit.intent != null or unit.is_busy():
			continue
		if unit.has_status(CG.Status.STUN):
			continue
		if unit.pawn != null and PlanInterpreter.decide(state, unit) != null:
			continue
		var side := "pawn" if unit.pawn != null else "enemy"
		totals[side + ":free"] = int(totals.get(side + ":free", 0)) + 1

		var reach := _best_attack_range(unit)
		if reach <= 0.0:
			continue
		var foe := _nearest_foe(state, unit)
		if foe == null or unit.position.distance_to(foe.position) > reach:
			continue
		totals[side + ":in_range"] = int(totals.get(side + ":in_range", 0)) + 1

		var intent = DefaultBehavior.decide(state, unit)
		if intent == null or intent.kind != CG.IntentKind.MOVE_TO:
			continue
		if intent.destination.distance_to(foe.position) > unit.position.distance_to(foe.position):
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
	var ids := Registry.all_class_ids()
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
