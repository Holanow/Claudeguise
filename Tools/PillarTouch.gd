extends SceneTree

## Does the party that reads 0/20 ever come near a pillar at all?
##
##     godot --headless --path . --script res://Tools/PillarTouch.gd
##
## `Tools/PillarDivergence.gd` says `[geysermancer, priest, siege_master,
## warrior]` on `floor1_cover` is **bit-for-bit identical** with the pillars in
## and with them removed, on #160, across 20 seeds -- same tick count, same
## event stream. On `main` the same party diverges 20/20, first at tick 57.
##
## Bit-identical has exactly two explanations and they need opposite responses:
##
##   1. **The fight moved.** Nothing this party does ever crosses a pillar any
##      more, so the pillars are correctly doing nothing. A finding about the
##      room, and the assertion is measuring a real change.
##   2. **The pillars stopped being consulted.** Something does cross one and
##      the simulation no longer cares. A defect, and announcement rule 1's
##      exact case -- the one that nearly shipped on #94.
##
## So this stops guessing and counts the geometry every tick: how often a unit
## stands inside a pillar's footprint, and how often the straight line between a
## unit and its focus target crosses one. Those numbers cannot both be zero if
## the pillars are being ignored rather than avoided.
##
## Measurement only, not part of the gate.

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const Encounter := preload("res://Scripts/Core/Encounter.gd")
const Terrain := preload("res://Scripts/Core/Terrain.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")

const SEEDS := 20


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


func _init() -> void:
	var enc := Registry.get_encounter(&"floor1_cover")
	print("floor1_cover terrain: %d features" % enc.terrain.size())
	for f in enc.terrain:
		print("  kind %d  rect %s" % [f.kind, str(f.rect)])

	print("\nper party, over %d seeds: ticks in which a unit stands inside a pillar," % SEEDS)
	print("and ticks in which some unit's line to its focus target is blocked by one")
	for ids in _buildable_parties():
		var inside := 0
		var blocked_lines := 0
		var focus_ticks := 0
		var pair_blocked := 0
		var pairs := 0
		var total_ticks := 0
		var closest := 1.0e9
		for seed in SEEDS:
			var state := CombatSim.build(_pawns(ids, seed), enc, seed)
			while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < 3000:
				CombatSim.step(state)
				total_ticks += 1
				for u in state.units:
					if not u.alive:
						continue
					for f in state.terrain:
						var d: bool = f.rect.grow(u.radius).has_point(u.position)
						if d:
							inside += 1
						var c: Vector2 = Vector2(
							clampf(u.position.x, f.rect.position.x, f.rect.end.x),
							clampf(u.position.y, f.rect.position.y, f.rect.end.y))
						closest = minf(closest, u.position.distance_to(c))
					if u.focus_id >= 0 and u.focus_id < state.units.size():
						var t: CombatUnit = state.units[u.focus_id]
						if t != null and t.alive:
							focus_ticks += 1
							if Terrain.line_is_blocked(state.terrain, u.position, t.position):
								blocked_lines += 1
					for o in state.units:
						if o.alive and o.team != u.team:
							pairs += 1
							if Terrain.line_is_blocked(state.terrain, u.position, o.position):
								pair_blocked += 1
		print("%-52s ticks %5d  unit-inside-a-pillar %5d  focus-lines %6d of which blocked %5d  all cross-team pairs %7d of which blocked %6d  nearest approach %.1f" % [
			str(ids), total_ticks, inside, focus_ticks, blocked_lines, pairs, pair_blocked, closest,
		])
	quit()
