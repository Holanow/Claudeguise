extends SceneTree

## Issue 836. "A combo that lands one beat in three is a defect wearing a
## feature's clothes", so this counts what each beat actually did rather than
## whether the combo exists.
##
## No new instrumentation in the simulation: `_resolve_beat` already emits
## ACTION_FIRE and MISS carrying `beat_index`, so a beat that reached nobody is
## already distinguishable in the event stream from one that landed.
##
## The measurement is CONNECT RATE PER BEAT. #830 measured that the Warden's
## abilities can work against him -- the throw removes his own melee target --
## and a slow boss committed to a three-part combo is the same risk again.

const SEEDS := 20
const ROOM := &"floor1_warden"
const COMBO := &"warden_axe"

func _init() -> void:
	var beats: int = ActionLibrary.get_action(COMBO).beats.size()
	print("WardenCombo -- issue 836. %s, %d beats, %s, %d seeds x %d compositions" % [
		COMBO, beats, ROOM, SEEDS, PartySpec.compositions().size()])
	if beats == 0:
		print("  %s has no beats; nothing to measure." % COMBO)
		quit(0)
		return
	for i in beats:
		var b: ActionBeat = ActionLibrary.get_action(COMBO).beats[i]
		var reach: float = b.targeting.range_units if b.targeting != null \
			else ActionLibrary.get_action(COMBO).range_units
		print("  beat %d  delay %2dt  reach %5.1f" % [i, b.delay_ticks, reach])

	var fired := {}
	var missed := {}
	var bleeds := 0
	var combos := 0
	var interrupted := 0
	var unfinished := 0
	var total_damage := 0
	## What INTERRUPTS the combo. `_interrupt_on_stun` is the only path that
	## throws a wind-up away, so whatever applied the STUN is the cause.
	var stunners := {}
	var runs := 0
	var ticks := 0
	for combo in PartySpec.compositions():
		for s in range(SEEDS):
			var state := CombatSim.build(PartySpec.make(combo, true),
				RoomLibrary.get_room(ROOM), hash([s, ROOM]))
			CombatSim.run(state)
			runs += 1
			ticks += state.tick
			## Committed to the combo when the fight ended: the wind-up never
			## finished, so nothing fired and nothing was interrupted either.
			for u in state.units:
				if u.current_action == COMBO and u.action_ticks_left > 0:
					unfinished += 1
			for e in state.events:
				if e.kind == CG.EventKind.STATUS_APPLIED and e.status == CG.Status.STUN 						and state.unit(e.target_id) != null 						and state.unit(e.target_id).enemy_id == &"the_warden":
					stunners[e.action_id] = int(stunners.get(e.action_id, 0)) + 1
				if e.action_id != COMBO:
					continue
				match e.kind:
					CG.EventKind.ACTION_START:
						combos += 1
					CG.EventKind.ACTION_FIRE:
						fired[e.beat_index] = int(fired.get(e.beat_index, 0)) + 1
					CG.EventKind.MISS:
						missed[e.beat_index] = int(missed.get(e.beat_index, 0)) + 1
					CG.EventKind.DAMAGE:
						## DAMAGE carries `action_id` but NOT `beat_index` --
						## only ACTION_FIRE and MISS are tagged -- so this is a
						## per-action total and cannot be split per beat.
						total_damage += e.amount
					CG.EventKind.INTERRUPTED:
						interrupted += 1
					CG.EventKind.STATUS_APPLIED:
						if e.status == CG.Status.BLEED:
							bleeds += 1

	print("\n%d fights, %d combos started, %.1fs mean fight" % [
		runs, combos, float(ticks) / float(runs) * CG.TICK_SECONDS])
	print("  %d interrupted mid-wind-up, %d still winding up when the fight ended" % [
		interrupted, unfinished])
	print("  %d total damage from %s" % [total_damage, COMBO])
	print("\n  beat   resolved   landed    whiffed   connect")
	for i in beats:
		var f := int(fired.get(i, 0))
		var m := int(missed.get(i, 0))
		## A beat that resolves either lands on somebody or emits a MISS, so
		## `f` counts resolutions and `f - m` counts the ones that connected.
		var hit := f - m
		print("  %4d   %8d   %6d   %8d   %6.1f%%" % [
			i, f, hit, m, 100.0 * float(hit) / maxf(1.0, float(f))])

	## The number the issue actually asks for: of the combos that STARTED, how
	## many of their later beats ever resolved at all. A beat is dropped
	## entirely if the caster dies before its tick arrives, which never shows
	## up as a miss.
	print("\n  of %d combos started:" % combos)
	for i in beats:
		var f := int(fired.get(i, 0))
		var m := int(missed.get(i, 0))
		print("    beat %d resolved in %5.1f%% of them, connected in %5.1f%%" % [
			i, 100.0 * float(f) / maxf(1.0, float(combos)),
			100.0 * float(f - m) / maxf(1.0, float(combos))])
	var keys := stunners.keys()
	keys.sort()
	print("\n  what stunned the Warden, which is the only thing that throws a wind-up away:")
	for k in keys:
		print("    %-24s %d" % [String(k), int(stunners[k])])

	print("\n  %d BLEED applications, %.2f per combo started" % [
		bleeds, float(bleeds) / maxf(1.0, float(combos))])
	quit(0)
