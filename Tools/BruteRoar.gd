extends SceneTree

## Does the Brute's roar fire, does it pull anybody, and does it lock a pawn?
##
##   godot --headless --path . --script res://Tools/BruteRoar.gd
##
## Not part of the game and not part of the gate. Issue 150, finch.
##
## **The third question is the one the player already ruled on** -- *"taunts must
## not permanently lock a pawn"* (#58) -- so it is measured directly rather than
## argued from the numbers on the action. `longest lock` is the most consecutive
## ticks any single pawn spent carrying TAUNTED in any fight, sampled every tick
## from `unit.statuses`. An 8-second roar on a 16-second cooldown should top out
## near 120 ticks and never approach the length of a fight.
##
## The control arm strips `brute_roar` from the Brute's own `unit.actions` after
## the state is built and changes nothing else, so the arms differ by one entry
## in one list. That is also the live proof of the branch it exercises: with the
## action present and `DefaultBehavior` unable to aim a self-targeted action, the
## two arms would be identical -- which is exactly what swift measured on `main`
## and reported on #150.

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")

const ENCOUNTER := &"floor1_hazard"
const SEEDS := 60
const ROAR := &"brute_roar"
const ALL := ["abomination", "geysermancer", "priest", "siege_master", "warrior"]

func _parties() -> Array:
	var out: Array = []
	for i in ALL.size():
		var p: Array = []
		for j in ALL.size():
			if i != j:
				p.append(ALL[j])
		out.append(p)
	return out

func _init() -> void:
	print("")
	print("BRUTE ROAR, %s, %d seeds x %d buildable parties" % [ENCOUNTER, SEEDS, _parties().size()])
	print("")
	print("%-14s %8s %10s %8s %8s %10s %12s %12s %11s" % [
		"arm", "wins", "avg ticks", "lost", "roars", "taunted", "longest lock", "brute taken", "party burn"])
	_row("no roar", _arm(false))
	_row("shipped", _arm(true))
	print("")
	print("'roars' is ACTION_FIRE for brute_roar per fight; 'taunted' is pawn-ticks")
	print("carrying TAUNTED per fight; 'longest lock' is the most consecutive ticks")
	print("ONE pawn ever carried it, against the player's #58 ruling that a taunt")
	print("must not permanently affect a pawn; 'brute taken' is damage the Brute")
	print("absorbed per fight, which is what a taunt is for; 'party burn' is damage")
	print("to pawns with no unit behind it -- the pit plus whatever DOTs are")
	print("already on them, which this count cannot separate.")
	quit(0)

func _row(label: String, r: Dictionary) -> void:
	print("%-14s %4d/%-4d %10.1f %8.2f %8.2f %10.1f %12d %12.1f %11.1f" % [
		label, r["wins"], r["fights"], r["avg_ticks"], r["lost"], r["roars"],
		r["taunted"], r["longest"], r["brute_taken"], r["party_burn"],
	])

func _arm(with_roar: bool) -> Dictionary:
	var fights := 0
	var wins := 0
	var ticks := 0
	var lost := 0
	var roars := 0
	var taunted := 0
	var longest := 0
	var brute_taken := 0
	var party_burn := 0

	for ids in _parties():
		for s in range(SEEDS):
			var party: Array[PawnData] = []
			for cid in ids:
				var c := StringName(cid)
				party.append(PawnFactory.make_starter_pawn(
					c, StringName("%s_%d" % [cid, party.size()]), Registry.get_class_def(c).display_name
				))
			var state := CombatSim.build(party, Registry.get_encounter(ENCOUNTER), s)
			if not with_roar:
				for u in state.units:
					if u.enemy_id == &"brute":
						u.actions.erase(ROAR)
			# Stepped by hand because a status is state, not an event: the run
			# of ticks a pawn spends TAUNTED cannot be recovered from
			# `state.events` afterwards, only its start and its end.
			var run := {}
			while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
				CombatSim.step(state)
				for u in state.units:
					if u.pawn == null or not u.alive:
						continue
					if u.has_status(CG.Status.TAUNTED):
						taunted += 1
						run[u.id] = int(run.get(u.id, 0)) + 1
						longest = maxi(longest, int(run[u.id]))
					else:
						run[u.id] = 0
			fights += 1
			ticks += state.tick
			if state.outcome == CombatState.Outcome.PLAYER_WIN:
				wins += 1
			for u in state.units:
				if u.pawn != null and not u.alive:
					lost += 1
			for e in state.events:
				if e.kind == CG.EventKind.ACTION_FIRE and e.action_id == ROAR:
					roars += 1
				elif e.kind == CG.EventKind.DAMAGE:
					var tgt := state.unit(e.target_id)
					if tgt != null and tgt.enemy_id == &"brute":
						brute_taken += e.amount
					## Everything that hurt a pawn with no unit behind it: the
					## burn pit, and the poison and burn already ticking on it.
					## Labelled as what it is rather than as "the fire", because
					## this count cannot separate the three.
					if e.source_id == -1 and tgt != null and tgt.pawn != null:
						party_burn += e.amount

	return {
		"fights": fights,
		"wins": wins,
		"avg_ticks": float(ticks) / float(fights),
		"lost": float(lost) / float(fights),
		"roars": float(roars) / float(fights),
		"taunted": float(taunted) / float(fights),
		"longest": longest,
		"brute_taken": float(brute_taken) / float(fights),
		"party_burn": float(party_burn) / float(fights),
	}
