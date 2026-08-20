extends SceneTree

## Does the burn pit ever burn anybody, and is that a steadier quantity than
## the difference of two health arms?
##
##     godot --headless --path . --script res://Tools/FireOutput.gd
##
## Every assertion in `test_the_burn_pit_changes_the_fight_for_every_buildable_party`
## is a **difference between the room with its fire and the same room bare**:
## two tick ratios and `largest_health`. That is a controlled A/B and it is the
## right shape for "the fire changes the fight" -- but it means anything that
## moves the bare arm moves the verdict, and **nothing in the test asserts that
## the fire has ever dealt a single point of damage.**
##
## Hazard damage is observable from outside a `step()`: `_tick_hazards` emits
## `DAMAGE` with `source_id == -1`, an empty `action_id`, and `status` left at
## its default `SHIELD`. The three damage-over-time statuses each set `status`
## to BURN, POISON or BLEED, so SHIELD is the discriminator and it cannot
## collide with them. Announcement rule 2: read `state.events`, not a field that
## dies inside the tick.
##
## Printed per team and at rising sample sizes, with a hazard of paint as the
## control, so the answer is a curve and a zero rather than one number.
##
## Measurement only, not part of the gate.


const SAMPLES: Array[int] = [4, 8, 20, 40]


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


## Health taken by terrain, split by whose it was. Returns [party, enemy].
func _fire_damage(state: CombatState) -> Array:
	var mine := 0
	var theirs := 0
	for e in state.events:
		if e.kind != CG.EventKind.DAMAGE or e.source_id != -1 or e.action_id != &"":
			continue
		if e.status != CG.Status.SHIELD:
			continue  # a burn/poison/bleed tick, not the terrain
		var u := state.unit(e.target_id)
		if u == null:
			continue
		if u.team == CG.Team.PLAYER:
			mine += e.amount
		else:
			theirs += e.amount
	return [mine, theirs]


func _init() -> void:
	var enc := Registry.get_encounter(&"floor1_hazard")
	var bare := _without_terrain(enc)
	var parties := _buildable_parties()

	print("floor1_hazard: health taken by the fire, per fight, by sample size")
	print("%-6s %-10s %-10s %s" % ["seeds", "party", "enemy", "both"])
	for seeds in SAMPLES:
		var mine := 0
		var theirs := 0
		var fights := 0
		for ids in parties:
			for seed in seeds:
				var state := CombatSim.build(_pawns(ids, seed), enc, seed)
				CombatSim.run(state)
				var d := _fire_damage(state)
				mine += d[0]
				theirs += d[1]
				fights += 1
		print("n=%-4d %-10.1f %-10.1f %.1f   over %d fights" % [
			seeds, float(mine) / fights, float(theirs) / fights, float(mine + theirs) / fights, fights,
		])

	print("\nper party at n=20, health taken by the fire per fight")
	for ids in parties:
		var mine := 0
		var theirs := 0
		for seed in 20:
			var state := CombatSim.build(_pawns(ids, seed), enc, seed)
			CombatSim.run(state)
			var d := _fire_damage(state)
			mine += d[0]
			theirs += d[1]
		print("%-52s party %5.1f   enemy %5.1f" % [str(ids), float(mine) / 20.0, float(theirs) / 20.0])

	print("\nCONTROL, a hazard of paint: the same roster with the terrain stripped")
	var c_mine := 0
	var c_theirs := 0
	for ids in parties:
		for seed in 20:
			var state := CombatSim.build(_pawns(ids, seed), enc, seed)
			state.terrain = []
			CombatSim.run(state)
			var d := _fire_damage(state)
			c_mine += d[0]
			c_theirs += d[1]
	print("party %d, enemy %d -- both must be zero" % [c_mine, c_theirs])

	print("\nCONTROL 2, the encounter built with no terrain at all")
	c_mine = 0
	c_theirs = 0
	for ids in parties:
		for seed in 20:
			var state := CombatSim.build(_pawns(ids, seed), bare, seed)
			CombatSim.run(state)
			var d := _fire_damage(state)
			c_mine += d[0]
			c_theirs += d[1]
	print("party %d, enemy %d -- both must be zero" % [c_mine, c_theirs])
	quit()
