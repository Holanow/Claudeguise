extends SceneTree

## Issue 562, and it is a measurement before a design rather than after one.
##
## The issue asks for a beam that is "still there while the target is being
## pulled". This asks whether there IS a pull on screen to be beside:
## `_apply_pull` moves a target in ONE tick, and `BattleView._tween_body`
## refuses to interpolate a step longer than `move_speed * 3 + radius * 3`.

const ScreenSweepScript := preload("res://Tools/ScreenSweep.gd")
const SEEDS := 12

func _init() -> void:
	var pulls := 0
	var snapped := 0
	var worst := 0.0
	var shown := 0
	for party_ids in ScreenSweepScript.sweep_parties(Registry.all_class_ids()):
		if not party_ids.has(&"abomination"):
			continue
		for seed_value in SEEDS:
			var party: Array[PawnData] = []
			for i in party_ids.size():
				party.append(PawnFactory.make_starter_pawn(
					party_ids[i], StringName("p%d" % i), String(party_ids[i])))
			var encounter := Registry.get_encounter(Registry.all_encounter_ids()[0])
			var state := CombatSim.build(party, encounter, seed_value)
			var cursor := 0
			while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
				# Sampled BEFORE the step, per ENGINEER.md: a position read after
				# `step()` returns has already had the pull applied to it.
				var before := {}
				for u in state.units:
					before[u.id] = u.position
				CombatSim.step(state)
				for e in state.events_since(cursor):
					if e.kind != CG.EventKind.DAMAGE:
						continue
					var action := Registry.get_action(e.action_id)
					if action == null or action.pull_distance <= 0.0:
						continue
					var target := state.unit(e.target_id)
					if target == null or not before.has(target.id):
						continue
					var moved: float = before[target.id].distance_to(target.position)
					var ceiling: float = target.move_speed * 3.0 \
						+ UnitView.display_radius(target) * 3.0
					pulls += 1
					worst = maxf(worst, moved)
					if moved > ceiling:
						snapped += 1
					if shown < 8:
						shown += 1
						print("  %-22s moved %6.1f  ceiling %6.1f  move_speed %.2f  radius %.1f  -> %s" % [
							e.action_id, moved, ceiling, target.move_speed, target.radius,
							"SNAP" if moved > ceiling else "slides"])
				cursor = state.events.size()
	print("PullSnap: %d pull(s) landed, %d of them SNAP rather than slide, longest %.1f units" % [
		pulls, snapped, worst])
	quit(0)
