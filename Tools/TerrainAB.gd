extends SceneTree

## Does terrain change a fight? Holds the roster fixed and varies only the
## walls.
##
##   godot --headless --path . --script res://Tools/TerrainAB.gd
##
## MANAGER-OWNED. Not part of the game and not part of the gate.
##
## This exists because I got the answer wrong without it. I compared
## `floor1_room1` (ten enemies, no terrain) against `floor1_cover` (three
## enemies, two pillars), saw the ranged party finish faster and healthier in
## the cover room, and concluded that cover helps whoever out-ranges the room.
## teal's own comment in `floor1_encounters.gd` says the cover room has
## "fewer, weaker enemies than floor1_room1 on purpose ... not to be a harder
## fight." Three enemies die faster than ten. I had attributed to the geometry
## an effect that the roster fully explains, and I wrote it into an issue, a
## merge commit, the board and PLAYING.md before checking.
##
## So: same enemies, same spawns, same party, same seeds, terrain the only
## difference. That is the only comparison that can answer the question, and
## the project did not have a way to run it.


const SEEDS := 20

## The parties worth asking about: the one that ignores the room, the one that
## has to walk into it, and the balanced reference.
const PARTIES := [
	["siege_master", "siege_master", "siege_master", "siege_master"],
	["warrior", "warrior", "warrior", "warrior"],
	["siege_master", "geysermancer", "priest", "warrior"],
]

func _init() -> void:
	var base := Registry.get_encounter(CG.DEFAULT_ENCOUNTER)
	if base == null:
		printerr("no base encounter")
		quit(1)
		return

	# The same two pillars floor1_cover uses, dropped into floor1_room1's
	# roster. Nothing else differs between the two arms.
	var pillars := [
		Terrain.make(Terrain.Kind.PILLAR, Rect2(40.0, -160.0, 50.0, 90.0)),
		Terrain.make(Terrain.Kind.PILLAR, Rect2(40.0, 70.0, 50.0, 90.0)),
	]
	# A wall with one gap, from floor1_chokepoint, on the same roster.
	var chokepoint := [
		Terrain.make(Terrain.Kind.WALL, Rect2(-20.0, -270.0, 40.0, 170.0)),
		Terrain.make(Terrain.Kind.WALL, Rect2(-20.0, 100.0, 40.0, 170.0)),
	]

	print("Terrain A/B: floor1_room1's roster, terrain as the only variable.")
	print("%d seeds per cell.\n" % SEEDS)

	for ids in PARTIES:
		print("party: %s" % ", ".join(PackedStringArray(ids)))
		_arm(base, [], ids, "no terrain     ")
		_arm(base, pillars, ids, "two pillars    ")
		_arm(base, chokepoint, ids, "wall + one gap ")
		print("")
	quit(0)

func _arm(base: Encounter, terrain: Array, ids: Array, label: String) -> void:
	var e := Encounter.new()
	e.id = base.id
	e.display_name = base.display_name
	e.enemy_spawns = base.enemy_spawns
	e.party_spawns = base.party_spawns
	e.terrain = terrain

	var wins := 0
	var draws := 0
	var win_hp: Array[int] = []
	var ticks: Array[int] = []
	for s in range(SEEDS):
		var party: Array[PawnData] = []
		for cid in ids:
			var c := StringName(cid)
			party.append(PawnFactory.make_starter_pawn(
				c, StringName("%s_%d" % [cid, party.size()]), Registry.get_class_def(c).display_name
			))
		var state := CombatSim.build(party, e, s)
		var outcome := CombatSim.run(state)
		ticks.append(state.tick)
		if outcome == CombatState.Outcome.PLAYER_WIN:
			wins += 1
			win_hp.append(_team_hp_percent(state))
		elif outcome == CombatState.Outcome.DRAW:
			draws += 1

	# A draw is reported rather than folded into the losses: a room whose walls
	# make a fight unresolvable is a different result from one that makes it
	# harder, and averaging them together hides exactly that.
	print("  %s win %2d/%d   cost %s   median %d ticks%s" % [
		label, wins, SEEDS,
		"   n/a" if win_hp.is_empty() else "%4d%%" % _median(win_hp),
		_median(ticks),
		"   <- %d DRAWS" % draws if draws > 0 else "",
	])

func _team_hp_percent(state: CombatState) -> int:
	var hp := 0
	var hp_max := 0
	for u in state.units:
		if u.team != CG.Team.PLAYER:
			continue
		hp += maxi(0, u.hp)
		hp_max += u.hp_max
	if hp_max <= 0:
		return 0
	return int(round(100.0 * float(hp) / float(hp_max)))

func _median(values: Array[int]) -> int:
	if values.is_empty():
		return 0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]
