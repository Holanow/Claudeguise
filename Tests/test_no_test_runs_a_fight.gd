extends "res://Tests/TestCase.gd"


## The player, after the gate went from 328s to 57s by deleting every test that
## ran one:
##
## > "any test that wants to run a fight that is more than a dummyroom or more
## > than 1 seed now needs to strongly justify why it needs it"
##
## This is that rule with teeth. A rule nobody checks is not a rule -- the same
## reason `Tools/gate.ps1` counts comment blocks rather than the board asking
## people to keep them short.
##
## **Before adding a name below, try the three cheaper answers first**, because
## between them they cover almost every reason a test used to run a fight:
##
## - **`Tools/DummyRoom.gd`** fires every action at a dummy and checks it does
##   what its own `effects` array declares. That is "the mechanic is reachable",
##   which is what a five-party twenty-seed sweep was usually buying.
## - **`Tools/StompCheck.gd`** runs each room once. A stall reads as a
##   non-contest there.
## - **The `sim` fingerprint** is a stronger determinism proof than any test
##   asserting that two runs of one seed agree.
##
## An entry here needs a sentence saying what the test proves that none of those
## three can, and one seed unless it says why not.

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
