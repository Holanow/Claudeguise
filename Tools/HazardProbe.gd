extends SceneTree

## Issue 338: how much time units actually spend standing in something that
## hurts them, and what changes when they are allowed to step off it.
##
## The answer on all four rooms is NOTHING: the two arms are bit-identical,
## because a unit on a harmful surface is essentially never IDLE.
##
## Reads positions and events only; never calls `decide` (issue 329).

const SEEDS := 20
const ROOMS := [&"floor1_hazard", &"floor1_cover", &"floor1_room1", &"floor1_chokepoint"]

func _init() -> void:
	var stuck := 0
	var stuck_units := {}
	for room_id in ROOMS:
		var enc := Registry.get_encounter(room_id)
		if enc == null:
			continue
		var pawn_burning := 0
		var pawn_alive := 0
		var enemy_burning := 0
		var enemy_alive := 0
		var pawn_hazard_damage := 0
		var wins := 0
		var ticks := 0
		for ids in _parties():
			for seed in SEEDS:
				var state := CombatSim.build(_pawns(ids, seed), enc, seed, SimDeps.new())
				var before := {}
				while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
					for u in state.units:
						before[u.id] = u.position
					CombatSim.step(state)
					for u in state.units:
						if u.alive and not u.is_busy() and u.position == before.get(u.id, Vector2.INF) 								and CombatSim.standing_harms(state, u.position):
							stuck += 1
							var key := String(u.enemy_id) if u.pawn == null else String(u.pawn.pawn_class.id)
							stuck_units[key] = int(stuck_units.get(key, 0)) + 1
					ticks += 1
					for u in state.units:
						if not u.alive:
							continue
						var standing := CombatSim.standing_harms(state, u.position)
						if u.pawn != null:
							pawn_alive += 1
							if standing:
								pawn_burning += 1
								for h in Terrain.hazards_at(state.terrain, u.position):
									pawn_hazard_damage += h.damage_per_tick
						else:
							enemy_alive += 1
							if standing:
								enemy_burning += 1
				if state.outcome == CombatState.Outcome.PLAYER_WIN:
					wins += 1
		print("%-20s pawns %5.2f%% of alive ticks on a harmful surface, enemies %5.2f%%; pawn surface damage %d; wins %d/%d; %d ticks" % [
			room_id,
			100.0 * float(pawn_burning) / float(maxi(1, pawn_alive)),
			100.0 * float(enemy_burning) / float(maxi(1, enemy_alive)),
			pawn_hazard_damage, wins, _parties().size() * SEEDS, ticks])
	print("")
	print("STANDING STILL, NOT BUSY, ON A HARMFUL SURFACE: %d unit-ticks" % stuck)
	print("  by unit: %s" % stuck_units)
	quit(0)

func _parties() -> Array:
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
