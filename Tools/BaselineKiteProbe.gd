extends SceneTree

## The evidence for issue 543's kiting finding: does the planless ranged pawn
## ever attack, or does it stop once the goblin is inside the kite band?
## Reads events after the fight; it never calls decide.

func _init() -> void:
	for class_id in [&"priest", &"geysermancer", &"siege_master", &"warrior"]:
		var pawn := PawnFactory.make_starter_pawn(class_id, class_id, String(class_id))
		pawn.armor = null
		var party: Array[PawnData] = [pawn]
		var e := Encounter.new()
		e.id = &"probe"
		e.enemy_spawns = [
			{"enemy_id": &"goblin", "position": Vector2(150.0, -50.0)},
			{"enemy_id": &"goblin", "position": Vector2(150.0, 50.0)},
		]
		e.party_spawns = [Vector2(-350.0, 0.0)]
		var state := CombatSim.build(party, e, 0)
		var pawn_unit: CombatUnit = null
		for u in state.units:
			if u.pawn != null:
				pawn_unit = u
		var speed := pawn_unit.move_speed
		CombatSim.run(state)
		var used := 0
		var last_tick := -1
		for ev in state.events:
			if ev.kind == CG.EventKind.ACTION_START and ev.source_id == pawn_unit.id:
				used += 1
				last_tick = ev.tick
		print("%s  move_speed %.2f (goblin 4.00)  actions started %d, last at tick %d of %d" % [
			String(class_id), speed, used, last_tick, state.tick,
		])
	quit(0)
