extends SceneTree

## Issue 330: where a pillar has to stand to interrupt a shot these units
## actually take. Reads observed positions after `CombatSim.step` and never
## calls `decide`, per #329.

const SEEDS := 10
const CELL := 60.0

func _init() -> void:
	var enc := Registry.get_encounter(&"floor1_cover")
	var bare := _without_terrain(enc)
	var lanes: Array[PackedFloat32Array] = []
	for party in _parties():
		_collect(party, bare, lanes)
	print("lanes recorded: %d" % lanes.size())
	_distances(lanes)
	_heat(lanes)
	quit(0)

## Every tick in which a unit had a focus it could legally shoot, as
## [ax, ay, bx, by, team].
func _collect(party: Array, enc: Encounter, out: Array[PackedFloat32Array]) -> void:
	for seed in SEEDS:
		var state := CombatSim.build(_pawns(party, seed), enc, seed, SimDeps.new())
		while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
			CombatSim.step(state)
			for u in state.units:
				if not u.alive:
					continue
				var t := state.unit(u.focus_id)
				if t == null or not t.alive:
					continue
				if not _has_a_shot_in_reach(u, t):
					continue
				out.append(PackedFloat32Array([u.position.x, u.position.y, t.position.x, t.position.y,
					0.0 if u.team == CG.Team.PLAYER else 1.0]))

func _distances(lanes: Array[PackedFloat32Array]) -> void:
	for team in 2:
		var d := PackedFloat32Array()
		var sx := 0.0
		for l in lanes:
			if int(l[4]) != team:
				continue
			d.append(Vector2(l[0], l[1]).distance_to(Vector2(l[2], l[3])))
			sx += l[0]
		if d.is_empty():
			continue
		var sorted := Array(d)
		sorted.sort()
		print("%s: %d shootable ticks, median shot distance %.1f, p10 %.1f, p90 %.1f, mean shooter x %.1f" % [
			"party" if team == 0 else "enemy", d.size(), sorted[d.size() / 2],
			sorted[d.size() / 10], sorted[d.size() * 9 / 10], sx / float(d.size())])

## For every candidate cell in the arena, how many lanes a pillar there would
## cut. The answer to "where does a pillar have to be".
func _heat(lanes: Array[PackedFloat32Array]) -> void:
	var cols := int(CG.ARENA_HALF_WIDTH * 2.0 / CELL)
	var rows := int(CG.ARENA_HALF_HEIGHT * 2.0 / CELL)
	var counts := {}
	for r in rows:
		for c in cols:
			var rect := Rect2(-CG.ARENA_HALF_WIDTH + c * CELL, -CG.ARENA_HALF_HEIGHT + r * CELL, CELL, CELL)
			var f := Terrain.make(Terrain.Kind.PILLAR, rect)
			var hit := [0, 0]
			for l in lanes:
				if TerrainGrid.from_features([f]).sight_blocked(Vector2(l[0], l[1]), Vector2(l[2], l[3])):
					hit[int(l[4])] += 1
			counts["%d,%d" % [c, r]] = hit
	for team in 2:
		print("")
		print("== %s lanes cut, per 60x60 cell (x across -480..480, y down -270..270) ==" % [
			"PARTY" if team == 0 else "ENEMY"])
		var header := "      "
		for c in cols:
			header += "%6d" % int(-CG.ARENA_HALF_WIDTH + c * CELL)
		print(header)
		for r in rows:
			var line := "%5d " % int(-CG.ARENA_HALF_HEIGHT + r * CELL)
			for c in cols:
				line += "%6d" % counts["%d,%d" % [c, r]][team]
			print(line)

func _has_a_shot_in_reach(u: CombatUnit, t: CombatUnit) -> bool:
	for id in u.actions:
		var a := ActionLibrary.get_action(id)
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
	for id in ClassLibrary.all_ids():
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
