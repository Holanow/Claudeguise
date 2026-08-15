extends SceneTree

## What is the tick-57 event that `[geysermancer, priest, siege_master,
## warrior]` loses when the Directional Block lands?
##
##     godot --headless --path . --script res://Tools/PillarFirstDiff.gd
##
## `Tools/PillarDivergence.gd` reports that on `main` four of five parties first
## differ with the pillars in at **exactly tick 57**, and that on #160 that
## divergence is gone for all four. One shared tick across four different
## rosters is one shared cause, not four. This prints the events on both sides
## of the split so the cause can be named rather than guessed at.
##
## Measurement only, not part of the gate.

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const Encounter := preload("res://Scripts/Core/Encounter.gd")

const PARTY: Array[StringName] = [&"geysermancer", &"priest", &"siege_master", &"warrior"]


func _pawns(seed: int) -> Array[PawnData]:
	var out: Array[PawnData] = []
	for i in PARTY.size():
		out.append(PawnFactory.make_starter_pawn(PARTY[i], StringName("%s_%d_%d" % [PARTY[i], seed, i]), String(PARTY[i])))
	return out


func _without_terrain(enc: Encounter) -> Encounter:
	var e := Encounter.new()
	e.id = enc.id
	e.display_name = enc.display_name
	e.enemy_spawns = enc.enemy_spawns
	e.party_spawns = enc.party_spawns
	e.terrain = []
	return e


func _run(enc: Encounter, seed: int) -> CombatState:
	var state := CombatSim.build(_pawns(seed), enc, seed)
	CombatSim.run(state)
	return state


func _name(state: CombatState, id: int) -> String:
	if id < 0 or id >= state.units.size():
		return "-"
	return "%s#%d" % [state.units[id].display_name, id]


func _line(state: CombatState, e) -> String:
	return "t%-5d kind %-2d %-18s -> %-18s amt %-5d dtype %d act %-24s status %d" % [
		e.tick, e.kind, _name(state, e.source_id), _name(state, e.target_id),
		e.amount, e.damage_type, String(e.action_id), e.status,
	]


func _fingerprint(e) -> String:
	return "%d|%d|%d|%d|%d|%d|%s|%d" % [
		e.kind, e.tick, e.source_id, e.target_id, e.amount, e.damage_type, e.action_id, e.status,
	]


func _init() -> void:
	var enc := Registry.get_encounter(&"floor1_cover")
	var bare := _without_terrain(enc)
	for seed in 3:
		var a := _run(enc, seed)
		var b := _run(bare, seed)
		var n := mini(a.events.size(), b.events.size())
		var at := -1
		for i in n:
			if _fingerprint(a.events[i]) != _fingerprint(b.events[i]):
				at = i
				break
		print("\n=== seed %d: %d events with pillars, %d bare; first differing index %d" % [seed, a.events.size(), b.events.size(), at])
		if at < 0:
			continue
		var from := maxi(0, at - 4)
		var to := mini(n, at + 4)
		print("  WITH PILLARS")
		for i in range(from, to):
			print("   %s%s" % [("*" if i == at else " "), _line(a, a.events[i])])
		print("  BARE")
		for i in range(from, to):
			print("   %s%s" % [("*" if i == at else " "), _line(b, b.events[i])])
	quit()
