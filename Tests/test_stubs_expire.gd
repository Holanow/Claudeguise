extends "res://Tests/TestCase.gd"


## This file exists to delete itself.
##
## There are no tests of the simulation, the plan interpreter or the battle
## screen yet, because none of them are built. A comment saying so would rot:
## the code gets written, the comment stays, and the gate quietly stops covering
## the most important part of the project while still printing "pass".
##
## So instead of a comment, an assertion that the *reason* for the gap is still
## true. When a session implements its stub, this goes red and names what to do
## about it. That is the intended lifecycle, not a break.
##
## ENGINEER.md covers this case explicitly: delete the one line for the stub you
## just implemented, and say so in your pull request. Do not delete the others.

const STUB_MARKER := "is not implemented yet"

const STUBS := {
	"res://Scripts/Combat/CombatSim.gd": "wren, issue 1",
	"res://Scripts/Plans/PlanInterpreter.gd": "teal, issue 2",
	"res://Scripts/Plans/DefaultBehavior.gd": "teal, issue 2",
	"res://Scripts/Content/Balance.gd": "teal, issue 2",
	"res://Scripts/UI/Main.gd": "pike, issue 3",
	"res://Scripts/UI/BattleView.gd": "pike, issue 3",
	"res://Scripts/UI/PartySelect.gd": "pike, issue 3",
	"res://Scripts/UI/CombatLogView.gd": "pike, issue 3",
	"res://Scripts/UI/UnitView.gd": "pike, issue 3",
}


func test_every_stub_is_still_a_stub() -> void:
	var paths := STUBS.keys()
	paths.sort()
	for path in paths:
		var text := FileAccess.get_file_as_string(path)
		if text == "":
			fail("%s is missing entirely. It is part of the frozen skeleton." % path)
			continue
		if text.contains(STUB_MARKER):
			continue
		fail(
			("%s is implemented now (%s). Two things to do: delete its line from " +
			"Tests/test_stubs_expire.gd, and add real tests for it. This " +
			"assertion is the only thing standing in for that coverage.")
			% [path, STUBS[path]]
		)


func test_the_stub_list_is_not_empty() -> void:
	# When the last entry goes, this fires once, says the file has done its job,
	# and the whole file gets deleted. Without it the file would end its life as
	# an empty dictionary that passes forever and means nothing.
	assert_false(
		STUBS.is_empty(),
		"every stub is implemented. Delete Tests/test_stubs_expire.gd; it is finished."
	)
