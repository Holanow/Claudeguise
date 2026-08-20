extends SceneTree

## What should the burn pit's guard assert, now that `largest_health` has gone
## the way of `total`?
##
##     godot --headless --path . --script res://Tools/BurnPitInstrument.gd
##
## `largest_health` is the **maximum of the same five absolute deltas `total`
## was the sum of**, so it inherits the defect #250 measured: at #163 the fire's
## own output fell sixfold and `largest` went **up**, 42 to 46. A number that
## rises when the mechanic loses five sixths of its output is not measuring the
## mechanic, and #250 already recorded that `largest` is a
## magnitude-of-anything detector whose carrier has flipped party and sign
## while the number barely moved.
##
## So this prints the candidates to replace it, all of them **non-differential**
## -- read off the fire's own events rather than off a difference between two
## arms -- beside `largest` itself for the comparison:
##
##   - health the fire dealt per fight, per team. Already asserted at #239 with
##     a floor of 100 on the enemy column.
##   - the fire's **share of all damage** in the room. A floor on this cannot be
##     met by a room that simply got longer, which a raw total can.
##   - **deaths whose killing blow was the fire**, per team. The least
##     deniable form of "not decoration", and the one a watcher can see.
##   - units that took any fire damage at all, per fight, of seven or so.
##
## Copy it into a detached checkout to compare builds. Measurement only, never
## gated.


const SAMPLES: Array[int] = [4, 20, 40]


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


func _is_hazard(e) -> bool:
	return e.kind == CG.EventKind.DAMAGE and e.source_id == -1 and e.action_id == &"" and e.status == CG.Status.SHIELD


## [fire party, fire enemy, all damage, fire kills party, fire kills enemy,
##  units the fire touched]
func _measure(state: CombatState) -> Array:
	var fp := 0
	var fe := 0
	var all := 0
	var touched := {}
	var last_hit := {}
	for e in state.events:
		if e.kind == CG.EventKind.DAMAGE:
			all += e.amount
			if _is_hazard(e):
				last_hit[e.target_id] = true
				touched[e.target_id] = true
				var u := state.unit(e.target_id)
				if u != null and u.team == CG.Team.PLAYER:
					fp += e.amount
				else:
					fe += e.amount
			else:
				last_hit[e.target_id] = false
	var kp := 0
	var ke := 0
	for u in state.units:
		if u.hp > 0 or not last_hit.get(u.id, false):
			continue
		if u.team == CG.Team.PLAYER:
			kp += 1
		else:
			ke += 1
	return [fp, fe, all, kp, ke, touched.size()]


func _init() -> void:
	var enc := Registry.get_encounter(&"floor1_hazard")
	var bare := _without_terrain(enc)
	var parties := _buildable_parties()

	print("floor1_hazard: the differential instrument beside the non-differential candidates")
	for seeds in SAMPLES:
		var largest := 0
		var total := 0
		var row := []
		var fp := 0
		var fe := 0
		var all := 0
		var kp := 0
		var ke := 0
		var touched := 0
		var fights := 0
		for ids in parties:
			var burnt := 0
			var plain := 0
			for seed in seeds:
				var a := CombatSim.build(_pawns(ids, seed), enc, seed)
				CombatSim.run(a)
				var b := CombatSim.build(_pawns(ids, seed), bare, seed)
				CombatSim.run(b)
				burnt += _party_hp_percent(a)
				plain += _party_hp_percent(b)
				var m := _measure(a)
				fp += m[0]
				fe += m[1]
				all += m[2]
				kp += m[3]
				ke += m[4]
				touched += m[5]
				fights += 1
			var delta := (burnt - plain) / seeds
			row.append(delta)
			largest = maxi(largest, absi(delta))
			total += absi(delta)
		print("n=%-3d  largest %2d  total %3d  %-26s | fire party %5.1f  enemy %5.1f  share %4.1f%%  kills %.2f/%.2f  touched %.1f" % [
			seeds, largest, total, str(row),
			float(fp) / fights, float(fe) / fights, 100.0 * float(fp + fe) / maxf(1.0, float(all)),
			float(kp) / fights, float(ke) / fights, float(touched) / fights,
		])

	print("\nper party at n=40, non-differential only")
	print("%-56s %7s %7s %6s %6s %6s" % ["party", "party", "enemy", "share", "kills", "touch"])
	for ids in parties:
		var fp := 0
		var fe := 0
		var all := 0
		var k := 0
		var touched := 0
		for seed in 40:
			var s := CombatSim.build(_pawns(ids, seed), enc, seed)
			CombatSim.run(s)
			var m := _measure(s)
			fp += m[0]
			fe += m[1]
			all += m[2]
			k += m[3] + m[4]
			touched += m[5]
		print("%-56s %7.1f %7.1f %5.1f%% %6.2f %6.1f" % [
			str(ids), float(fp) / 40.0, float(fe) / 40.0,
			100.0 * float(fp + fe) / maxf(1.0, float(all)), float(k) / 40.0, float(touched) / 40.0,
		])

	# The known-good input. A hazard of paint must read zero on every one of
	# them, and a candidate that cannot reach zero is not a detector.
	var cfp := 0
	var cfe := 0
	var ck := 0
	var ct := 0
	for ids in parties:
		for seed in 20:
			var s := CombatSim.build(_pawns(ids, seed), bare, seed)
			CombatSim.run(s)
			var m := _measure(s)
			cfp += m[0]
			cfe += m[1]
			ck += m[3] + m[4]
			ct += m[5]
	print("\nCONTROL, a hazard of paint: fire party %d, enemy %d, kills %d, touched %d -- all must be 0" % [cfp, cfe, ck, ct])
	quit()
