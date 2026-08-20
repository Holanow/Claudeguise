extends SceneTree

## Issue 330: scores candidate colonnade layouts by the exact metric
## `test_the_colonnade_denies_shots_to_both_sides` uses. Reads observed
## positions after `CombatSim.step` and never calls `decide`, per #329.

const SEEDS := 10

func _init() -> void:
	var enc := Registry.get_encounter(&"floor1_cover")
	for pair in [[-300.0, -120.0], [-260.0, -120.0], [-320.0, -180.0]]:
		_score("A %d B %d" % [int(pair[0]), int(pair[1])], _colonnade(enc, pair[0], pair[1]))
	quit(0)

## Two staggered columns of pillars, three then two, at the given x offsets.
func _colonnade(enc: Encounter, ax: float, bx: float) -> Encounter:
	var e := _without_terrain(enc)
	var t: Array = []
	for y in [-250.0, -50.0, 150.0]:
		t.append(Terrain.make(Terrain.Kind.PILLAR, Rect2(ax, y, 100.0, 100.0)))
	for y in [-150.0, 50.0]:
		t.append(Terrain.make(Terrain.Kind.PILLAR, Rect2(bx, y, 100.0, 100.0)))
	e.terrain = t
	return e

func _score(label: String, enc: Encounter) -> void:
	var party := 0
	var enemy := 0
	var stalls := 0
	var ticks := 0
	for ids in _parties():
		for seed in SEEDS:
			var state := CombatSim.build(_pawns(ids, seed), enc, seed, SimDeps.new())
			while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
				CombatSim.step(state)
				for u in state.units:
					if not u.alive:
						continue
					var t := state.unit(u.focus_id)
					if t == null or not t.alive:
						continue
					if not Terrain.line_is_blocked(state.terrain, u.position, t.position):
						continue
					if not _has_a_shot_in_reach(u, t):
						continue
					if u.team == CG.Team.PLAYER:
						party += 1
					else:
						enemy += 1
			ticks += state.tick
			if state.outcome == CombatState.Outcome.UNRESOLVED:
				stalls += 1
	print("%-12s denied party %6d  enemy %6d  stalls %d  mean ticks %d" % [label, party, enemy, stalls, ticks / 50])

func _has_a_shot_in_reach(u: CombatUnit, t: CombatUnit) -> bool:
	for id in u.actions:
		var a := Registry.get_action(id)
		if a == null or a.heals or not a.requires_line_of_sight:
			continue
		if u.position.distance_to(t.position) <= a.range_units:
			return true
	return false

func _without_terrain(enc: Encounter) -> Encounter:
	var e := Encounter.new()
	e.id = enc.id
	e.display_name = enc.display_name
	e.enemy_spawns = enc.enemy_spawns
	e.party_spawns = enc.party_spawns
	return e

func _parties() -> Array:
	var names := PackedStringArray()
	for id in Registry.all_class_ids():
		names.append(String(id))
	names.sort()
	var out := []
	for skip in names.size():
		var party: Array[StringName] = []
		for i in names.size():
			if i != skip:
				party.append(StringName(names[i]))
		out.append(party)
	return out

func _pawns(ids: Array, seed: int) -> Array[PawnData]:
	var out: Array[PawnData] = []
	for i in ids.size():
		out.append(PawnFactory.make_starter_pawn(ids[i], StringName("%s_%d_%d" % [ids[i], seed, i]), String(ids[i])))
	return out
