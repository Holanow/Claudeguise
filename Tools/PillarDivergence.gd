extends SceneTree

## Do the colonnade's pillars change the fight, for whom, and how do you tell
## "they do nothing for this party" from "this party's fights got shorter"?
##
##     godot --headless --path . --script res://Tools/PillarDivergence.gd
##
## `test_the_colonnades_pillars_are_not_decoration` asserts that every buildable
## party diverges -- ticks or outcome differing between the room with its
## pillars and the same room bare -- in at least 5 fights of 10. On #160 one
## party reads **0 of 10** while the other four read 8 to 10.
##
## A hard zero is not the shape noise makes, so this asks what is behind it
## rather than what number to put in the test:
##
##   1. divergence per party at rising sample sizes, so a zero can be told from
##      a small number,
##   2. **how far into the fight the two arms stay identical**, which separates
##      "the pillars never matter to this party" from "they matter after the
##      fight is already over",
##   3. fight length in both arms, because both open branches make fights
##      shorter and a shorter fight has less room to diverge in,
##   4. a colonnade of paint as the control, which must read zero everywhere.
##
## Measurement only, not part of the gate.


const SAMPLES: Array[int] = [10, 20, 40]


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


func _without_terrain(enc: Encounter) -> Encounter:
	var e := Encounter.new()
	e.id = enc.id
	e.display_name = enc.display_name
	e.enemy_spawns = enc.enemy_spawns
	e.party_spawns = enc.party_spawns
	e.terrain = []
	return e


func _run(ids: Array, enc: Encounter, seed: int) -> CombatState:
	var state := CombatSim.build(_pawns(ids, seed), enc, seed)
	CombatSim.run(state)
	return state


## The first tick whose event list differs between the two arms, or -1 if the
## whole fight is bit-identical.
##
## `state.events` rather than `tick` or `outcome`: the assertion under
## examination compares only the two end-of-fight summaries, so a fight where
## the pillars change who shoots whom and the last tick still lands on the same
## number reads as "no effect". This is the finer instrument for the same
## question, and announcement rule 2's advice about what is observable from
## outside a `step()`.
func _fingerprint(e) -> String:
	return "%d|%d|%d|%d|%d|%d|%s|%d" % [
		e.kind, e.tick, e.source_id, e.target_id, e.amount, e.damage_type, e.action_id, e.status,
	]


func _first_differing_tick(ids: Array, enc: Encounter, bare: Encounter, seed: int) -> int:
	var a := _run(ids, enc, seed)
	var b := _run(ids, bare, seed)
	var n := mini(a.events.size(), b.events.size())
	for i in n:
		if _fingerprint(a.events[i]) != _fingerprint(b.events[i]):
			return a.events[i].tick
	if a.events.size() != b.events.size():
		if n > 0:
			return a.events[n - 1].tick
		return 0
	return -1


func _init() -> void:
	var enc := Registry.get_encounter(&"floor1_cover")
	var bare := _without_terrain(enc)
	var parties := _buildable_parties()

	print("floor1_cover: fights whose tick or outcome differs with the pillars in")
	for seeds in SAMPLES:
		var row := []
		for ids in parties:
			var differs := 0
			for seed in seeds:
				var a := _run(ids, enc, seed)
				var b := _run(ids, bare, seed)
				if a.tick != b.tick or a.outcome != b.outcome:
					differs += 1
			row.append("%d/%d" % [differs, seeds])
		print("n=%-4d %s" % [seeds, str(row)])

	print("\nfloor1_cover: fights whose EVENT STREAM differs at all, and where it first differs")
	for ids in parties:
		var differs := 0
		var first_sum := 0
		var earliest := 1 << 30
		var len_with := 0
		var len_bare := 0
		for seed in 20:
			var at := _first_differing_tick(ids, enc, bare, seed)
			if at >= 0:
				differs += 1
				first_sum += at
				earliest = mini(earliest, at)
			len_with += _run(ids, enc, seed).tick
			len_bare += _run(ids, bare, seed).tick
		var mean_first := 0
		if differs > 0:
			mean_first = first_sum / differs
		print("%-52s events differ %2d/20, first at tick %5d (earliest %5d), ticks %4d with / %4d bare" % [
			str(ids), differs, mean_first, (earliest if differs > 0 else -1), len_with / 20, len_bare / 20,
		])

	print("\nCONTROL, a colonnade of paint: the bare room measured against itself")
	for ids in parties:
		var differs := 0
		for seed in 20:
			if _first_differing_tick(ids, bare, bare, seed) >= 0:
				differs += 1
		print("%-52s events differ %2d/20" % [str(ids), differs])
	quit()
