extends SceneTree

## A one-off: two Sellswords and three Brutes across the Narrows' bridge,
## against every buildable party. Prints who won and what it cost.
const SEEDS := 6

func _initialize() -> void:
	var enc := Encounter.new()
	enc.id = &"probe_bridge"
	enc.display_name = "The Narrows, elite"
	var src := Registry.get_encounter(&"floor1_chokepoint")
	enc.terrain = src.terrain
	enc.party_spawns = src.party_spawns
	enc.enemy_spawns = [
		{"enemy_id": &"sellsword", "position": Vector2(260.0, -90.0)},
		{"enemy_id": &"sellsword", "position": Vector2(260.0, 90.0)},
		{"enemy_id": &"brute", "position": Vector2(150.0, 0.0)},
		{"enemy_id": &"brute", "position": Vector2(360.0, -150.0)},
		{"enemy_id": &"brute", "position": Vector2(360.0, 150.0)},
	]
	var classes := ClassLibrary.all_ids()
	for skip in classes.size():
		var ids: Array = []
		for i in classes.size():
			if i != skip:
				ids.append(classes[i])
		var wins := 0
		var hp_left := 0.0
		for s in SEEDS:
			var party: Array[PawnData] = []
			for cid in ids:
				party.append(PawnFactory.make_preset_pawn(cid, StringName("%s_p" % cid), String(cid)))
			var state := CombatSim.build(party, enc, s)
			var outcome := CombatSim.run(state)
			if outcome == CombatState.Outcome.PLAYER_WIN:
				wins += 1
			var have := 0.0
			var full := 0.0
			for u in state.units:
				if u.team == CG.Team.PLAYER and u.pawn != null:
					full += float(u.hp_max)
					have += float(maxi(0, u.hp))
			hp_left += (have / maxf(full, 1.0)) * 100.0
		print("%-46s  win %d/%d   party hp left %.0f%%" % [", ".join(PackedStringArray(ids)), wins, SEEDS, hp_left / float(SEEDS)])
	quit(0)
