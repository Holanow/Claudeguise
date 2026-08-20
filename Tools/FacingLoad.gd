extends Node

## Issue 256: how often was the old drawing rule wrong?
##
##   godot --path . --headless res://Tools/FacingLoad.tscn
##
## OWNER: wren. Not part of the game and not part of the gate.
##
## `UnitView` drew `facing_left = (team == ENEMY)`. `CombatUnit.facing` is real
## and the simulation reads it to decide whether the Warrior's guard stops a
## shot. **Before changing the line, measure how much it was lying**, because
## "every enemy is permanently mirrored" is a statement about the code and the
## thing worth knowing is how many drawn frames disagreed with the fight.
##
## Sampled every tick, per living unit: what the team rule would have drawn,
## what `facing` says, and whether they agree. A unit with no facing yet is
## counted separately -- the team guess is the answer there and is not wrong.


const PARTY := [&"geysermancer", &"priest", &"siege_master", &"warrior"]
const ROOMS := [&"floor1_room1", &"floor1_cover", &"floor1_warden"]
const SEEDS := 10

func _ready() -> void:
	var party: Array[PawnData] = []
	for id in PARTY:
		party.append(PawnFactory.make_starter_pawn(id, id, Registry.get_class_def(id).display_name))

	var totals := {}
	for room in ROOMS:
		var agree := 0
		var disagree := 0
		var unset := 0
		var vertical := 0
		for seed in SEEDS:
			var state := CombatSim.build(party, Registry.get_encounter(room), seed)
			while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
				CombatSim.step(state)
				for u in state.units:
					if not u.alive:
						continue
					if u.facing == Vector2.ZERO:
						unset += 1
						continue
					if u.facing.x == 0.0:
						vertical += 1
						continue
					var team_rule := u.team == CG.Team.ENEMY
					if team_rule == (u.facing.x < 0.0):
						agree += 1
					else:
						disagree += 1
		var live: int = agree + disagree
		totals[room] = "%d of %d live unit-ticks drawn the wrong way (%.1f%%), %d with no facing yet, %d facing straight up or down" % [
			disagree, live, 0.0 if live == 0 else 100.0 * float(disagree) / float(live), unset, vertical]
	for room in ROOMS:
		print("FacingLoad %s: %s" % [room, totals[room]])
	get_tree().quit(0)
