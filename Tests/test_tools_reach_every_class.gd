extends "res://Tests/TestCase.gd"


## No tool may pick its party as a prefix of the class roster.

## The two tools allowed to name a prefix, plus this one, which quotes the
## patterns it looks for. Both reach that line only at four classes or fewer;
## above four they use leave-one-out, which covers everybody.
const ALLOWED := [
	"res://Tools/SampleFights.gd",
	"res://Tools/OutcomeTable.gd",
	"res://Tests/test_tools_reach_every_class.gd",
]

const LEAVE_ONE_OUT := "for skip in class_ids.size()"


func test_no_tool_takes_a_prefix_of_the_roster() -> void:
	# Issue 350: nine tools took the first four of `all_class_ids()`, which
	# sorts the Warrior fifth of five. Every one produced a correct measurement
	# of a game with no Warrior in it, including the shield pixel-diff whose
	# subject is a Warrior ability.
	var offenders: Array[String] = []
	for path in _tool_scripts():
		if ALLOWED.has(path):
			continue
		var line_no := 0
		for line in FileAccess.get_file_as_string(path).split("\n"):
			line_no += 1
			if _takes_a_prefix(line):
				offenders.append("%s:%d  %s" % [path, line_no, line.strip_edges()])
	assert_eq(offenders, [] as Array[String],
		"these pick a party by position in the roster instead of by class id:\n  %s"
			% "\n  ".join(offenders))


func test_the_guard_fires_on_the_lines_it_was_written_for() -> void:
	# The negative half: a detector nobody has seen go red is furniture. Each of
	# these is the exact line one of the seven tools carried.
	assert_true(_takes_a_prefix('\tvar party_ids := class_ids.slice(0, mini(4, class_ids.size()))'),
		"slicing the class list must be flagged")
	assert_true(_takes_a_prefix('\tvar party_ids := Registry.all_class_ids().slice(0, 4)'),
		"slicing the roster inline must be flagged")
	assert_true(_takes_a_prefix('\tfor i in mini(4, class_ids.size()):'),
		"looping the first four class ids must be flagged")
	assert_true(_takes_a_prefix('\t\tcards[i].toggled.emit(true)'),
		"selecting a party card by index must be flagged")

	assert_false(_takes_a_prefix('\tfor party_ids in ScreenSweepScript.sweep_parties(class_ids):'),
		"the covering partition is the fix, not the defect")
	assert_false(_takes_a_prefix('\t\tby_id[id].toggled.emit(true)'),
		"selecting a card by its class id must pass")
	assert_false(_takes_a_prefix('\tfor i in party_ids.size():'),
		"walking a party that was chosen by id must pass")
	assert_false(_takes_a_prefix('## takes class_ids.slice(0, mini(4, class_ids.size())), said a comment'),
		"a comment must not be flagged")


func test_the_allowlisted_tools_still_cover_every_class() -> void:
	# The allowlist stands on those two using leave-one-out above four classes.
	# If that branch ever goes, the allowlist is hiding a real prefix.
	for path in ["res://Tools/SampleFights.gd", "res://Tools/OutcomeTable.gd"]:
		var text := FileAccess.get_file_as_string(path)
		assert_true(text.contains(LEAVE_ONE_OUT),
			"%s no longer uses leave-one-out; it must not stay on the allowlist" % path)


func _tool_scripts() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open("res://Tools")
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".gd"):
			out.append("res://Tools/%s" % f)
	out.sort()
	return out


## True when a line chooses a party by position in the roster rather than by id.
func _takes_a_prefix(line: String) -> bool:
	var code := line.strip_edges()
	if code.begins_with("#"):
		return false
	if code.contains("slice(0") and code.contains("class_ids"):
		return true
	if code.contains("mini(4") and (code.contains("class_ids") or code.contains("cards")):
		return true
	if code.contains("cards[") and code.contains("toggled"):
		return true
	return false
