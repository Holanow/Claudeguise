extends SceneTree

## Two questions the 20-seed sweep could not settle.
##
##     godot --headless --path . --script res://Tools/ChokeCell.gd
##
## 1. `floor1_chokepoint` x `no_geysermancer` is the one cell that moves, and it
##    sits on the 50% line my own `wins >= 4 of 8` assertion is drawn at. 20
##    seeds cannot separate 10/20 from 7/20: the standard deviation of a fair
##    coin over 20 is 2.2, so a 3-win gap is about 1.3 of them. This runs 100.
##
## 2. Does the Siege Engine inflate the burn-pit health numbers I merged in
##    #212? The assertion is on a *difference* of two health figures, so the
##    inflation may cancel. "May" is not a measurement.
##
## Measurement only. Not part of the gate.

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const Encounter := preload("res://Scripts/Core/Encounter.gd")

const SEEDS := 100


func _init() -> void:
	print("ChokeCell. %d seeds.\n" % SEEDS)

	print("== 1. floor1_chokepoint, every party, %d seeds ==" % SEEDS)
	var enc := Registry.get_encounter(&"floor1_chokepoint")
	for ids in _buildable_parties():
		var wins := 0
		for s in range(SEEDS):
			if _run(ids, enc, s).outcome == CombatState.Outcome.PLAYER_WIN:
				wins += 1
		print("  %-24s %3d/%d   %3d%%" % [_label(ids), wins, SEEDS, int(round(100.0 * float(wins) / float(SEEDS)))])

	print("\n== 2. The burn pit's health numbers, with and without summons ==")
	print("#212 asserts largest >= 20 and total >= 55 on the 'all' column.")
	var hazard := Registry.get_encounter(&"floor1_hazard")
	var bare := _without_terrain(hazard)
	var seeds := 4
	var largest_all := 0
	var total_all := 0
	var largest_pawns := 0
	var total_pawns := 0
	print("  %-24s %10s %10s" % ["party", "delta all", "delta pawns"])
	for ids in _buildable_parties():
		var burnt_all := 0
		var bare_all := 0
		var burnt_pawns := 0
		var bare_pawns := 0
		for s in range(seeds):
			var a := _run(ids, hazard, s)
			var b := _run(ids, bare, s)
			burnt_all += _hp_percent(a, false)
			bare_all += _hp_percent(b, false)
			burnt_pawns += _hp_percent(a, true)
			bare_pawns += _hp_percent(b, true)
		var d_all := (burnt_all - bare_all) / seeds
		var d_pawns := (burnt_pawns - bare_pawns) / seeds
		largest_all = maxi(largest_all, absi(d_all))
		total_all += absi(d_all)
		largest_pawns = maxi(largest_pawns, absi(d_pawns))
		total_pawns += absi(d_pawns)
		print("  %-24s %+10d %+10d" % [_label(ids), d_all, d_pawns])
	print("  largest  all %d   pawns %d" % [largest_all, largest_pawns])
	print("  total    all %d   pawns %d" % [total_all, total_pawns])
	quit(0)


func _without_terrain(enc: Encounter) -> Encounter:
	var e := Encounter.new()
	e.id = enc.id
	e.display_name = enc.display_name
	e.enemy_spawns = enc.enemy_spawns
	e.party_spawns = enc.party_spawns
	e.terrain = []
	return e


func _hp_percent(state: CombatState, pawns_only: bool) -> int:
	var hp := 0
	var hp_max := 0
	for u in state.units:
		if u.team != CG.Team.PLAYER:
			continue
		if pawns_only and u.enemy_id != &"":
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


func _label(ids: Array) -> String:
	var all := PackedStringArray()
	for id in Registry.all_class_ids():
		all.append(String(id))
	all.sort()
	for n in all:
		if not ids.has(StringName(n)):
			return "no_" + n
	return "?"


func _run(ids: Array, enc: Encounter, fight_seed: int) -> CombatState:
	var party: Array[PawnData] = []
	for i in ids.size():
		party.append(PawnFactory.make_starter_pawn(
			ids[i], StringName("%s_%d_%d" % [ids[i], fight_seed, i]), String(ids[i])
		))
	var state := CombatSim.build(party, enc, fight_seed)
	CombatSim.run(state)
	return state
