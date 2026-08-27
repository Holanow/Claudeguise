extends SceneTree

## Issue 641: does the plan form of the fallback decide exactly what
## `DefaultBehavior` decides? Every planless decision, field by field.
##
## The #628 pattern the issue names: keep both, diff them, delete both after.
## Arm A is `DefaultBehavior.decide`. Arm B is whatever `_arm_b` calls. Run
## `-- perturb` to point arm B at a deliberately wrong answer and confirm this
## tool can fail; a differ that has never fired is not evidence.

## SAMPLES BEFORE `step()`, per ENGINEER.md, and restores everything both arms
## touch: `state.rng.state` and every unit's `focus_id`. `PlanInterpreter.decide`
## writes `focus_id` and `DefaultBehavior.decide` can draw from `state.rng`.

const SEEDS := 6

## The same corpus shape `SampleFights` uses, so the thing being proved is the
## thing the acceptance instrument measures.
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("verify"):
		_verify()
		return
	var perturb := args.has("perturb")
	var class_ids := Registry.all_class_ids()
	var checked := 0
	var differed := 0
	var relabelled := 0
	var shown := 0
	for encounter_id in Registry.all_encounter_ids():
		var encounter := Registry.get_encounter(encounter_id)
		for party_ids in _parties(class_ids):
			for s in SEEDS:
				var party: Array[PawnData] = []
				for cid in party_ids:
					party.append(PawnFactory.make_starter_pawn(cid, StringName("%s_p" % cid),
						Registry.get_class_def(cid).display_name))
				var state := CombatSim.build(party, encounter, s, SimDeps.new())
				while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
					for unit in state.units:
						if not _reaches_the_fallback(state, unit):
							continue
						checked += 1
						var a := _run(state, unit, false)
						var b := _run(state, unit, true) if not perturb else _wrong()
						if a != null and b != null and a.source_plan != b.source_plan:
							relabelled += 1
						if _same(a, b):
							continue
						differed += 1
						if shown < 10:
							shown += 1
							print("  DIFF %s seed %d tick %d unit %d (%s)" % [
								encounter_id, s, state.tick, unit.id, unit.display_name])
							print("    A %s" % _show(a))
							print("    B %s" % _show(b))
					CombatSim.step(state)
	print("FallbackDiff: %d planless decisions checked, %d differed" % [checked, differed])
	## Issue 641 on purpose: the fallback now names the row it ran, so
	## `source_plan` goes from "" to a readable id. That is the payoff, not a
	## difference, so it is counted apart from the ones that matter.
	print("FallbackDiff: %d relabelled (source_plan only, intended)" % relabelled)
	quit(1 if (differed > 0) != perturb else 0)

## Arm A, or arm B. Snapshot and restore around every call, so asking costs
## nothing: the rng stream and every focus_id come back exactly as they were.
static func _wrong() -> Intent:
	return Intent.idle()

func _run(state: CombatState, unit: CombatUnit, wrong: bool) -> Intent:
	var rng_state := state.rng.state
	var focus: Array[int] = []
	for u in state.units:
		focus.append(u.focus_id)
	var out: Intent = _arm_b(state, unit) if wrong else DefaultBehavior.decide(state, unit)
	state.rng.state = rng_state
	for i in state.units.size():
		state.units[i].focus_id = focus[i]
	return out

## The plan form. `-- perturb` swaps it for a deliberately wrong answer, which
## is what proves the identity number means anything.
func _arm_b(state: CombatState, unit: CombatUnit) -> Intent:
	return FallbackPlan.decide(state, unit)

## `CombatSim._decide_phase`'s own guard chain, read-only. `_compelling_taunter`
## is NOT called: it removes the status and emits an event when the taunter is
## dead, so a probe that called it would perturb the fight it is measuring.
func _reaches_the_fallback(state: CombatState, unit: CombatUnit) -> bool:
	if not unit.alive:
		return false
	if unit.has_status(CG.Status.STUN):
		return false
	if unit.intent != null or unit.is_busy():
		return false
	if unit.has_status(CG.Status.TAUNTED):
		var t := state.unit(int(unit.status_magnitude.get(CG.Status.TAUNTED, -1.0)))
		if t != null and t.alive:
			return false
	if unit.pawn == null:
		return true
	var rng_state := state.rng.state
	var focus: Array[int] = []
	for u in state.units:
		focus.append(u.focus_id)
	var planned := PlanInterpreter.decide(state, unit)
	state.rng.state = rng_state
	for i in state.units.size():
		state.units[i].focus_id = focus[i]
	return planned == null

static func _same(a: Intent, b: Intent) -> bool:
	if a == null or b == null:
		return a == b
	return a.kind == b.kind \
		and a.action_id == b.action_id \
		and a.target_id == b.target_id \
		and a.destination.is_equal_approx(b.destination)

static func _show(i: Intent) -> String:
	if i == null:
		return "null"
	return "kind=%d action=%s target=%d dest=%s plan=%s" % [
		i.kind, i.action_id, i.target_id, i.destination, i.source_plan]

## The step almost nobody does: every fight again with the probe removed, and
## nothing may have moved. Asking is only free if it is measured to be.
func _verify() -> void:
	var perturbed := 0
	var fights := 0
	var class_ids := Registry.all_class_ids()
	for encounter_id in Registry.all_encounter_ids():
		var encounter := Registry.get_encounter(encounter_id)
		for party_ids in _parties(class_ids):
			for s in SEEDS:
				fights += 1
				var clean := CombatSim.build(_party(party_ids), encounter, s, SimDeps.new())
				CombatSim.run(clean)
				var probed := CombatSim.build(_party(party_ids), encounter, s, SimDeps.new())
				while probed.outcome == CombatState.Outcome.UNRESOLVED and probed.tick < CG.MAX_TICKS:
					for unit in probed.units:
						if _reaches_the_fallback(probed, unit):
							_run(probed, unit, false)
					CombatSim.step(probed)
				if clean.outcome != probed.outcome or clean.tick != probed.tick 						or clean.events.size() != probed.events.size():
					perturbed += 1
	print("FallbackDiff: %d perturbed of %d fights" % [perturbed, fights])
	quit(1 if perturbed > 0 else 0)

func _party(party_ids: Array) -> Array[PawnData]:
	var out: Array[PawnData] = []
	for cid in party_ids:
		out.append(PawnFactory.make_starter_pawn(cid, StringName("%s_p" % cid),
			Registry.get_class_def(cid).display_name))
	return out

func _parties(class_ids: Array) -> Array:
	var out := []
	## Leave-one-out, named by class id rather than by position: a prefix of the
	## roster silently stops covering whichever class sorts last.
	for skip in class_ids:
		var party := []
		for cid in class_ids:
			if cid != skip:
				party.append(cid)
		out.append(party)
	return out
