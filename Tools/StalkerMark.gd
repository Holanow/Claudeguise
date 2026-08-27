extends SceneTree

## Issue 642. The instrument that attributed a since-closed regression in
## `stalker_mark` on the colonnade to the Stalker dying early rather than to its
## targeting: the same 20 fights the test runs, counting what the Stalker did
## rather than only what landed.

func _ids() -> Array[StringName]:
	var names := PackedStringArray()
	for id in Registry.all_class_ids():
		names.append(String(id))
	names.sort()
	var out: Array[StringName] = []
	for n in names:
		out.append(StringName(n))
	return out

func _init() -> void:
	var class_ids := _ids()
	var enc := Registry.get_encounter(&"floor1_cover")
	var marks := 0
	var fired := 0
	var dart_fired := 0
	var died := 0
	var death_ticks := 0
	var ticks := 0
	var fights := 0
	for skip in class_ids.size():
		var ids: Array[StringName] = []
		for i in class_ids.size():
			if i != skip:
				ids.append(class_ids[i])
		for seed in 4:
			var party: Array[PawnData] = []
			for j in ids.size():
				party.append(PawnFactory.make_preset_pawn(ids[j], StringName("%s_%d_%d" % [ids[j], seed, j]), String(ids[j])))
			var state := CombatSim.build(party, enc, seed)
			CombatSim.run(state)
			fights += 1
			ticks += state.tick
			var stalker_id := -1
			for u in state.units:
				if u.enemy_id == &"stalker":
					stalker_id = u.id
			for e in state.events:
				if e.kind == CG.EventKind.STATUS_APPLIED and e.action_id == &"stalker_mark":
					marks += 1
				if e.kind == CG.EventKind.ACTION_FIRE and e.action_id == &"stalker_mark":
					fired += 1
				if e.kind == CG.EventKind.ACTION_FIRE and e.action_id == &"stalker_dart":
					dart_fired += 1
				if e.kind == CG.EventKind.DEATH and e.target_id == stalker_id:
					died += 1
					death_ticks += e.tick
	print("fights %d  median-ish mean ticks %.0f" % [fights, float(ticks) / fights])
	print("stalker_mark FIRED %d  LANDED %d" % [fired, marks])
	print("stalker_dart FIRED %d" % dart_fired)
	print("stalker died in %d of %d fights, mean death tick %.0f"
		% [died, fights, (float(death_ticks) / died) if died > 0 else -1.0])
	quit(0)
