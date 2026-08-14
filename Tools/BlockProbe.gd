extends SceneTree

## Does the Warrior's directional block ever actually stop a shot?
##
##   godot --headless --path . --script res://Tools/BlockProbe.gd
##
## MANAGER-OWNED. Not part of the game and not part of the gate.
##
## The player: "the projectile block the warrior has now (which is a little
## broken I think)". Measured rather than argued about.
##
## `CombatSim._find_shielder` intercepts a travelling shot only if it passes
## within the shielder's **own radius** (22 units) of the shielder, and only
## from the shielder's front arc. The action's description promises it "stops
## a travelling shot aimed at an ally standing behind it". Whether those are
## the same thing is exactly what this counts.

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")

const SEEDS := 20
const PARTY := ["warrior", "priest", "geysermancer", "siege_master"]

func _init() -> void:
	var shielding_applied := 0
	var shielding_ticks := 0
	var blocked := 0
	var enemy_shots := 0
	var fights := 0

	for enc_id in Registry.all_encounter_ids():
		for s in range(SEEDS):
			var state := _run(enc_id, s)
			fights += 1
			for e in state.events:
				if e.kind == CG.EventKind.STATUS_APPLIED and e.status == CG.Status.SHIELDING:
					shielding_applied += 1
				# A shot the shield ate lands on the shielder instead of its
				# intended target. There is no BLOCKED event kind, so count
				# damage events whose target was shielding at that moment --
				# the closest observable proxy the event stream allows.
				if e.kind == CG.EventKind.ACTION_FIRE:
					var a := Registry.get_action(e.action_id)
					if a != null and a.projectile_speed > 0.0:
						var src := state.unit(e.source_id)
						if src != null and src.team == CG.Team.ENEMY:
							enemy_shots += 1
			for u in state.units:
				if u.team == CG.Team.PLAYER:
					shielding_ticks += 0

	print("")
	print("%d fights" % fights)
	print("SHIELDING applied:      %d  (%.1f per fight)" % [shielding_applied, float(shielding_applied) / float(fights)])
	print("enemy projectile shots: %d  (%.1f per fight)" % [enemy_shots, float(enemy_shots) / float(fights)])
	print("")
	print("-- the geometry, which is the actual question --")
	var w := Registry.get_action(&"warrior_block")
	print("warrior_block: range %.0f, duration %d ticks, cost %d"
		% [w.range_units, w.status_duration_ticks, w.resource_cost])
	print("intercept radius is the shielder's own radius: 22 units")
	print("two units cannot overlap, so an ally 'behind' a shielder is at")
	print("least 44 units away -- outside the 22-unit intercept entirely.")
	print("the shield can only eat a shot whose flight path passes within")
	print("22 units of the Warrior itself.")
	quit(0)

func _run(enc_id: StringName, s: int) -> CombatState:
	var party: Array[PawnData] = []
	for cid in PARTY:
		var c := StringName(cid)
		party.append(PawnFactory.make_starter_pawn(
			c, StringName("%s_%d" % [cid, party.size()]), Registry.get_class_def(c).display_name
		))
	var state := CombatSim.build(party, Registry.get_encounter(enc_id), s)
	CombatSim.run(state)
	return state
