extends SceneTree

## What a taunt does and how much of it the player can see. Issue 132 part 1.

const SEEDS := 20

func _init() -> void:
	var class_ids := ClassLibrary.all_ids()
	for encounter_id in RoomLibrary.all_ids():
		var encounter := RoomLibrary.get_room(encounter_id)
		if not _has_taunter(encounter):
			continue
		var applied := 0
		var roars := 0
		var roars_that_taunted_nobody := 0
		var compelled_actions := 0
		var taunts_with_no_attack := 0
		var silent_ticks := 0
		var taunted_ticks := 0
		var fights := 0
		for skip in class_ids.size():
			var party_ids := []
			for i in class_ids.size():
				if i != skip:
					party_ids.append(class_ids[i])
			for s in SEEDS:
				var party: Array[PawnData] = []
				for cid in party_ids:
					party.append(PawnFactory.make_starter_pawn(cid, StringName("%s_%d" % [cid, party.size()]), String(cid)))
				var state := CombatSim.build(party, encounter, s)
				CombatSim.run(state)
				fights += 1

				var attacked_while_taunted := {}
				var roar_ticks := {}
				var applied_ticks := {}
				for e in state.events:
					if e.kind == CG.EventKind.ACTION_FIRE and e.action_id == &"brute_roar":
						roars += 1
						roar_ticks[e.tick] = true
					elif e.kind == CG.EventKind.STATUS_APPLIED and e.status == CG.Status.TAUNTED:
						applied += 1
						applied_ticks[e.tick] = true
					elif e.kind == CG.EventKind.ACTION_START and e.source_plan == Intent.COMPELLED:
						compelled_actions += 1
						attacked_while_taunted[e.source_id] = int(attacked_while_taunted.get(e.source_id, 0)) + 1
				for t in roar_ticks:
					if not applied_ticks.has(t):
						roars_that_taunted_nobody += 1
				var per_victim := {}
				for e in state.events:
					if e.kind == CG.EventKind.STATUS_APPLIED and e.status == CG.Status.TAUNTED:
						per_victim[e.target_id] = int(per_victim.get(e.target_id, 0)) + 1
				for uid in per_victim:
					if not attacked_while_taunted.has(uid):
						taunts_with_no_attack += int(per_victim[uid])

				var pair := _taunted_ticks(state)
				taunted_ticks += pair[0]
				silent_ticks += pair[1]

		print("")
		print("ENCOUNTER %s, %d fights" % [encounter_id, fights])
		print("  roars                        %d" % roars)
		print("  roars that taunted nobody    %d" % roars_that_taunted_nobody)
		print("  TAUNTED applications         %d" % applied)
		print("  taunts where the pawn never landed a compelled ACTION_START   %d" % taunts_with_no_attack)
		print("  ticks spent taunted          %d" % taunted_ticks)
		print("  of those, ticks with an ACTION_START carrying [taunted]   %d" % compelled_actions)
		print("  of those, ticks with NO event from that unit at all       %d (%.0f%%)" % [
			silent_ticks, 100.0 * float(silent_ticks) / maxf(1.0, float(taunted_ticks)),
		])
	quit(0)

## Ticks a pawn spent carrying TAUNTED, and how many of those produced no event
## naming that pawn -- the window in which the compulsion is invisible.
func _taunted_ticks(state: CombatState) -> Array:
	var window := {}
	for e in state.events:
		if e.status != CG.Status.TAUNTED:
			continue
		if e.kind == CG.EventKind.STATUS_APPLIED:
			window[e.target_id] = e.tick
		elif e.kind == CG.EventKind.STATUS_EXPIRED and window.has(e.target_id):
			window[e.target_id] = [int(window[e.target_id]), e.tick]

	var spoke := {}
	for e in state.events:
		if e.source_id >= 0:
			spoke[[e.source_id, e.tick]] = true
		if e.target_id >= 0:
			spoke[[e.target_id, e.tick]] = true

	var total := 0
	var silent := 0
	for uid in window:
		var span = window[uid]
		if not (span is Array):
			continue
		for t in range(int(span[0]), int(span[1])):
			total += 1
			if not spoke.has([uid, t]):
				silent += 1
	return [total, silent]

func _has_taunter(encounter) -> bool:
	for spawn in encounter.enemy_spawns:
		var e := EnemyLibrary.get_enemy(spawn.get("enemy_id", &""))
		if e == null:
			continue
		for a in e.actions:
			var action := ActionLibrary.get_action(a)
			if action != null and action.applies_status_enabled and action.applies_status == CG.Status.TAUNTING:
				return true
	return false
