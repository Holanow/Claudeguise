extends "res://Tests/TestCase.gd"


## The player, after the gate went 328s to 57s by deleting every test that ran
## one: any test wanting a fight beyond a dummy room or one seed must justify
## it. A rule nobody checks is not a rule. Detail in ENGINEER.md.

## Try Tools/DummyRoom.gd, Tools/StompCheck.gd and the sim fingerprint first.
## Between them they cover almost every reason a test used to run a fight.
## An entry below needs a sentence saying what none of those three can prove.

const ALLOWED := {
	## Names the call inside a string constant in order to search for it, the
	## same way this file does. It runs no fight of its own.
	"res://Tests/test_probe_does_not_perturb.gd":
		"names the call in a const to search for it, does not run one",
}

## `CombatSim.run(` only. `step()` is ONE tick on a hand-built fixture, which
## is a unit test and always was -- forbidding it would delete the cheap tests
## this rule exists to leave alone. Running a fight means running it to its end.
const FIGHT_CALLS := ["CombatSim.run("]

## Only real code counts. A comment naming the call, or a string in a message,
## is not a fight.
func _runs_a_fight(source: String) -> bool:
	for raw in source.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("#"):
			continue
		var code := line
		var hash_at := code.find("#")
		if hash_at >= 0:
			code = code.substr(0, hash_at)
		for call in FIGHT_CALLS:
			if code.contains(call):
				return true
	return false


func test_no_test_runs_a_fight_without_being_named_here() -> void:
	var offenders: Array[String] = []
	var dir := DirAccess.open("res://Tests")
	assert_not_null(dir, "cannot read res://Tests, so this guard would pass by seeing nothing")
	for name in dir.get_files():
		if not name.begins_with("test_") or not name.ends_with(".gd"):
			continue
		var path := "res://Tests/%s" % name
		if name == "test_no_test_runs_a_fight.gd":
			continue  # this file names the call in order to look for it
		if ALLOWED.has(path):
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		if _runs_a_fight(f.get_as_text()):
			offenders.append(name)
	assert_eq(offenders, [],
		("these tests run a real fight and are not named in ALLOWED. Use Tools/DummyRoom.gd, "
		+ "Tools/StompCheck.gd or the sim fingerprint, or add an entry saying what they prove "
		+ "that none of those three can: %s") % str(offenders))


## The guard has to be able to fail, or it is a comment with a test's
## reputation. This board has found seven that could not. The detector is run
## against a source string rather than a file so the proof costs nothing.
func test_the_guard_can_actually_fail() -> void:
	assert_true(_runs_a_fight("\tvar state := CombatSim.run(s)"),
		"a real call must be caught, or the guard above sees nothing and passes forever")
	assert_false(_runs_a_fight("\tCombatSim.step(state, deps)"),
		"one step on a fixture is a unit test, not a fight")
	assert_false(_runs_a_fight("## explains why CombatSim.run( is expensive"),
		"a comment naming the call is not a fight")
	assert_false(_runs_a_fight("\tvar msg := \"see CombatSim.run\""),
		"a string naming the call is not a fight")
