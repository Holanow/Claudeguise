extends SceneTree

## How big is the colonnade's effect really, once party health stops counting
## summoned Siege Engines, and how much of the 4-seed number is noise?
##
##     godot --headless --path . --script res://Tools/PillarDelta.gd
##
## `test_the_colonnades_pillars_are_not_decoration` asserts largest >= 8 and
## total >= 18 at 4 seeds. With summons counted it reads 12 and 23; with them
## excluded it reads 8 and 19, which puts the first assertion exactly on its own
## floor. Before touching either number I want to know whether 8 is the effect
## or the sample.
##
## Measurement only. Not part of the gate.



func _init() -> void:
	var enc := Registry.get_encounter(&"floor1_cover")
	var bare := _without_terrain(enc)
	print("Colonnade delta, party health EXCLUDING summons.\n")
	print("%8s %10s %8s   per-party deltas" % ["seeds", "largest", "total"])
	for seeds_v in [4, 8, 12, 20, 40]:
		var seeds: int = seeds_v
		var largest := 0
		var total := 0
		var per := PackedStringArray()
		for ids in _buildable_parties():
			var with_hp := 0
			var bare_hp := 0
			for s in range(seeds):
				with_hp += _hp(_run(ids, enc, s))
				bare_hp += _hp(_run(ids, bare, s))
			var delta := (with_hp - bare_hp) / seeds
			per.append("%+d" % delta)
			largest = maxi(largest, absi(delta))
			total += absi(delta)
		print("%8d %10d %8d   %s" % [seeds, largest, total, ", ".join(per)])

	# The other half: does the fight *diverge* at all with the pillars in?
	# Bit-identical ticks and outcomes on every seed is what a colonnade of
	# paint looks like, and it is the case announcement rule 1 was written
	# about. This is a yes/no per seed, so it has no magnitude to be noisy.
	print("\nDivergence: seeds where ticks or outcome differ, pillars vs bare.")
	print("%-24s %10s" % ["party", "differ"])
	for ids in _buildable_parties():
		var differs := 0
		for s in range(10):
			var a := _run(ids, enc, s)
			var b := _run(ids, bare, s)
			if a.tick != b.tick or a.outcome != b.outcome:
				differs += 1
		print("%-24s %8d/10" % [_label(ids), differs])
	quit(0)


func _label(ids: Array) -> String:
	var all := PackedStringArray()
	for id in Registry.all_class_ids():
		all.append(String(id))
	all.sort()
	for n in all:
		if not ids.has(StringName(n)):
			return "no_" + n
	return "?"


func _without_terrain(enc: Encounter) -> Encounter:
	var e := Encounter.new()
	e.id = enc.id
	e.display_name = enc.display_name
	e.enemy_spawns = enc.enemy_spawns
	e.party_spawns = enc.party_spawns
	e.terrain = []
	return e


func _hp(state: CombatState) -> int:
	var hp := 0
	var hp_max := 0
	for u in state.units:
		if u.team != CG.Team.PLAYER or u.enemy_id != &"":
			continue
		hp += maxi(0, u.hp)
		hp_max += u.hp_max
	if hp_max <= 0:
		return 0
	return int(round(100.0 * float(hp) / float(hp_max)))


func _buildable_parties() -> Array:
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


func _run(ids: Array, enc: Encounter, fight_seed: int) -> CombatState:
	var party: Array[PawnData] = []
	for i in ids.size():
		party.append(PawnFactory.make_starter_pawn(
			ids[i], StringName("%s_%d_%d" % [ids[i], fight_seed, i]), String(ids[i])
		))
	var state := CombatSim.build(party, enc, fight_seed)
	CombatSim.run(state)
	return state
