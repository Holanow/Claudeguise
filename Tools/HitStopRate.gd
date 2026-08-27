extends SceneTree

## How often a death-gated freeze would fire, and how often an interrupt-gated
## one would, measured on real fights rather than argued about.
##
##   godot --headless --path . --script res://Tools/HitStopRate.gd
##
## Read-only: it runs the fight to completion and then walks `state.events`.
## It never calls `decide`, never samples mid-step, and writes nothing back.

const SEEDS := 8

## Both rooms. `floor1_room1` is the default; `floor1_hazard` is where the
## Brute lives and is the only source of INTERRUPTED in the game today.
const ROOMS := [CG.DEFAULT_ENCOUNTER, &"floor1_hazard"]

## What BattleView will hold for, in seconds, and the tick budget that buys.
const FREEZE_SECONDS := 0.10

func _init() -> void:
	print("HIT STOP RATE. freeze = %.2fs (%d frames at 60Hz, %.1f sim ticks)" % [
		FREEZE_SECONDS, int(round(FREEZE_SECONDS * 60.0)),
		FREEZE_SECONDS / CG.TICK_SECONDS])
	for id in ROOMS:
		_measure(id)
	quit(0)

func _measure(room_id: StringName) -> void:
	var encounter := RoomLibrary.get_room(room_id)
	if encounter == null:
		printerr("no encounter %s" % room_id)
		return
	print("")
	print("ROOM %s" % room_id)

	var fights := 0
	var totals := {
		"seconds": 0.0, "deaths": 0, "death_ticks": 0,
		"interrupts": 0, "interrupt_ticks": 0,
	}
	var worst_death_ticks := 0
	var worst_interrupt_ticks := 0
	# A freeze that fires while the previous one is still on screen reads as one
	# long hold rather than two beats. Deaths one tick apart do that.
	var back_to_back := 0
	var late_deaths := 0

	for party_ids in _parties(ClassLibrary.all_ids()):
		for s in SEEDS:
			var party: Array[PawnData] = []
			for cid in party_ids:
				party.append(PawnFactory.make_starter_pawn(
					cid, StringName("%s_%d" % [cid, party.size()]), String(cid)))
			var state := CombatSim.build(party, encounter, s)
			CombatSim.run(state)
			fights += 1
			totals.seconds += float(state.tick) * CG.TICK_SECONDS

			var death_ticks := _ticks_with(state, CG.EventKind.DEATH)
			var interrupt_ticks := _ticks_with(state, CG.EventKind.INTERRUPTED)
			totals.deaths += _count(state, CG.EventKind.DEATH)
			totals.interrupts += _count(state, CG.EventKind.INTERRUPTED)
			totals.death_ticks += death_ticks.size()
			totals.interrupt_ticks += interrupt_ticks.size()
			worst_death_ticks = maxi(worst_death_ticks, death_ticks.size())
			worst_interrupt_ticks = maxi(worst_interrupt_ticks, interrupt_ticks.size())

			var budget := int(ceil(FREEZE_SECONDS / CG.TICK_SECONDS))
			for i in range(1, death_ticks.size()):
				if death_ticks[i] - death_ticks[i - 1] <= budget:
					back_to_back += 1
			# Clustering: how much of it lands in the closing fifth, which is the
			# half of the question a per-fight average cannot answer.
			var tail := int(float(state.tick) * 0.8)
			for t in death_ticks:
				if t >= tail:
					late_deaths += 1

	var f := float(maxi(fights, 1))
	print("  %d fights, %.0f seconds of fighting" % [fights, totals.seconds])
	print("  DEATHS        %5d total, %5.1f per fight, %.2f/sec" % [
		totals.deaths, totals.deaths / f, totals.deaths / maxf(1.0, totals.seconds)])
	print("  FREEZES       %5d (distinct ticks carrying a death), %5.1f per fight, worst fight %d" % [
		totals.death_ticks, totals.death_ticks / f, worst_death_ticks])
	print("    %d of them land within one freeze of the one before, so they read as" % back_to_back)
	print("    one long hold rather than two beats.")
	print("    %d of %d deaths (%.0f%%) are in the closing fifth of their fight." % [
		late_deaths, totals.deaths, 100.0 * float(late_deaths) / maxf(1.0, float(totals.deaths))])
	print("  frozen time   %5.1fs of %.0fs, %.1f%% of the fight" % [
		totals.death_ticks * FREEZE_SECONDS, totals.seconds,
		100.0 * totals.death_ticks * FREEZE_SECONDS / maxf(1.0, totals.seconds)])
	print("  INTERRUPTED   %5d total, %5.1f per fight, %.2f/sec; %d distinct ticks, worst fight %d" % [
		totals.interrupts, totals.interrupts / f,
		totals.interrupts / maxf(1.0, totals.seconds),
		totals.interrupt_ticks, worst_interrupt_ticks])

func _count(state: CombatState, kind: int) -> int:
	var n := 0
	for e in state.events:
		if e.kind == kind:
			n += 1
	return n

## One freeze per tick, not per event: several deaths in the same tick share it.
func _ticks_with(state: CombatState, kind: int) -> Array[int]:
	var out: Array[int] = []
	for e in state.events:
		if e.kind == kind and (out.is_empty() or out[-1] != e.tick):
			out.append(e.tick)
	return out

## Leave-one-out, per #350: taking the first four skips the Warrior.
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
		out.append(class_ids)
	return out
