extends SceneTree

## Is `floor1_chokepoint` a wall for `no_geysermancer`, and do my own room tests
## count summoned Siege Engines as party?
##
##     godot --headless --path . --script res://Tools/ChokeProbe.gd
##
## Two questions because finch's Warden finding says they may be the same
## question. `_party_hp_percent` and `_check_outcome` both walk `state.units`
## filtering on `team == PLAYER`, and `CombatSim._spawn_summon` gives a summon
## `caster.team` -- so a Siege Engine is party by both. Four of the five
## buildable parties carry a Siege Master.
##
## Measurement only. Not part of the gate.


const SEEDS := 20

const PICKABLE := [&"floor1_room1", &"floor1_cover", &"floor1_hazard", &"floor1_chokepoint"]


func _init() -> void:
	var parties := _buildable_parties()
	print("ChokeProbe. %d seeds per cell.\n" % SEEDS)

	print("== 1. Winnability, every pickable room, %d seeds ==" % SEEDS)
	print("A 'hollow' win is one the party finished with all four PAWNS dead and")
	print("only a Siege Engine alive. `_check_outcome` counts a summon as party.")
	print("%-20s %-24s %8s %9s %9s %9s" % ["room", "party", "wins", "hollow", "pawns<4", "draws"])
	for id in PICKABLE:
		var enc := Registry.get_encounter(id)
		for ids in parties:
			var wins := 0
			var hollow := 0
			var wiped := 0
			var draws := 0
			for s in range(SEEDS):
				var state := _run(ids, enc, s)
				var pawns_alive := _alive(state, true)
				if state.outcome == CombatState.Outcome.PLAYER_WIN:
					wins += 1
					if pawns_alive == 0:
						hollow += 1
				elif state.outcome == CombatState.Outcome.DRAW:
					draws += 1
				if pawns_alive < 4:
					wiped += 1
			print("%-20s %-24s %6d/%d %9d %9d %9d" % [String(id), _label(ids), wins, SEEDS, hollow, wiped, draws])
		print("")

	print("== 2. Does a Siege Engine inflate `_party_hp_percent`? ==")
	print("Same fights, health computed both ways. 'pawns' excludes summons.")
	print("%-20s %-24s %8s %8s %7s" % ["room", "party", "all", "pawns", "delta"])
	for id in PICKABLE:
		var enc := Registry.get_encounter(id)
		for ids in parties:
			var all_hp := 0
			var pawn_hp := 0
			for s in range(SEEDS):
				var state := _run(ids, enc, s)
				all_hp += _hp_percent(state, false)
				pawn_hp += _hp_percent(state, true)
			var a := all_hp / SEEDS
			var p := pawn_hp / SEEDS
			print("%-20s %-24s %7d%% %7d%% %+6d" % [String(id), _label(ids), a, p, a - p])
		print("")
	quit(0)


## Living units on the player's side. `pawns_only` drops anything with an
## `enemy_id`, which is exactly what a summon carries and a real pawn does not.
func _alive(state: CombatState, pawns_only: bool) -> int:
	var n := 0
	for u in state.units:
		if u.team != CG.Team.PLAYER or not u.alive:
			continue
		if pawns_only and u.enemy_id != &"":
			continue
		n += 1
	return n


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
