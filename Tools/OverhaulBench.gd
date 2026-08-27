extends SceneTree

## The before/after for the data-driven overhaul: actions and enemies as
## resources, rooms as scenes, Registry deleted. Runs unchanged on both trees,
## because the only thing that moved is the content lookup and that is resolved
## at runtime rather than named at parse time.
##
##   godot --headless --path . --script res://Tools/OverhaulBench.gd

const LOOKUPS := 40000
const SEEDS := 12
const ROOM := &"floor1_room1"

static func _content() -> Script:
	if FileAccess.file_exists("res://Scripts/Content/RoomLibrary.gd"):
		return load("res://Scripts/Content/RoomLibrary.gd")
	return load("res://Scripts/Content/Registry.gd")

static func _room(lib: Script, id: StringName):
	return lib.get_room(id) if lib.has_method("get_room") else lib.get_encounter(id)

static func _class_ids(lib: Script) -> Array:
	if FileAccess.file_exists("res://Scripts/Content/ClassLibrary.gd"):
		var cl: Script = load("res://Scripts/Content/ClassLibrary.gd")
		if cl.has_method("all_ids"):
			return cl.all_ids()
	return load("res://Scripts/Content/Registry.gd").all_class_ids()

func _initialize() -> void:
	var lib := _content()

	var t0 := Time.get_ticks_usec()
	var room = _room(lib, ROOM)
	var cold_us := Time.get_ticks_usec() - t0
	if room == null:
		printerr("no room named %s" % ROOM)
		quit(1)
		return

	var t1 := Time.get_ticks_usec()
	for _i in LOOKUPS:
		_room(lib, ROOM)
	var lookup_us := Time.get_ticks_usec() - t1

	var ids := _class_ids(lib)
	var t2 := Time.get_ticks_usec()
	var ticks := 0
	var fights := 0
	for skip in ids.size():
		var party: Array[PawnData] = []
		for i in ids.size():
			if i != skip:
				party.append(PawnFactory.make_starter_pawn(ids[i], StringName("p%d" % i), String(ids[i])))
		for s in SEEDS:
			var state := CombatSim.build(party, _room(lib, ROOM), s)
			CombatSim.run(state)
			ticks += state.tick
			fights += 1
	var fight_us := Time.get_ticks_usec() - t2

	print("classes           %d" % ids.size())
	print("cold content us   %d" % cold_us)
	print("lookups/sec       %d" % int(float(LOOKUPS) / (float(lookup_us) / 1000000.0)))
	print("fights            %d" % fights)
	print("total ticks       %d" % ticks)
	print("fight seconds     %.2f" % (float(fight_us) / 1000000.0))
	print("ticks/sec         %d" % int(float(ticks) / (float(fight_us) / 1000000.0)))
	quit(0)
