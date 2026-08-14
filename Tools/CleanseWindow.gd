extends SceneTree

## Is there anything for a cleanse to do, and does the mechanism fire in a real
## fight?
##
##   godot --headless --path . --script res://Tools/CleanseWindow.gd
##
## Written by swift for issue 87. Not part of the game and not part of the gate.
##
## Two questions, in this order, because the second is worthless if the first
## answers no.
##
## **1. How wide is the window?** Across every party a player can build, every
## encounter, and six seeds, how many ticks does a living player unit actually
## carry a harmful status, and which statuses are they? finch's own finding on
## #86 is the reason this is measured rather than reasoned about:
## `geyser_scald` never fired in 210 real fights partly because its condition
## window was *empty*, not merely narrow, and nobody could tell from reading it.
## A cleanse aimed at a window that never opens is the same failure again.
##
## **2. Does the mechanism reach a real fight?** The same fights are run again
## with one probe action handed to every Geysermancer: a free, ally-targeted
## action identical to a plausible content cleanse, injected through
## `SimDeps.action_lookup` and appended to the unit's own action list. Nothing
## in `Scripts/Content` is touched -- the real action is finch's half, and this
## is here so the simulation half can be verified without waiting on it.
##
## What this deliberately does NOT prove: that finch's action, with finch's
## cost and finch's plan, will fire. This probe hands the class a free action
## and lets `DefaultBehavior` reach for it. A real cleanse has to get past the
## preset plan ladder first, and the note printed at the end says what that
## costs.

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")
const SimDeps := preload("res://Scripts/Combat/SimDeps.gd")
const ActionDef := preload("res://Scripts/Core/ActionDef.gd")
const Plan := preload("res://Scripts/Core/Plan.gd")
const PlanBlock := preload("res://Scripts/Core/PlanBlock.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")

const SEEDS := 6
const PROBE_ACTION_ID := &"probe_cleanse"

## How the probe cleanse is made available to the class.
enum { ROUTE_NONE, ROUTE_ACTION_ONLY, ROUTE_PLAN }

func _init() -> void:
	var class_ids := Registry.all_class_ids()
	var encounter_ids := Registry.all_encounter_ids()
	if class_ids.size() < 5 or encounter_ids.is_empty():
		printerr("not enough content registered to sample")
		quit(1)
		return

	print("")
	print("=== 1. THE WINDOW: harmful statuses on player units, real fights ===")
	var window := _totals()
	for encounter_id in encounter_ids:
		for party_ids in _parties(class_ids):
			for s in SEEDS:
				_measure(party_ids, encounter_id, s, window, ROUTE_NONE)
	_report_window(window)

	print("")
	print("=== 2. ACTION ONLY: the cleanse in starting_actions and nowhere else ===")
	print("The route a content cleanse takes if it is added to the class's action")
	print("list without a plan: DefaultBehavior._first_heal has to reach for it.")
	var by_action := _totals()
	for encounter_id in encounter_ids:
		for party_ids in _parties(class_ids):
			for s in SEEDS:
				_measure(party_ids, encounter_id, s, by_action, ROUTE_ACTION_ONLY)
	_report_firing(by_action)

	print("")
	print("=== 3. ACTION PLUS A PRESET PLAN, below the existing Mana ladder ===")
	print("condition `always`, blocks [target_lowest_hp_fraction_ally,")
	print("use_action], third in the list -- the slot a real cleanse would take.")
	var by_plan := _totals()
	for encounter_id in encounter_ids:
		for party_ids in _parties(class_ids):
			for s in SEEDS:
				_measure(party_ids, encounter_id, s, by_plan, ROUTE_PLAN)
	_report_firing(by_plan)
	print("")
	print("Every strip above is a STATUS_EXPIRED carrying a source_id and an")
	print("action_id, which is what separates it from a status running out.")
	print("")
	print("=== 4. WHAT THE LOG SAYS, first real cleanse in the run ===")
	if _sample_lines.is_empty():
		print("no cleanse landed on another unit; showing a self-cleanse instead")
		for line in _self_lines:
			print(line)
	else:
		for line in _sample_lines:
			print(line)
	quit(0)

## Leave-one-out, the only full parties PartySelect can build, in card order.
func _parties(class_ids: Array) -> Array:
	var out := []
	for skip in class_ids.size():
		var party := []
		for i in class_ids.size():
			if i != skip:
				party.append(class_ids[i])
		out.append(party)
	return out

func _totals() -> Dictionary:
	return {
		"fights": 0,
		"ticks": 0,
		"afflicted_ticks": 0,
		"fights_afflicted": 0,
		"per_status": {},
		"cleansed": 0,
		"stripped": 0,
		"fights_cleansed": 0,
		"geyser_in_range_ticks": 0,
		"geyser_fires": {},
	}

## A free, ally-targeted cleanse. `heals` is what makes DefaultBehavior aim it
## at an ally at all (`_first_heal`), and the 0 power keeps it from being a
## heal in disguise: the only thing this action does is strip.
func _probe_action() -> ActionDef:
	var a := ActionDef.new()
	a.id = PROBE_ACTION_ID
	a.display_name = "Probe Cleanse"
	a.range_units = 200.0
	a.wind_up_ticks = 8
	a.recover_ticks = 10
	a.power_scale = 0.0
	a.resource_cost = 0
	a.heals = true
	a.cleanses_harmful = true
	a.damage_type = CG.DamageType.WATER
	return a

## A third preset plan in the slot a real one would occupy: below the Blast
## and Scald ladder, so it takes only the ticks those two already fall through
## on. `always` because no condition op asks "does an ally carry a harmful
## status" -- that gap is the finding, not an oversight here.
func _probe_plan() -> Plan:
	var cond := PlanBlock.new()
	cond.kind = PlanBlock.Kind.CONDITION
	cond.op = &"always"

	var targeting := PlanBlock.new()
	targeting.kind = PlanBlock.Kind.TARGETING
	targeting.op = &"target_lowest_hp_fraction_ally"

	var action := PlanBlock.new()
	action.kind = PlanBlock.Kind.ACTION
	action.op = &"use_action"
	action.args = {"action_id": PROBE_ACTION_ID}

	var p := Plan.new()
	p.id = &"probe_cleanse_plan"
	p.display_name = "Probe cleanse"
	p.condition = cond
	p.blocks = [targeting, action]
	return p

func _is_geysermancer(u: CombatUnit) -> bool:
	return u.pawn != null and u.pawn.pawn_class != null and u.pawn.pawn_class.id == &"geysermancer"

func _measure(party_ids: Array, encounter_id: StringName, fight_seed: int, totals: Dictionary, route: int) -> void:
	var party: Array[PawnData] = []
	for cid in party_ids:
		var c := StringName(cid)
		var pawn := PawnFactory.make_starter_pawn(
			c, StringName("%s_%d" % [cid, party.size()]), Registry.get_class_def(c).display_name
		)
		if route == ROUTE_PLAN and c == &"geysermancer":
			pawn.plans.append(_probe_plan())
		party.append(pawn)

	var deps := SimDeps.new()
	if route != ROUTE_NONE:
		var probe := _probe_action()
		deps.action_lookup = func(id: StringName):
			if id == PROBE_ACTION_ID:
				return probe
			return Registry.get_action(id)

	var state := CombatSim.build(party, Registry.get_encounter(encounter_id), fight_seed, deps)
	if route != ROUTE_NONE:
		for u in state.units:
			if _is_geysermancer(u):
				# First, so `_first_heal` finds it before anything else.
				u.actions.insert(0, PROBE_ACTION_ID)

	var afflicted_ticks := 0
	var in_range_ticks := 0
	while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
		CombatSim.step(state, deps)
		var afflicted: Array[CombatUnit] = []
		for u in state.living(CG.Team.PLAYER):
			for s in u.statuses.keys():
				if CG.is_harmful(s):
					afflicted.append(u)
					totals["per_status"][s] = int(totals["per_status"].get(s, 0)) + 1
					break
		if not afflicted.is_empty():
			afflicted_ticks += 1
			if _a_geysermancer_could_reach(state, afflicted):
				in_range_ticks += 1

	totals["fights"] += 1
	totals["ticks"] += state.tick
	totals["afflicted_ticks"] += afflicted_ticks
	totals["geyser_in_range_ticks"] += in_range_ticks
	if afflicted_ticks > 0:
		totals["fights_afflicted"] += 1

	var geysermancers := {}
	for u in state.units:
		if _is_geysermancer(u):
			geysermancers[u.id] = true

	var stripped := 0
	var on_someone_else := false
	for e in state.events:
		# A cleanse names its caster and its action; an ordinary expiry
		# carries source_id -1 and no action id.
		if e.kind == CG.EventKind.STATUS_EXPIRED and e.source_id != -1:
			stripped += 1
			if e.source_id != e.target_id:
				on_someone_else = true
		elif e.kind == CG.EventKind.ACTION_FIRE:
			if e.action_id == PROBE_ACTION_ID:
				totals["cleansed"] += 1
			if geysermancers.has(e.source_id):
				var fires: Dictionary = totals["geyser_fires"]
				fires[e.action_id] = int(fires.get(e.action_id, 0)) + 1
	if stripped > 0:
		totals["stripped"] += stripped
		totals["fights_cleansed"] += 1
		# A cleanse on somebody else is the case issue 87 asks for; a
		# Geysermancer scrubbing its own poison is the same mechanism but a
		# weaker demonstration, so it is only kept if nothing better turns up.
		if on_someone_else and _sample_lines.is_empty():
			_sample_lines = _capture_log(state, party_ids, encounter_id, fight_seed, true)
		elif _self_lines.is_empty():
			_self_lines = _capture_log(state, party_ids, encounter_id, fight_seed, false)

## The window a *Geysermancer* has, which is narrower than the window the party
## has: it needs to be alive and inside its own 200-unit band of the afflicted
## ally. Measured rather than assumed, because "somebody is poisoned" and "the
## support can do something about it" are different numbers.
func _a_geysermancer_could_reach(state: CombatState, afflicted: Array[CombatUnit]) -> bool:
	for u in state.living(CG.Team.PLAYER):
		if u.pawn == null or u.pawn.pawn_class == null or u.pawn.pawn_class.id != &"geysermancer":
			continue
		for a in afflicted:
			if a.id != u.id and u.position.distance_to(a.position) <= 200.0:
				return true
	return false

func _report_window(t: Dictionary) -> void:
	print("fights                   : %d" % t["fights"])
	print("ticks simulated          : %d" % t["ticks"])
	print("fights with an affliction: %d" % t["fights_afflicted"])
	print("ticks with an affliction : %d (%.1f%% of all ticks)" % [
		t["afflicted_ticks"], 100.0 * float(t["afflicted_ticks"]) / maxf(1.0, float(t["ticks"]))
	])
	print("...and a Geysermancer in range of it: %d (%.1f%% of all ticks)" % [
		t["geyser_in_range_ticks"],
		100.0 * float(t["geyser_in_range_ticks"]) / maxf(1.0, float(t["ticks"]))
	])
	var per: Dictionary = t["per_status"]
	var keys: Array = per.keys()
	keys.sort()
	for s in keys:
		print("  unit-ticks of %-8s : %d" % [String(CG.Status.keys()[s]), per[s]])

## The log lines a player would actually read around the first real cleanse
## the probe produces. Rendered through `CombatLogView.line_for_event`, the
## same formatting the battle screen uses, rather than a string built here:
## "the log says so" is a claim about that function's output, and a sentence
## composed in this file would only ever agree with itself.
var _sample_lines: Array[String] = []
var _self_lines: Array[String] = []

func _capture_log(state: CombatState, party_ids: Array, encounter_id: StringName, fight_seed: int, cross_unit: bool) -> Array[String]:
	var log_view = load("res://Scripts/UI/CombatLogView.gd").new()
	var first := -1
	for e in state.events:
		if e.kind == CG.EventKind.STATUS_EXPIRED and e.source_id != -1:
			if cross_unit and e.source_id == e.target_id:
				continue
			first = e.tick
			break
	var out: Array[String] = []
	out.append("party %s, %s, seed %d" % [
		", ".join(PackedStringArray(party_ids)), encounter_id, fight_seed
	])
	for e in state.events:
		if e.tick < first - 2 or e.tick > first + 1:
			continue
		var line: String = log_view.line_for_event(state, e)
		if line == "":
			continue
		var mark := "  "
		if e.kind == CG.EventKind.STATUS_EXPIRED and e.source_id != -1:
			mark = "->"
		out.append("%s t%-5d %s" % [mark, e.tick, line])
	log_view.free()
	return out

## What the Geysermancers in these fights actually did, which is the only way
## to tell a cleanse that never got a turn from one that got a turn and did
## nothing. Both look identical in a strip count of zero.
func _report_firing(t: Dictionary) -> void:
	print("cleanses that fired      : %d" % t["cleansed"])
	print("statuses stripped        : %d" % t["stripped"])
	print("fights with a cleanse    : %d of %d" % [t["fights_cleansed"], t["fights"]])
	var fires: Dictionary = t["geyser_fires"]
	var ids: Array = fires.keys()
	ids.sort()
	print("what Geysermancers fired, all %d fights:" % t["fights"])
	for id in ids:
		print("  %-16s : %d" % [String(id), fires[id]])
