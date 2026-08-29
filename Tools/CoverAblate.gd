extends SceneTree

## Issue 818. One variable at a time against `floor1_cover`, on the same rig
## `Tools/CoverAutopsy.gd` uses. Every arm builds a COPY of the room:
## `RoomLibrary.get_room` hands out the cached instance, so an in-place edit
## would follow every later fight in the process, control arms included.
## The control runs first and last and the two must agree; if they do not, an
## arm mutated the cache and the whole table is void.

const SEEDS := 40
const COVER := &"floor1_cover"
const ROOM1 := &"floor1_room1"

func _init() -> void:
	var arms: Array = [
		["control", _shipped],
		["rats->goblins   (count held at 10)", _rats_to_goblins],
		["no rats         (count 8, the issue's arm)", _no_rats],
		["cultists->archers (count held at 10)", _cultists_to_archers],
		["stalker->goblin (count held at 10)", _stalker_to_goblin],
		["flat            (terrain cleared, roster+placement kept)", _flat],
		["room1 placement (cover roster at room1's spawn points)", _room1_placement],
		["room1 roster    (room1's enemies at cover's spawn points)", _room1_roster],
		["CANDIDATE one rat + one goblin        (count held at 10)", _one_rat_goblin],
		["CANDIDATE one rat + one goblin_archer (count held at 10)", _one_rat_archer],
		["CANDIDATE one rat + one cultist       (count held at 10)", _one_rat_cultist],
		["control again   (must match the first control exactly)", _shipped],
	]
	print("CoverAblate -- issue 818, one variable at a time on floor1_cover")
	print("  base room    %s, %d enemies shipped" % [
		COVER, RoomLibrary.get_room(COVER).enemy_spawns.size()])
	print("  seeds        %d per composition, seed = hash([s, room_id]) -- the" % [SEEDS])
	print("               SAME seed expression CoverAutopsy uses, and it keys on")
	print("               the room id, so every arm below shares one seed set.")
	print("  parties      %d compositions of %d from %s, PawnFactory.make_preset_pawn" % [
		PartySpec.compositions().size(), PartySpec.PARTY_SIZE, ClassLibrary.all_ids()])
	print("  RoomScale    %s" % [RoomScale.Mode.keys()[RoomScale.MODE]])
	print("  fights/arm   %d" % [PartySpec.compositions().size() * SEEDS])
	print("  damage       direct hits AND DoT ticks, which CoverAutopsy's")
	print("               by-ability table leaves out entirely.")
	print("\n%-58s %5s %7s %8s %8s %8s" % ["arm", "win", "deaths", "dmg tot", "  direct", "     DoT"])
	for arm in arms:
		var room: RoomData = arm[1].call()
		print("%-58s %s" % [arm[0], _measure(room)])
	quit(0)

func _measure(room: RoomData) -> String:
	var wins := 0
	var deaths := 0.0
	var runs := 0
	var direct := 0
	var dot := 0
	for combo in PartySpec.compositions():
		for s in range(SEEDS):
			var party: Array[PawnData] = []
			for cid in combo:
				var c := StringName(cid)
				party.append(PawnFactory.make_preset_pawn(c, c, ClassLibrary.get_class_def(c).display_name))
			var state := CombatSim.build(party, room, hash([s, COVER]))
			CombatSim.run(state)
			runs += 1
			if state.outcome == CombatState.Outcome.PLAYER_WIN:
				wins += 1
			for j in party.size():
				if not state.unit(j).alive:
					deaths += 1.0
			var l := DamageLedger.build(state)
			for aid in l.by_ability.get(CG.Team.ENEMY, {}):
				direct += int(l.by_ability[CG.Team.ENEMY][aid].total)
			for st in l.by_dot.get(CG.Team.ENEMY, {}):
				dot += int(l.by_dot[CG.Team.ENEMY][st].total)
	return "%4d%% %7.2f %8d %8d %8d" % [
		int(round(100.0 * wins / runs)), deaths / float(runs), direct + dot, direct, dot]

## A copy of `room`, sharing nothing a caller might edit.
static func _copy(room: RoomData) -> RoomData:
	var out := RoomData.new()
	out.id = room.id
	out.display_name = room.display_name
	out.pickable = room.pickable
	out.cells = room.cells.duplicate()
	out.party_spawns = room.party_spawns.duplicate()
	for spawn in room.enemy_spawns:
		out.enemy_spawns.append(spawn.duplicate())
	return out

func _shipped() -> RoomData:
	return _copy(RoomLibrary.get_room(COVER))

func _swap(from: StringName, to: StringName) -> RoomData:
	var out := _shipped()
	for spawn in out.enemy_spawns:
		if spawn.enemy_id == from:
			spawn.enemy_id = to
	return out

func _rats_to_goblins() -> RoomData:
	return _swap(&"rat", &"goblin")

func _cultists_to_archers() -> RoomData:
	return _swap(&"cultist", &"goblin_archer")

func _stalker_to_goblin() -> RoomData:
	return _swap(&"stalker", &"goblin")

func _no_rats() -> RoomData:
	var out := _shipped()
	var kept: Array[Dictionary] = []
	for spawn in out.enemy_spawns:
		if spawn.enemy_id != &"rat":
			kept.append(spawn)
	out.enemy_spawns = kept
	return out

## The second rat only. One bite every seven ticks against a stack that decays
## one every thirty is the engine; the first rat alone cannot outrun the decay
## the way two together do.
func _second_rat_becomes(to: StringName) -> RoomData:
	var out := _shipped()
	var seen := 0
	for spawn in out.enemy_spawns:
		if spawn.enemy_id != &"rat":
			continue
		seen += 1
		if seen == 2:
			spawn.enemy_id = to
	return out

func _one_rat_goblin() -> RoomData:
	return _second_rat_becomes(&"goblin")

func _one_rat_archer() -> RoomData:
	return _second_rat_becomes(&"goblin_archer")

func _one_rat_cultist() -> RoomData:
	return _second_rat_becomes(&"cultist")

func _flat() -> RoomData:
	var out := _shipped()
	out.cells = {}
	return out

## Cover's enemies, in order, moved onto room1's spawn points. Terrain stays
## cover's, so what moves is where the two sides start relative to the pillars.
func _room1_placement() -> RoomData:
	var out := _shipped()
	var other := RoomLibrary.get_room(ROOM1)
	for j in out.enemy_spawns.size():
		out.enemy_spawns[j].position = other.enemy_spawns[j].position
	out.party_spawns = other.party_spawns.duplicate()
	return out

## Room1's enemies on cover's spawn points and cover's terrain: the cross that
## separates the roster from everything else about the room.
func _room1_roster() -> RoomData:
	var out := _shipped()
	var other := RoomLibrary.get_room(ROOM1)
	for j in out.enemy_spawns.size():
		out.enemy_spawns[j].enemy_id = other.enemy_spawns[j].enemy_id
	return out
