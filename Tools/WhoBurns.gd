extends SceneTree

## Who pays for `floor1_hazard`'s fire, and are they walking through it or
## standing in it?
##
##     godot --headless --path . --script res://Tools/WhoBurns.gd
##
## `test_the_burn_pit_changes_the_fight`'s header has said since #163 that *"the
## party routes around fire and the enemy back rank has to cross it, so the
## fire's cost lands on the side that walks into it."* finch's #214 then
## measured that `_usable_actions` filtered neither cooldown nor cost, so a
## player pawn spent **46% of its decisions** picking an action it could not
## pay for and doing nothing at all. A pawn deciding nothing does not move, so
## part of what that header calls "walking into it" may have been standing in
## it, and I have never measured which half is which.
##
## So this counts, per team, per tick, for every unit whose centre is inside a
## burn band: whether that unit moved on that tick, and how much fire damage it
## took. "Walks into it" and "stands in it" are then two numbers rather than a
## story.
##
## Measurement only, not part of the gate.


const SEEDS := 20
## A unit is "moving" on a tick if its centre travelled at least this far. Not
## zero: a unit pushed off an overlap by separation has not chosen to walk.
const MOVED_EPSILON := 0.5


func _class_ids_in_a_stable_order() -> Array[StringName]:
	var names := PackedStringArray()
	for id in Registry.all_class_ids():
		names.append(String(id))
	names.sort()
	var out: Array[StringName] = []
	for n in names:
		out.append(StringName(n))
	return out


func _buildable_parties() -> Array:
	var class_ids := _class_ids_in_a_stable_order()
	var out := []
	for skip in class_ids.size():
		var party: Array[StringName] = []
		for i in class_ids.size():
			if i != skip:
				party.append(class_ids[i])
		out.append(party)
	return out


func _pawns(ids: Array, seed: int) -> Array[PawnData]:
	var out: Array[PawnData] = []
	for i in ids.size():
		out.append(PawnFactory.make_starter_pawn(ids[i], StringName("%s_%d_%d" % [ids[i], seed, i]), String(ids[i])))
	return out


func _in_fire(state: CombatState, p: Vector2) -> bool:
	for f in state.terrain:
		if f.kind == Terrain.Kind.HAZARD and f.damage_per_tick > 0 and f.rect.has_point(p):
			return true
	return false


func _init() -> void:
	var enc := Registry.get_encounter(&"floor1_hazard")
	print("floor1_hazard terrain:")
	for f in enc.terrain:
		print("  kind %d  rect %s  dmg/tick %d" % [f.kind, str(f.rect), f.damage_per_tick])

	print("\nticks spent standing in fire, split by whether the unit moved that tick")
	print("%-52s %-34s %s" % ["party", "PLAYER  moving / still / total", "ENEMY   moving / still / total"])
	var g_pm := 0
	var g_ps := 0
	var g_em := 0
	var g_es := 0
	for ids in _buildable_parties():
		var pm := 0
		var ps := 0
		var em := 0
		var es := 0
		for seed in SEEDS:
			var state := CombatSim.build(_pawns(ids, seed), enc, seed)
			var last := {}
			for u in state.units:
				last[u.id] = u.position
			while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < 3000:
				CombatSim.step(state)
				for u in state.units:
					if not u.alive:
						continue
					var was: Vector2 = last.get(u.id, u.position)
					var moved: bool = was.distance_to(u.position) >= MOVED_EPSILON
					last[u.id] = u.position
					if not _in_fire(state, u.position):
						continue
					if u.team == CG.Team.PLAYER:
						if moved:
							pm += 1
						else:
							ps += 1
					else:
						if moved:
							em += 1
						else:
							es += 1
		g_pm += pm
		g_ps += ps
		g_em += em
		g_es += es
		print("%-52s %6d / %6d / %6d            %6d / %6d / %6d" % [str(ids), pm, ps, pm + ps, em, es, em + es])
	print("%-52s %6d / %6d / %6d            %6d / %6d / %6d" % ["ALL FIVE", g_pm, g_ps, g_pm + g_ps, g_em, g_es, g_em + g_es])
	var p_all := maxi(g_pm + g_ps, 1)
	var e_all := maxi(g_em + g_es, 1)
	print("\nof the party's burning ticks, %d%% are spent standing still" % (100 * g_ps / p_all))
	print("of the enemy's burning ticks, %d%% are spent standing still" % (100 * g_es / e_all))
	print("the party takes %d%% of all burning ticks" % (100 * p_all / maxi(p_all + e_all, 1)))
	quit()
