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
		for hit in _prefix_offenders(FileAccess.get_file_as_string(path)):
			offenders.append("%s:%s" % [path, hit])
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


func test_the_guard_fires_on_indexing_the_roster_by_a_loop_variable() -> void:
	# Issue 816: `for k in n: class_ids[k]` is a prefix, matched none of the line
	# shapes, and the guard was green over a live one in PartySizeLethality.
	assert_false(_prefix_offenders("for k in n:\n\tvar c := StringName(class_ids[k])").is_empty(),
		"indexing the roster by a loop variable with a short bound must be flagged")
	assert_false(_prefix_offenders("for i in 4:\n\tparty.append(class_ids[i])").is_empty(),
		"a literal loop bound over the roster must be flagged")
	assert_false(_prefix_offenders("\tparty.append(class_ids[0])").is_empty(),
		"a literal roster index must be flagged")
	assert_false(_prefix_offenders("\tparty.append(ClassLibrary.all_ids()[0])").is_empty(),
		"indexing the roster inline must be flagged")

	assert_eq(_prefix_offenders("for skip in class_ids.size():\n\tfor i in class_ids.size():\n\t\tif i != skip:\n\t\t\tparty.append(class_ids[i])"),
		[] as Array[String], "leave-one-out walks the whole roster and must pass")
	assert_eq(_prefix_offenders("for skip in class_ids.size():\n\tprint(String(class_ids[skip]))"),
		[] as Array[String], "naming the left-out class must pass")
	assert_eq(_prefix_offenders("\twhile taken < class_ids.size():\n\t\tparty.append(class_ids[taken])"),
		[] as Array[String], "the covering sweep partition is the fix, not the defect")
	assert_eq(_prefix_offenders("\tcfg.encounter_id = RoomLibrary.all_ids()[0]"),
		[] as Array[String], "the room roster is not the class roster")
	assert_false(_prefix_offenders("for i in class_ids.size():\n\tparty.append(class_ids[i])\nfor i in 4:\n\tparty.append(class_ids[i])").is_empty(),
		"a covering loop earlier in the file must not excuse a later prefix on the same name")
	assert_false(_prefix_offenders("for i in class_ids.size() - 1:\n\tparty.append(class_ids[i])").is_empty(),
		"a bound one short of the roster is issue 350 written arithmetically")
	assert_eq(_prefix_offenders("## for k in n: class_ids[k], said a comment"),
		[] as Array[String], "a comment must not be flagged")


func test_the_allowlisted_tools_still_cover_every_class() -> void:
	# The allowlist stands on those two using leave-one-out above four classes.
	# If that branch ever goes, the allowlist is hiding a real prefix.
	for path in ["res://Tools/SampleFights.gd", "res://Tools/OutcomeTable.gd"]:
		var text := FileAccess.get_file_as_string(path)
		assert_true(text.contains(LEAVE_ONE_OUT),
			"%s no longer uses leave-one-out; it must not stay on the allowlist" % path)


func _tool_scripts() -> Array[String]:
	return ToolScripts.under("res://Tools")


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


## Every offending line in one file's text, as "line_no  code".
func _prefix_offenders(text: String) -> Array[String]:
	var out: Array[String] = []
	var covering := {}
	var line_no := 0
	for line in text.split("\n"):
		line_no += 1
		var code := line.strip_edges()
		if code.begins_with("#"):
			continue
		for v in _rebound_vars(code):
			covering.erase(v)
		for v in _covering_vars(code):
			covering[v] = true
		if _takes_a_prefix(line) or _indexes_roster_by_position(code, covering):
			out.append("%d  %s" % [line_no, code])
	return out


## Every variable this line gives a new bound to, covering or not, so an
## earlier covering loop cannot excuse a later prefix on the same name.
func _rebound_vars(code: String) -> Array[String]:
	var out: Array[String] = []
	for pattern in ["for\\s+([A-Za-z_]\\w*)\\s+in\\s+", "while\\s+([A-Za-z_]\\w*)\\s*<"]:
		var re := RegEx.create_from_string(pattern)
		for m in re.search_all(code):
			out.append(m.get_string(1))
	return out


## Index variables shown to walk the whole roster, from `for i in
## class_ids.size()` and from `while taken < class_ids.size()`.
func _covering_vars(code: String) -> Array[String]:
	var out: Array[String] = []
	for pattern in [
		"for\\s+([A-Za-z_]\\w*)\\s+in\\s+(?:range\\()?class_ids\\.size\\(\\)\\)?\\s*:",
		"([A-Za-z_]\\w*)\\s*<=?\\s*class_ids\\.size\\(\\)(?!\\s*[-+])",
	]:
		var re := RegEx.create_from_string(pattern)
		for m in re.search_all(code):
			out.append(m.get_string(1))
	return out


## True when a line reads the class roster at a position never shown to walk
## all of it, which is a prefix whatever the loop bound happens to be.
func _indexes_roster_by_position(code: String, covering: Dictionary) -> bool:
	var inline := RegEx.create_from_string("(ClassLibrary\\.all_ids|all_class_ids)\\(\\)\\[")
	if inline.search(code) != null:
		return true
	var re := RegEx.create_from_string("class_ids\\[([A-Za-z_]\\w*|\\d+)\\]")
	for m in re.search_all(code):
		if not covering.has(m.get_string(1)):
			return true
	return false
