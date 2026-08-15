extends SceneTree

## Is the burn pit's health effect a quantity, or is it noise the gate can
## afford to sample?
##
##     godot --headless --path . --script res://Tools/BurnPitSize.gd
##
## `test_the_burn_pit_changes_the_fight_for_every_buildable_party` asserts two
## aggregates over **4 seeds**: the largest single party's health delta between
## the room with its fire and the same room bare, floor 20, and the total of the
## five, floor 55. On finch's #214 the total reads 52.
##
## Four seeds is the same order of sample that made `4 of 8` a coin-flip
## detector, and the colonnade's health aggregate turned out to be noise at
## every sample the gate can afford (`Tools/PillarDelta.gd`). So the question
## is not "is 52 below 55", it is **does this quantity converge, and to what**.
##
## Same measurement as the test, at rising sample sizes, so the answer is a
## curve rather than one number. Measurement only, not part of the gate.

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const Encounter := preload("res://Scripts/Core/Encounter.gd")

const SAMPLES: Array[int] = [4, 8, 12, 20, 40, 80]


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


## Pawns only. A summon carries an `enemy_id` and a pawn never does.
func _party_hp_percent(state: CombatState) -> int:
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


func _run(ids: Array, enc: Encounter, seed: int) -> CombatState:
	var state := CombatSim.build(_pawns(ids, seed), enc, seed)
	CombatSim.run(state)
	return state


func _init() -> void:
	var enc := Registry.get_encounter(&"floor1_hazard")
	var bare := _without_terrain(enc)
	var parties := _buildable_parties()

	print("floor1_hazard: health delta per party (fire minus bare), by sample size")
	print("%-6s %-58s %s" % ["seeds", "party", "delta"])
	for seeds in SAMPLES:
		var largest := 0
		var total := 0
		var row := []
		for ids in parties:
			var burnt := 0
			var plain := 0
			for seed in seeds:
				burnt += _party_hp_percent(_run(ids, enc, seed))
				plain += _party_hp_percent(_run(ids, bare, seed))
			var delta := (burnt - plain) / seeds
			row.append(delta)
			largest = maxi(largest, absi(delta))
			total += absi(delta)
		print("n=%-4d %-58s largest %2d  total %3d" % [seeds, str(row), largest, total])
	quit()
