extends SceneTree

## What does the shipped Immolate actually do, and what does it cost the rest of
## the Abomination's kit?
##
##   godot --headless --path . --script res://Tools/ImmolateWindow.gd
##
## Not part of the game and not part of the gate. Issue 219, finch.
##
## **This is the with-and-without column, not a win table.** Announcement rule 1
## on the board: a win table cannot see a dead mechanic, and heron nearly shipped
## a colonnade whose pillars did nothing because the outcomes looked right. So
## every number below is printed for two arms of the same seeds -- the shipped
## content, and the same content with `abomination_immolate_dump` removed from
## the pawn's plans -- and the interesting rows are the ones that differ.
##
## **Removing the PLAN is the whole control, and that is deliberate rather than
## convenient.** `abomination_immolate` stays in `unit.actions` in both arms, so
## if the aura ever fires in the "no plan" arm, `DefaultBehavior` has reached a
## sustained action and the guard in `_attack_candidates` is broken. That is a
## real assertion this tool makes by construction, not a side effect.
##
## Single room, per CLAUDE.md: `floor1_room1` is the instrument. `Tools/
## FloorRuns.gd` is not evidence about a single-room decision.
##
## **Two columns are the honest ones and they are both costs.** `wasted` is the
## share of charged aura ticks that reached no enemy at all -- the channel holds
## while an enemy is within 90 and charges every tick regardless of whether one
## is still standing there when the tick resolves. `held each` is how long one
## channel lasts, and it is short: `abomination_grapple_close` sits above the
## aura's plan and takes the tick the moment anything reaches 45 units, so the
## channel is punctuation rather than a stance. Both are stated in
## `PresetPlans.gd` beside the row that causes them.


const ENCOUNTER := &"floor1_room1"
const SEEDS := 120
const PARTY := ["abomination", "geysermancer", "priest", "warrior"]

const IMMOLATE := &"abomination_immolate"
const IMMOLATE_PLAN := &"abomination_immolate_dump"
const KIT := [&"abomination_claw", &"abomination_grapple", &"abomination_hook"]

func _init() -> void:
	print("")
	print("IMMOLATE, %s, %d seeds, party %s" % [ENCOUNTER, SEEDS, PARTY])
	print("")
	var without := _arm(false)
	var with_it := _arm(true)
	print("%-18s %8s %10s %8s %9s %10s %8s %9s %8s" % [
		"arm", "wins", "avg ticks", "lost", "channels", "held each", "burn", "% party", "wasted"])
	_row("no immolate plan", without)
	_row("shipped", with_it)
	print("")
	print("%-18s %10s %10s %10s %10s" % ["arm", "claw", "grapple", "hook", "abom dmg"])
	_kit_row("no immolate plan", without)
	_kit_row("shipped", with_it)
	print("")
	print("'channels' is SUSTAIN_START per fight, the event kind #219 exists to")
	print("make happen; 'held each' is ticks per channel, at 15 ticks a second.")
	print("The kit table is the guard against the new plan making the other three")
	print("actions inert, which is how this project keeps losing abilities.")
	quit(0)

func _row(label: String, r: Dictionary) -> void:
	print("%-18s %4d/%-3d %10.1f %8.2f %9.2f %10.1f %8d %8.1f%% %7.1f%%" % [
		label, r["wins"], SEEDS, r["avg_ticks"], r["pawns_lost"], r["channels"],
		r["ticks_each"], r["burn"], r["burn_share"] * 100.0, r["wasted"] * 100.0,
	])

func _kit_row(label: String, r: Dictionary) -> void:
	var f: Dictionary = r["fires"]
	print("%-18s %10.2f %10.2f %10.2f %10d" % [
		label, f[KIT[0]], f[KIT[1]], f[KIT[2]], r["abom_damage"]])

func _arm(with_plan: bool) -> Dictionary:
	var wins := 0
	var ticks := 0
	var pawns_lost := 0
	var channels := 0
	var ticks_held := 0
	var burn := 0
	var party_damage := 0
	var abom_damage := 0
	var charged_ticks := 0
	var wasted_ticks := 0
	var fires := {}
	for id in KIT:
		fires[id] = 0

	for s in range(SEEDS):
		var state := _run(with_plan, s)
		if state.outcome == CombatState.Outcome.PLAYER_WIN:
			wins += 1
		ticks += state.tick
		for u in state.units:
			if u.pawn != null and not u.alive:
				pawns_lost += 1

		# A charged tick that reached nobody. Both halves are read off events on
		# the same tick rather than from the simulation's own state, which dies
		# inside `step()` -- announcement rule 2.
		var charged := {}
		var landed := {}
		for e in state.events:
			match e.kind:
				CG.EventKind.DAMAGE:
					var src := state.unit(e.source_id)
					if src != null and src.team == CG.Team.PLAYER:
						party_damage += e.amount
						if _is_abomination(src):
							abom_damage += e.amount
					if e.action_id == IMMOLATE:
						burn += e.amount
						landed[e.tick] = true
				CG.EventKind.RESOURCE_SPENT:
					if e.action_id == IMMOLATE:
						charged[e.tick] = true
				CG.EventKind.SUSTAIN_START:
					channels += 1
				CG.EventKind.SUSTAIN_END:
					ticks_held += e.amount
				CG.EventKind.ACTION_FIRE:
					if fires.has(e.action_id):
						fires[e.action_id] = int(fires[e.action_id]) + 1
		charged_ticks += charged.size()
		for t in charged:
			if not landed.has(t):
				wasted_ticks += 1

	var per_fight := {}
	for id in KIT:
		per_fight[id] = float(fires[id]) / float(SEEDS)

	return {
		"wins": wins,
		"avg_ticks": float(ticks) / float(SEEDS),
		"pawns_lost": float(pawns_lost) / float(SEEDS),
		"channels": float(channels) / float(SEEDS),
		"ticks_held": float(ticks_held) / float(SEEDS),
		"ticks_each": (float(ticks_held) / float(channels)) if channels > 0 else 0.0,
		"burn": burn,
		"burn_share": (float(burn) / float(party_damage)) if party_damage > 0 else 0.0,
		"wasted": (float(wasted_ticks) / float(charged_ticks)) if charged_ticks > 0 else 0.0,
		"abom_damage": abom_damage,
		"fires": per_fight,
	}

func _is_abomination(u: CombatUnit) -> bool:
	return u.pawn != null and u.pawn.pawn_class != null and u.pawn.pawn_class.id == &"abomination"

func _run(with_plan: bool, fight_seed: int) -> CombatState:
	var party: Array[PawnData] = []
	for cid in PARTY:
		var c := StringName(cid)
		var pawn := PawnFactory.make_starter_pawn(
			c, StringName("%s_%d" % [cid, party.size()]), Registry.get_class_def(c).display_name
		)
		if not with_plan:
			var kept: Array = []
			for p in pawn.plans:
				if p.id != IMMOLATE_PLAN:
					kept.append(p)
			pawn.plans.assign(kept)
		party.append(pawn)
	var state := CombatSim.build(party, Registry.get_encounter(ENCOUNTER), fight_seed)
	CombatSim.run(state)
	return state
