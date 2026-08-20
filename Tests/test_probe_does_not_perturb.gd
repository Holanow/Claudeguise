extends "res://Tests/TestCase.gd"


## Issue 329: a tool that steps a fight may not ask `decide` what a unit would do.

const TOOLS_DIR := "res://Tools"

## Either of these draws from `state.rng` inside `DefaultBehavior._choose_target`.
const OBSERVER_CALLS := ["DefaultBehavior.decide(", "PlanInterpreter.decide("]

## A file assigning this is supplying the sim's own decide phase, not observing it.
const SIM_HOOK := "plan_decide"

## Naming one of these is what makes a state a live fight rather than a fixture.
const STEP_CALLS := ["CombatSim.step(", "CombatSim.run("]


func test_no_tool_that_steps_a_fight_observes_it_with_decide() -> void:
	var offenders: Array[String] = []
	for path in _tool_scripts():
		var text := FileAccess.get_file_as_string(path)
		for line_no in _offending_lines(text):
			offenders.append("%s:%d" % [path, line_no])
	assert_eq(offenders, [] as Array[String],
		("these step a fight and also call decide on it, which consumes the fight's own\n"
		+ "  RNG and measures a fight the probe created. Read positions across a step\n"
		+ "  instead, the way Tools/KiteProbe.gd does:\n  %s") % "\n  ".join(offenders))


func test_the_detector_fires_on_a_probe_that_calls_decide() -> void:
	var perturbing := "\tCombatSim.step(state)\n\tvar i := DefaultBehavior.decide(state, u)\n"
	assert_eq(_offending_lines(perturbing).size(), 1,
		"a probe that steps a fight and then asks decide must be flagged")

	var fixture := "\tvar state := CombatState.new(0)\n\tvar i := DefaultBehavior.decide(state, u)\n"
	assert_eq(_offending_lines(fixture), [] as Array[int],
		"a static fixture that never steps is not observing a live fight")

	var hook := "\tdeps.plan_decide = func(s, u): return PlanInterpreter.decide(s, u)\n\tCombatSim.run(state, deps)\n"
	assert_eq(_offending_lines(hook), [] as Array[int],
		"supplying the sim's decide phase is the decide phase, not an observation of it")

	var commented := "\tCombatSim.step(state)\n\t# never call DefaultBehavior.decide( here\n"
	assert_eq(_offending_lines(commented), [] as Array[int],
		"a comment naming the call must not be flagged")


## The guard's premise, asserted rather than assumed: if `decide` stops drawing
## from `state.rng` this goes red, and the rule above can be deleted with it.
func test_observing_with_decide_really_does_change_the_fight() -> void:
	var plain := _run_fight(false)
	var observed := _run_fight(true)
	assert_ne(observed, plain,
		("calling decide on a stepped fight no longer changes it. Check whether\n"
		+ "  DefaultBehavior._choose_target still draws from state.rng; if it does not,\n"
		+ "  Tests/test_probe_does_not_perturb.gd is obsolete and should be deleted."))
	assert_eq(_run_fight(false), plain, "the unobserved fight is deterministic")


func test_there_are_tools_to_guard() -> void:
	assert_true(_tool_scripts().size() > 10, "no tools found under %s; this guard guards nothing" % TOOLS_DIR)


## The 1-based line numbers in `text` that observe a stepped fight with `decide`.
func _offending_lines(text: String) -> Array[int]:
	var out: Array[int] = []
	var code_lines: Array[String] = []
	for line in text.split("\n"):
		code_lines.append(_strip_comment(line))
	var joined := "\n".join(code_lines)
	if not _contains_any(joined, STEP_CALLS):
		return out
	if joined.contains(SIM_HOOK):
		return out
	for i in code_lines.size():
		if _contains_any(code_lines[i], OBSERVER_CALLS):
			out.append(i + 1)
	return out


func _contains_any(text: String, needles: Array) -> bool:
	for n in needles:
		if text.contains(n):
			return true
	return false


## The line with any trailing `#` comment removed, quotes respected.
func _strip_comment(line: String) -> String:
	var quote := ""
	for i in line.length():
		var c := line[i]
		if quote != "":
			if c == quote:
				quote = ""
		elif c == "\"" or c == "'":
			quote = c
		elif c == "#":
			return line.substr(0, i)
	return line


func _tool_scripts() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(TOOLS_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".gd"):
			out.append(TOOLS_DIR.path_join(f))
	out.sort()
	return out


## One real fight, summarised. `observe` adds exactly what a naive probe does.
func _run_fight(observe: bool) -> String:
	var enc := Registry.get_encounter(&"floor1_room1")
	var pawns: Array[PawnData] = [
		PawnFactory.make_starter_pawn(&"warrior", &"p0", "P0"),
		PawnFactory.make_starter_pawn(&"priest", &"p1", "P1"),
	]
	var state := CombatSim.build(pawns, enc, 7, SimDeps.new())
	while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
		CombatSim.step(state)
		if observe:
			for u in state.units:
				if u.alive:
					DefaultBehavior.decide(state, u)
	var parts: Array[String] = ["tick=%d outcome=%d" % [state.tick, state.outcome]]
	for u in state.units:
		parts.append("%d:%d" % [u.id, u.hp])
	return " ".join(parts)
