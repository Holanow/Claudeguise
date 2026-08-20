extends SceneTree

## What does a room being a WALL for a party actually look like?
##
##     godot --headless --path . --script res://Tools/WallProbe.gd
##
## `test_no_pickable_room_is_a_wall_for_any_buildable_party` now asserts a floor
## of 5 wins in 20 seeds per room x party cell (PR #220). The floor was set from
## the real distribution, which is right, and its header then claimed "against a
## genuine wall at 5%, it fires essentially always" -- which nothing had
## measured. **A floor nobody has crossed is a detector nobody has fired**, which
## is announcement rule 2.
##
## This is the instrument for the control that answers it. Three columns:
##
##   1. Every room x party win rate at SEEDS seeds, the distribution the floor
##      sits under.
##   2. The same table counting only wins with a pawn still standing. #218: a
##      fight where every pawn dies and a summoned siege engine finishes the
##      room is still reported PLAYER_WIN.
##   3. The CONTROL: the same rooms with the enemy roster doubled. If those do
##      not come out at or near zero, no floor drawn from column 1 means
##      anything.
##
## Measured on `main` at `da348e7`, 40 seeds:
##
##   - column 1: 19 of 20 cells at 36-40/40, one cell (chokepoint x
##     no_geysermancer) at 19/40. A cluster and one coin flip, no tail.
##   - column 2: the worst cell reads 18/40 against 19/40. **One fight in 800
##     was won with every pawn dead**, so #218 does not move this table.
##   - column 3: 18 of 20 cells at 0/40, all five chokepoint cells at 0/40.
##     `floor1_hazard` x `[abomination, geysermancer, siege_master, warrior]` is
##     the outlier at 32/40 -- twice the enemies means twice the burning, and
##     that party holds the far side of the fire. Reported, not acted on.
##
## Measurement only. The gate carries the one-room version of column 3 as
## `test_the_detector_fires_on_a_room_that_really_is_a_wall`.


const SEEDS := 40

const ROOMS: Array[StringName] = [
	&"floor1_room1",
	&"floor1_cover",
	&"floor1_hazard",
	&"floor1_chokepoint",
]


## Same helper as the test file, and for the same reason: `Array[StringName]`
## sorts by interned pointer, not alphabetically, and `party[i]` takes
## `party_spawns[i]`, so an unstable order changes who stands where.
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


## The forced wall. Every enemy spawned twice, the second copy offset so the
## two do not start inside one another. Terrain and party spawns untouched.
func _doubled(enc: Encounter) -> Encounter:
	var e := Encounter.new()
	e.id = enc.id
	e.display_name = enc.display_name
	e.party_spawns = enc.party_spawns
	e.terrain = enc.terrain
	var spawns: Array[Dictionary] = []
	for s in enc.enemy_spawns:
		spawns.append(s)
		spawns.append({"enemy_id": s["enemy_id"], "position": (s["position"] as Vector2) + Vector2(70.0, 0.0)})
	e.enemy_spawns = spawns
	return e


## A pawn, not a summon. `enemy_id` is the discriminator, the same signal
## `_party_hp_percent` in `Tests/test_content_rooms.gd` uses: a summon is built
## by `CombatSim._build_enemy_unit` and carries one, a real pawn never does.
func _pawns_alive(state: CombatState) -> int:
	var n := 0
	for u in state.units:
		if u.team == CG.Team.PLAYER and u.enemy_id == &"" and u.alive:
			n += 1
	return n


func _measure(enc: Encounter, ids: Array) -> Array:
	var wins := 0
	var wins_with_a_pawn := 0
	for seed in SEEDS:
		var state := CombatSim.build(_pawns(ids, seed), enc, seed)
		CombatSim.run(state)
		if state.outcome == CombatState.Outcome.PLAYER_WIN:
			wins += 1
			if _pawns_alive(state) > 0:
				wins_with_a_pawn += 1
	return [wins, wins_with_a_pawn]


func _init() -> void:
	print("seeds per cell: %d" % SEEDS)
	var parties := _buildable_parties()

	print("\n=== REAL ROOMS: wins / wins with a pawn still standing ===")
	var lowest := SEEDS + 1
	var lowest_row := ""
	var lowest_pawn := SEEDS + 1
	var lowest_pawn_row := ""
	for room in ROOMS:
		var enc := Registry.get_encounter(room)
		for ids in parties:
			var r := _measure(enc, ids)
			print("%-20s %-52s %2d/%d  pawn %2d/%d" % [room, str(ids), r[0], SEEDS, r[1], SEEDS])
			if r[0] < lowest:
				lowest = r[0]
				lowest_row = "%s %s" % [room, str(ids)]
			if r[1] < lowest_pawn:
				lowest_pawn = r[1]
				lowest_pawn_row = "%s %s" % [room, str(ids)]
	print("lowest wins:           %d/%d  %s" % [lowest, SEEDS, lowest_row])
	print("lowest pawn-alive wins: %d/%d  %s" % [lowest_pawn, SEEDS, lowest_pawn_row])

	print("\n=== CONTROL, a real wall: same rooms, enemy roster doubled ===")
	var worst_control := -1
	var worst_control_row := ""
	for room in ROOMS:
		var enc := _doubled(Registry.get_encounter(room))
		for ids in parties:
			var r := _measure(enc, ids)
			print("%-20s %-52s %2d/%d  pawn %2d/%d" % [room, str(ids), r[0], SEEDS, r[1], SEEDS])
			if r[0] > worst_control:
				worst_control = r[0]
				worst_control_row = "%s %s" % [room, str(ids)]
	print("highest wins in the wall control: %d/%d  %s" % [worst_control, SEEDS, worst_control_row])
	quit()
