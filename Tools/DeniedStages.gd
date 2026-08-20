extends SceneTree

## Issue 97: `_denied_shots` decomposed into its filter stages, on exactly the
## parties and seeds `test_the_colonnade_denies_shots_to_both_sides` uses.

func _init() -> void:
	var enc := Registry.get_encounter(&"floor1_cover")
	var focus_ok := 0
	var blocked := 0
	var denied := 0
	var stale := 0
	var reach_fail := 0
	var alive_ticks := 0
	var gaps_to_focus: Array[float] = []
	var lengths := ""
	for ids in _buildable_parties():
		for seed in 10:
			var state := CombatSim.build(_pawns(ids, seed), enc, seed)
			while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
				CombatSim.step(state)
				for u in state.units:
					if not u.alive:
						continue
					alive_ticks += 1
					var t := state.unit(u.focus_id)
					if t == null or not t.alive:
						continue
					focus_ok += 1
					var foes := state.living(CG.Team.ENEMY if u.team == CG.Team.PLAYER else CG.Team.PLAYER)
					var nearest: CombatUnit = null
					var best := INF
					for f in foes:
						var d := u.position.distance_to(f.position)
						if d < best:
							best = d
							nearest = f
					if nearest != null and nearest.id != t.id:
						stale += 1
					if not Terrain.line_is_blocked(state.terrain, u.position, t.position):
						continue
					blocked += 1
					gaps_to_focus.append(u.position.distance_to(t.position))
					if _has_a_shot_in_reach(u, t):
						denied += 1
					else:
						reach_fail += 1
			if ids == _buildable_parties()[0]:
				lengths += "%d " % state.tick
	gaps_to_focus.sort()
	var med := gaps_to_focus[gaps_to_focus.size() / 2] if gaps_to_focus.size() > 0 else -1.0
	print("STAGES over 5 parties x 10 seeds:")
	print("  alive unit-ticks          %d" % alive_ticks)
	print("  focus valid               %d   (of those, %d had focus on a NON-nearest foe = %.1f%% stale)" % [focus_ok, stale, 100.0 * float(stale) / float(maxi(1, focus_ok))])
	print("  focus valid AND blocked   %d   (median distance to that focus %.1f)" % [blocked, med])
	print("  ... AND a shot in reach   %d   DENIED" % denied)
	print("  ... blocked but OUT of reach %d" % reach_fail)
	print("  party 1 fight lengths: %s" % lengths)
	quit(0)

func _has_a_shot_in_reach(u: CombatUnit, t: CombatUnit) -> bool:
	for id in u.actions:
		var a := Registry.get_action(id)
		if a == null or a.heals or not a.requires_line_of_sight:
			continue
		if u.position.distance_to(t.position) <= a.range_units:
			return true
	return false

func _buildable_parties() -> Array:
	var ids := Registry.all_class_ids()
	ids.sort()
	var out := []
	for skip in ids.size():
		var party: Array[StringName] = []
		for i in ids.size():
			if i != skip:
				party.append(ids[i])
		out.append(party)
	return out

func _pawns(ids: Array, seed: int) -> Array[PawnData]:
	var out: Array[PawnData] = []
	for cid in ids:
		out.append(PawnFactory.make_starter_pawn(cid, StringName("%s_%d" % [cid, out.size()]), String(cid)))
	return out
