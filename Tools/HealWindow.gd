extends SceneTree

## Issue 138: HEAL fired once in eight full fights against 98 deaths.
##
##   godot --headless --path . --script res://Tools/HealWindow.gd
##
## Not part of the game and not part of the gate. Throwaway instrument, kept
## because the number it produces is the argument.
##
## **Counts firable ticks, not casts.** A cast count cannot tell "the window
## never opens" from "the window opens and something else takes the tick", and
## this project has now been wrong about that three times (`warrior_execute`,
## `geyser_scald`, the plan-less cleanse). A firable tick is one where a living
## Priest is free to act, an ally is at or below the heal threshold, that ally is
## inside `priest_heal`'s reach, and the Priest can pay for it -- every gate the
## real decision has to pass, and no gate it does not.
##
## The four counters below are nested on purpose, so the drop-off says which
## gate is the one that closes:
##
##   free                     -- not winding up or recovering
##   ...with a hurt ally      -- somebody at or below HEAL_THRESHOLD_FRACTION
##   ...in reach              -- and inside priest_heal.range_units
##   ...and affordable        -- and Mana and cooldown both allow it  = FIRABLE
##
## Then, on every firable tick, what the Priest did with it instead, read from
## the ACTION_START it emitted on that same tick and attributed to the plan that
## chose it (`CombatEvent.source_plan`). "Nothing" means it moved or idled.

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")
const SimDeps := preload("res://Scripts/Combat/SimDeps.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const PlanInterpreter := preload("res://Scripts/Plans/PlanInterpreter.gd")
const DefaultBehavior := preload("res://Scripts/Plans/DefaultBehavior.gd")

const SEEDS := 6
const HEAL_ID := &"priest_heal"

func _init() -> void:
	var class_ids := Registry.all_class_ids()
	var encounter_ids := Registry.all_encounter_ids()
	var heal := Registry.get_action(HEAL_ID)
	if heal == null:
		printerr("no priest_heal")
		quit(1)
		return

	print("")
	print("priest_heal: range %.0f, cost %d, cooldown %d, power %.2f" % [
		heal.range_units, heal.resource_cost, heal.cooldown_ticks, heal.power_scale
	])
	print("threshold  : %.2f of max hp (DefaultBehavior and the preset plan agree)" % DefaultBehavior.HEAL_THRESHOLD_FRACTION)

	for arm in [0, 1, 2]:
		print("")
		if arm == 1:
			print("################ ARM B: Smite gated on self_resource_at_least 40 ################")
		elif arm == 2:
			print("################ ARM C: Smite, Ward and Haste all gated on 40 ################")
			print("Heal costs 25 and Smite costs 15, so 40 is 'spend only what the heal")
			print("does not need'. The range gate it replaces is not lost: a plan whose")
			print("focus is out of range is already declined by _target_in_range, which")
			print("is the same argument issue 79's Scald ladder rests on.")
		else:
			print("################ ARM A: main as it stands ################")
		var totals := _totals()
		for encounter_id in encounter_ids:
			for party_ids in _parties(class_ids):
				if not party_ids.has(&"priest"):
					continue
				for s in SEEDS:
					_measure(party_ids, encounter_id, s, totals, arm)
		_report(totals)
	quit(0)

## Leave-one-out, the only full parties PartySelect can build.
func _parties(class_ids: Array) -> Array:
	var out := []
	for skip in class_ids.size():
		var party := []
		for i in class_ids.size():
			if i != skip:
				party.append(StringName(class_ids[i]))
		out.append(party)
	return out

func _totals() -> Dictionary:
	return {
		"fights": 0,
		"ticks": 0,
		"deaths": 0,
		"player_deaths": 0,
		"heal_events": 0,
		"healed_hp": 0,
		"free": 0,
		"hurt": 0,
		"in_reach": 0,
		"firable": 0,
		"fights_with_a_firable_tick": 0,
		"fights_with_a_heal": 0,
		"wins": 0,
		"unaffordable_reason": {"mana": 0, "cooldown": 0},
		"spent_on": {},
		"heal_by_action": {},
		"spent_mana": {},
		"mana_at_block": 0,
		"mana_max": 0,
		"hurt_out_of_reach": 0,
	}

func _measure(party_ids: Array, encounter_id: StringName, fight_seed: int, t: Dictionary, reserve_arm: int) -> void:
	var party: Array[PawnData] = []
	for cid in party_ids:
		var c := StringName(cid)
		var pawn := PawnFactory.make_starter_pawn(
			c, StringName("%s_%d" % [cid, party.size()]), Registry.get_class_def(c).display_name
		)
		var gated := []
		if reserve_arm == 1:
			gated = [&"priest_smite_nearest"]
		elif reserve_arm == 2:
			gated = [&"priest_smite_nearest", &"priest_ward_default", &"priest_haste_default"]
		for plan in pawn.plans:
			if gated.has(plan.id):
				plan.condition.op = &"self_resource_at_least"
				plan.condition.args = {"amount": 40}
		party.append(pawn)

	var deps := SimDeps.new()
	var state := CombatSim.build(party, Registry.get_encounter(encounter_id), fight_seed, deps)
	var heal := Registry.get_action(HEAL_ID)

	var priests: Array[int] = []
	for u in state.units:
		if u.actions.has(HEAL_ID):
			priests.append(u.id)

	var firable_here := 0
	# tick -> array of priest ids that could have healed on it
	var firable_ticks := {}
	while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
		## +1 because `CombatSim.step` increments the counter before it decides,
		## so a decision read here is stamped on the next tick number.
		var this_tick := state.tick + 1
		for pid in priests:
			var p: CombatUnit = state.units[pid]
			if not p.alive:
				continue
			## The same three gates `_decide_phase` applies before it asks for an
			## intent at all, read rather than re-derived.
			if p.has_status(CG.Status.STUN) or p.intent != null or p.is_busy():
				continue
			t["free"] += 1
			## The neediest living ally, chosen exactly the way both paths choose
			## it: `target_lowest_hp_fraction_ally` and `_lowest_hp_fraction` both
			## take the lowest fraction on the team with no threshold of their
			## own, and the threshold is the *condition* on top. Picking the
			## neediest ally **in reach** instead would answer a question neither
			## path asks -- a plan whose focus is out of range is declined, it
			## does not look for a second-choice patient.
			var neediest: CombatUnit = null
			for a in state.living(p.team):
				if neediest == null or a.hp_fraction() < neediest.hp_fraction():
					neediest = a
			if neediest == null or neediest.hp_fraction() > DefaultBehavior.HEAL_THRESHOLD_FRACTION:
				continue
			t["hurt"] += 1
			if p.position.distance_to(neediest.position) > heal.range_units:
				t["hurt_out_of_reach"] += 1
				continue
			t["in_reach"] += 1
			if not PlanInterpreter.can_afford(state, p, HEAL_ID):
				if p.resource < heal.resource_cost:
					t["unaffordable_reason"]["mana"] += 1
					t["mana_at_block"] += p.resource
					t["mana_max"] = p.resource_max
				else:
					t["unaffordable_reason"]["cooldown"] += 1
				continue
			t["firable"] += 1
			firable_here += 1
			var seen: Array = firable_ticks.get(this_tick, [])
			seen.append(pid)
			firable_ticks[this_tick] = seen
		CombatSim.step(state, deps)

	t["fights"] += 1
	t["ticks"] += state.tick
	if state.outcome == CombatState.Outcome.PLAYER_WIN:
		t["wins"] += 1
	if firable_here > 0:
		t["fights_with_a_firable_tick"] += 1

	var healed_here := 0
	# What was started on each firable tick, by the priest that could have healed.
	for e in state.events:
		if e.kind == CG.EventKind.HEAL:
			t["heal_events"] += 1
			t["healed_hp"] += e.amount
			var hk := String(e.action_id)
			t["heal_by_action"][hk] = int(t["heal_by_action"].get(hk, 0)) + 1
			healed_here += 1
		elif e.kind == CG.EventKind.DEATH:
			t["deaths"] += 1
			if e.target_id >= 0 and state.units[e.target_id].team == CG.Team.PLAYER:
				t["player_deaths"] += 1
		elif e.kind == CG.EventKind.RESOURCE_SPENT:
			if priests.has(e.source_id):
				var sk := String(e.action_id)
				t["spent_mana"][sk] = int(t["spent_mana"].get(sk, 0)) + e.amount
		elif e.kind == CG.EventKind.ACTION_START:
			var owners: Array = firable_ticks.get(e.tick, [])
			if owners.has(e.source_id):
				var label := "%s (%s)" % [
					String(e.action_id),
					"default" if e.source_plan == &"" else String(e.source_plan)
				]
				t["spent_on"][label] = int(t["spent_on"].get(label, 0)) + 1
	if healed_here > 0:
		t["fights_with_a_heal"] += 1

func _report(t: Dictionary) -> void:
	print("")
	print("=== %d fights, %d ticks ===" % [t["fights"], t["ticks"]])
	print("player wins                  : %d of %d" % [t["wins"], t["fights"]])
	print("deaths                       : %d (%d of them player pawns)" % [t["deaths"], t["player_deaths"]])
	print("HEAL events                  : %d, %d hp restored" % [t["heal_events"], t["healed_hp"]])
	var hkeys: Array = t["heal_by_action"].keys()
	hkeys.sort()
	for k in hkeys:
		print("    %-24s : %d" % [k, t["heal_by_action"][k]])
	print("fights with at least one heal: %d of %d" % [t["fights_with_a_heal"], t["fights"]])
	print("")
	print("--- the window, gate by gate (Priest-ticks) ---")
	print("free to act                  : %d" % t["free"])
	print("...with an ally at or below the threshold : %d" % t["hurt"])
	print("......and in reach of Heal   : %d" % t["in_reach"])
	print("      (hurt but out of reach : %d)" % t["hurt_out_of_reach"])
	print(".........and affordable      : %d   <-- FIRABLE" % t["firable"])
	print("      (blocked by Mana       : %d)" % t["unaffordable_reason"]["mana"])
	print("      (blocked by cooldown   : %d)" % t["unaffordable_reason"]["cooldown"])
	print("fights with a firable tick   : %d of %d" % [t["fights_with_a_firable_tick"], t["fights"]])
	print("")
	print("--- where a Priest's Mana went (pool max %d) ---" % t["mana_max"])
	var skeys: Array = t["spent_mana"].keys()
	skeys.sort()
	for k in skeys:
		print("  %-30s : %d" % [k, t["spent_mana"][k]])
	print("  mean Mana held on a Mana-blocked heal tick : %.1f of %d" % [
		float(t["mana_at_block"]) / maxf(1.0, float(t["unaffordable_reason"]["mana"])), t["mana_max"]
	])
	print("")
	print("--- what the Priest started on a firable tick ---")
	var keys: Array = t["spent_on"].keys()
	keys.sort()
	var accounted := 0
	for k in keys:
		print("  %-46s : %d" % [k, t["spent_on"][k]])
		accounted += int(t["spent_on"][k])
	print("  %-46s : %d" % ["(no action started: moved or idled)", int(t["firable"]) - accounted])
