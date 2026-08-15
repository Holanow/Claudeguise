extends SceneTree

## Issue #234. Who does the colonnade act on?
##
##     godot --headless --path . --script res://Tools/ColonnadeReach.gd
##
## `Tools/PillarTouch.gd` counts blocked lines for a whole fight. That total
## cannot answer #234's question, because #234 is about **which side** the
## geometry acts on, and a total sums both sides into one number.
##
## So everything here is split by team, and the two columns that decide the
## issue are the blocked-focus-line rates: if the party's rate is ~0 while the
## enemy's is not, the colonnade is a one-sided room and the fix is geometry.
## If both are non-zero, "the party never enters the colonnade" is true about
## feet and false about shots, and the room is doing its job second-hand.
##
## Also printed: how far east the party's front unit ever gets, against the
## pillar band at x 20..260. Feet, not shots.
##
## Measurement only, not part of the gate.

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const Terrain := preload("res://Scripts/Core/Terrain.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")
const CombatEvent := preload("res://Scripts/Core/CombatEvent.gd")
const Encounter := preload("res://Scripts/Core/Encounter.gd")

const SEEDS := 20
const ROOM := &"floor1_cover"


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


func _init() -> void:
	var enc := Registry.get_encounter(ROOM)
	var west := 1.0e9
	var east := -1.0e9
	for f in enc.terrain:
		west = minf(west, f.rect.position.x)
		east = maxf(east, f.rect.end.x)
	print("%s: %d pillars, band x %.0f .. %.0f" % [ROOM, enc.terrain.size(), west, east])
	print("party spawns: %s" % str(enc.party_spawns))
	print("")
	print("%-46s | %-24s | %-24s | party feet" % ["party", "PARTY focus lines", "ENEMY focus lines"])
	for ids in _buildable_parties():
		var focus := {CG.Team.PLAYER: 0, CG.Team.ENEMY: 0}
		var blocked := {CG.Team.PLAYER: 0, CG.Team.ENEMY: 0}
		var denied := {CG.Team.PLAYER: 0, CG.Team.ENEMY: 0}
		var in_band := 0
		var party_ticks := 0
		var deepest_per_fight: Array[float] = []
		var fights_reaching := 0
		for seed in SEEDS:
			var state := CombatSim.build(_pawns(ids, seed), enc, seed)
			var deepest := -1.0e9
			while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < 3000:
				CombatSim.step(state)
				for u in state.units:
					if not u.alive:
						continue
					if u.team == CG.Team.PLAYER:
						party_ticks += 1
						deepest = maxf(deepest, u.position.x)
						if u.position.x >= west:
							in_band += 1
					if u.focus_id >= 0 and u.focus_id < state.units.size():
						var t: CombatUnit = state.units[u.focus_id]
						if t != null and t.alive:
							focus[u.team] += 1
							if Terrain.line_is_blocked(state.terrain, u.position, t.position):
								blocked[u.team] += 1
								if _has_a_denied_shot(u, t, state):
									denied[u.team] += 1
			deepest_per_fight.append(deepest)
			if deepest >= west:
				fights_reaching += 1
		deepest_per_fight.sort()
		var pf := float(focus[CG.Team.PLAYER])
		var ef := float(focus[CG.Team.ENEMY])
		print("%-46s | %6d blocked %5d (%5.2f%%) | %6d blocked %5d (%5.2f%%) | shots denied: party %5d enemy %5d | median deepest x %7.1f, ticks east of x %.0f: %d of %d (%.2f%%)" % [
			str(ids),
			focus[CG.Team.PLAYER], blocked[CG.Team.PLAYER], 0.0 if pf == 0.0 else 100.0 * blocked[CG.Team.PLAYER] / pf,
			focus[CG.Team.ENEMY], blocked[CG.Team.ENEMY], 0.0 if ef == 0.0 else 100.0 * blocked[CG.Team.ENEMY] / ef,
			denied[CG.Team.PLAYER], denied[CG.Team.ENEMY],
			deepest_per_fight[deepest_per_fight.size() / 2], west, in_band, party_ticks, 0.0 if party_ticks == 0 else 100.0 * in_band / party_ticks,
		])
		print("%-46s |   deepest party x per fight: min %7.1f  median %7.1f  max %7.1f  |  fights reaching the band: %d of %d" % [
			"", deepest_per_fight[0], deepest_per_fight[deepest_per_fight.size() / 2], deepest_per_fight[-1], fights_reaching, SEEDS,
		])

	## A blocked focus line is geometry, not effect. Only an action carrying
	## `requires_line_of_sight` loses anything to a pillar, so the number that
	## settles who the room acts on is damage dealt with the colonnade against
	## damage dealt on the same seeds with the terrain stripped. Negative means
	## the pillars cost that side.
	var bare := _without_terrain(enc)
	print("\ndamage dealt per fight, colonnade vs the same seeds on bare ground:")
	print("%-46s | %-28s | %-28s" % ["party", "PARTY damage dealt", "ENEMY damage dealt"])
	for ids in _buildable_parties():
		var with_d := {CG.Team.PLAYER: 0, CG.Team.ENEMY: 0}
		var bare_d := {CG.Team.PLAYER: 0, CG.Team.ENEMY: 0}
		for seed in SEEDS:
			_tally(_run(ids, enc, seed), with_d)
			_tally(_run(ids, bare, seed), bare_d)
		var pw := float(with_d[CG.Team.PLAYER]) / SEEDS
		var pb := float(bare_d[CG.Team.PLAYER]) / SEEDS
		var ew := float(with_d[CG.Team.ENEMY]) / SEEDS
		var eb := float(bare_d[CG.Team.ENEMY]) / SEEDS
		print("%-46s | %7.1f vs %7.1f bare  %+7.1f | %7.1f vs %7.1f bare  %+7.1f" % [
			str(ids), pw, pb, pw - pb, ew, eb, ew - eb,
		])
	quit()


## A blocked line only costs a unit something if the unit had a shot to lose:
## an action that opted into `requires_line_of_sight`, aimed at an enemy, with
## the target already inside its reach. Out of range the pillar is never
## consulted -- that was the whole of #231's 0-of-40.
func _has_a_denied_shot(u: CombatUnit, t: CombatUnit, state: CombatState) -> bool:
	for id in u.actions:
		var a := Registry.get_action(id)
		if a == null or a.heals or not a.requires_line_of_sight:
			continue
		if u.position.distance_to(t.position) <= a.range_units:
			return true
	return false


func _run(ids: Array, enc: Encounter, seed: int) -> CombatState:
	var state := CombatSim.build(_pawns(ids, seed), enc, seed)
	while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < 3000:
		CombatSim.step(state)
	return state


func _tally(state: CombatState, into: Dictionary) -> void:
	for e in state.events:
		if e.kind != CG.EventKind.DAMAGE or e.source_id < 0:
			continue
		var src: CombatUnit = state.unit(e.source_id)
		if src != null:
			into[src.team] += e.amount


func _without_terrain(enc: Encounter) -> Encounter:
	var e := Encounter.new()
	e.id = enc.id
	e.display_name = enc.display_name
	e.enemy_spawns = enc.enemy_spawns
	e.party_spawns = enc.party_spawns
	e.terrain = []
	return e
