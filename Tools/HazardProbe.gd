extends SceneTree

## Issue 357: how much time units spend standing still on a surface that hurts
## them, split by whether they were mid-action when they did it.
##
## `is_busy()` here is sampled after `step()` returns, so it cannot tell a
## blocked move from an action that finished inside the tick; the intent-level
## breakdown is in issue 357.
##
## Reads positions and events only; never calls `decide` (issue 329).

const SEEDS := 20
const ROOMS := [&"floor1_hazard", &"floor1_cover", &"floor1_room1", &"floor1_chokepoint"]

func _init() -> void:
	var still_idle := 0
	var still_busy := 0
	var still_units := {}
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
						if not u.alive or u.position != before.get(u.id, Vector2.INF):
							continue
						if not CombatSim.standing_harms(state, u.position):
							continue
						if u.is_busy():
							still_busy += 1
						else:
							still_idle += 1
						var key := String(u.enemy_id) if u.pawn == null else String(u.pawn.pawn_class.id)
						still_units[key] = int(still_units.get(key, 0)) + 1
					ticks += 1
					for u in state.units:
						if not u.alive:
							continue
						var standing := CombatSim.standing_harms(state, u.position)
						if u.pawn != null:
							pawn_alive += 1
							if standing:
								pawn_burning += 1
								for h in state.grid.hazards_at(u.position):
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
	print("STANDING STILL ON A HARMFUL SURFACE: %d unit-ticks busy, %d not busy" % [still_busy, still_idle])
	print("  by unit: %s" % still_units)
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
