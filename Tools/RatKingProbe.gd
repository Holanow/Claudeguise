extends SceneTree

## Issue 356: does the Rat King move and attack, or does it stand still?


const SEEDS := 5

func _init() -> void:
	var encounter := Registry.get_encounter(&"floor1_rat_king")
	var class_ids := Registry.all_class_ids()
	for skip in class_ids.size():
		for s in SEEDS:
			var party: Array[PawnData] = []
			for i in class_ids.size():
				if i == skip:
					continue
				var cid: StringName = class_ids[i]
				party.append(PawnFactory.make_starter_pawn(cid, StringName("%s_%d" % [cid, i]), String(cid)))
			var state := CombatSim.build(party, encounter, s)
			var king: CombatUnit = null
			for u in state.units:
				if u.enemy_id == &"rat_king":
					king = u
			var start := king.position
			var moved := 0.0
			var last := king.position
			var actions := 0
			var last_action := &""
			var nearest_ever := 1e9
			while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < 3600:
				CombatSim.step(state)
				if not king.alive:
					break
				moved += king.position.distance_to(last)
				last = king.position
				if king.current_action != &"" and king.current_action != last_action:
					actions += 1
				last_action = king.current_action
				for u in state.units:
					if u.team == CG.Team.PLAYER and u.alive:
						nearest_ever = minf(nearest_ever, king.position.distance_to(u.position))
			var first_fire := -1
			for e in state.events:
				if e.source_id == king.id and e.kind == CG.EventKind.ACTION_FIRE and first_fire < 0:
					first_fire = e.tick
			var dealt := 0
			var summons := 0
			for e in state.events:
				if e.source_id == king.id and e.kind == CG.EventKind.DAMAGE:
					dealt += e.amount
				if e.source_id == king.id and e.kind == CG.EventKind.ACTION_FIRE:
					summons += 1
			print("-%-13s seed %2d  ticks %4d  king alive=%s hp %d/%d  travelled %.0f  from %s to %s  action starts %d  damage dealt %d  action fires %d  closest %.0f  first fire tick %d" % [
				String(class_ids[skip]), s, state.tick, str(king.alive), maxi(0, king.hp), king.hp_max,
				moved, str(start), str(king.position), actions, dealt, summons, nearest_ever, first_fire,
			])
	quit(0)
