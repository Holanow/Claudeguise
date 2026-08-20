extends SceneTree

## How many statuses does a unit actually carry AT ONCE, in real fights?
##
##   godot --headless --path . --script res://Tools/StatusLoad.gd
##
## OWNED BY sable (`Scripts/Art/**`). Not part of the gate.
##
## WHY THIS EXISTS
##
## `UnitView.MAX_STATUS_BADGES` is 4, and a row of four badges is between 1.8x
## and 2.7x the width of the unit it describes (`Tools/BadgeLegibility.tscn`).
## Cutting the cap is the one recommendation left from `BADGE-LEGIBILITY.md`
## that is not a drawing change -- but **nobody has ever measured what the cap
## costs**, and the number 4 was reasoned from "a unit can in principle carry
## every status at once", which is a statement about the type and not about the
## game.
##
## So: sample every living unit on every tick of real encounters with real
## parties, and count. If four badges are routinely needed the cap stays and the
## problem is elsewhere. If a unit almost never carries more than two, then four
## slots are being reserved -- and paid for in width, on every unit, all the
## time -- for a case that does not happen.
##
## **This measures, it does not tune.** It reads the simulation and changes
## nothing in it. Parties are taken from the same leave-one-out set
## `Tools/SampleFights.gd` uses, for the same reason: `PartySelect` allows one
## card per class, so four-of-a-kind parties are not parties and a number taken
## from them is a number about a team nobody can build.


const SEEDS := 20
const MAX_TICKS := 3600

## Counts of simultaneous statuses, indexed by count. Index 0 is "carrying
## nothing", which matters as much as the tail: a badge row that is empty most
## of the time is a different design problem from one that is always full.
var _hist_all := {}
var _hist_player := {}
var _hist_enemy := {}
var _peak := 0
var _peak_where := ""
## Unit-ticks where at least one status would be hidden at a given cap.
var _hidden_at := {}

func _init() -> void:
	var class_ids := Registry.all_class_ids()
	var encounter_ids := Registry.all_encounter_ids()
	if class_ids.is_empty() or encounter_ids.is_empty():
		printerr("no content registered; nothing to sample")
		quit(1)
		return

	for encounter_id in encounter_ids:
		var encounter := Registry.get_encounter(encounter_id)
		for party_ids in _parties(class_ids):
			for seed_index in SEEDS:
				_run(party_ids, encounter, 0x2A + seed_index)

	_report()
	quit(0)

func _run(party_ids: Array, encounter, fight_seed: int) -> void:
	var party: Array[PawnData] = []
	for cid in party_ids:
		party.append(PawnFactory.make_starter_pawn(
			cid, StringName("%s_%d" % [cid, party.size()]), Registry.get_class_def(cid).display_name))
	var state := CombatSim.build(party, encounter, fight_seed)
	var ticks := 0
	while state.outcome == CombatState.Outcome.UNRESOLVED and ticks < MAX_TICKS:
		CombatSim.step(state)
		ticks += 1
		# Sampled AFTER step: `_tick_statuses` runs late, so a set read before
		# it is a set from the previous tick. The same trap finch documented for
		# `unit.intent`.
		for u in state.units:
			if not u.alive:
				continue
			# Counted through the view's own ordering function, not by reading
			# the dictionary here, so this counts exactly what the badge row
			# would be asked to draw. A second way of counting is a second thing
			# to disagree with the screen.
			var n: int = UnitView.ordered_statuses(u).size()
			_bump(_hist_all, n)
			_bump(_hist_player if u.team == CG.Team.PLAYER else _hist_enemy, n)
			for cap in [1, 2, 3, 4]:
				if n > cap:
					_bump(_hidden_at, cap)
			if n > _peak:
				_peak = n
				_peak_where = "%s on tick %d, seed %08X" % [_name_of(u), ticks, fight_seed]

func _name_of(u) -> String:
	if u.pawn != null and u.pawn.pawn_class != null:
		return String(u.pawn.pawn_class.id)
	return String(u.enemy_id)

func _bump(into: Dictionary, key: int) -> void:
	into[key] = int(into.get(key, 0)) + 1

func _total(hist: Dictionary) -> int:
	var t := 0
	for v in hist.values():
		t += int(v)
	return t

func _report() -> void:
	var total := _total(_hist_all)
	print("")
	print("SIMULTANEOUS STATUSES PER LIVING UNIT, PER TICK")
	print("  %d unit-ticks sampled across %d seeds, every encounter, every buildable party" % [
		total, SEEDS])
	print("  peak observed: %d  (%s)" % [_peak, _peak_where])
	print("")
	print("  %-8s %-12s %-9s %-12s %s" % ["statuses", "unit-ticks", "share", "player", "enemy"])
	var highest := _peak
	for n in range(0, highest + 1):
		var all_n := int(_hist_all.get(n, 0))
		if all_n == 0 and n > 0:
			continue
		print("  %-8d %-12d %-9s %-12d %d" % [
			n, all_n, "%.2f%%" % (100.0 * float(all_n) / maxf(float(total), 1.0)),
			int(_hist_player.get(n, 0)), int(_hist_enemy.get(n, 0))])

	print("")
	print("WHAT EACH CAP WOULD HIDE")
	print("  A unit-tick is 'hidden' if the unit carried more statuses than the")
	print("  cap allows, so the row had to drop at least one behind a +N chip.")
	print("  MAX_STATUS_BADGES is currently %d." % UnitView.MAX_STATUS_BADGES)
	print("")
	print("  %-6s %-14s %s" % ["cap", "hidden ticks", "share of all unit-ticks"])
	for cap in [1, 2, 3, 4]:
		var hidden := int(_hidden_at.get(cap, 0))
		print("  %-6d %-14d %.3f%%" % [cap, hidden, 100.0 * float(hidden) / maxf(float(total), 1.0)])

	# The number the design decision actually turns on: of the ticks where a unit
	# is carrying anything at all, how often is it carrying more than two? A cap
	# is paid for on every unit at all times; it is only *earned* on these.
	var carrying := total - int(_hist_all.get(0, 0))
	print("")
	print("  Of the %d unit-ticks carrying ANY status (%.1f%% of all):" % [
		carrying, 100.0 * float(carrying) / maxf(float(total), 1.0)])
	for cap in [1, 2, 3]:
		var hidden := int(_hidden_at.get(cap, 0))
		print("    a cap of %d would hide something on %.1f%% of them" % [
			cap, 100.0 * float(hidden) / maxf(float(carrying), 1.0)])

## The leave-one-out parties, exactly as Tools/SampleFights.gd builds them, and
## for the reason written at length there: `PartySelect` allows one card per
## class, so four-of-a-kind teams are not teams. Not duplicated for the
## mono-class diagnostic rows -- this tool has no per-class question.
func _parties(class_ids: Array) -> Array:
	var out := []
	if class_ids.size() > 4:
		for skip in class_ids.size():
			var party := []
			for i in class_ids.size():
				if i != skip:
					party.append(class_ids[i])
			out.append(party)
	elif class_ids.size() >= 1:
		out.append(class_ids.slice(0, mini(4, class_ids.size())))
	return out
