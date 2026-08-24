extends "res://Tests/TestCase.gd"


## Issue 538: a tool that types a seed and never presses Enter is not seeded.

## `PartySelect` connects `text_submitted`, and assigning `.text` emits nothing.
## So the fight seed applied (it is read off the field when Start is pressed)
## while `_roster_seed` kept its `randi()` value and rolled a different party
## every run. Same seed, different fight, in five tools.


func _text(path: String) -> String:
	return FileAccess.get_file_as_string(path)

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

## True when a line writes into the seed field.
func _assigns_a_seed(line: String) -> bool:
	var code := line.strip_edges()
	if code.begins_with("#"):
		return false
	if not code.contains(".text = "):
		return false
	var lower := code.to_lower()
	return lower.contains("_seed_edit") or (lower.contains("seed") and lower.contains("edits["))

func _submits_a_seed(line: String) -> bool:
	var code := line.strip_edges()
	if code.begins_with("#"):
		return false
	return code.contains("text_submitted.emit(")

# ---------------------------------------------------------------------------
# The rule
# ---------------------------------------------------------------------------

## Every write to a seed field must be followed by a submit, close enough that a
## reader sees them as one action.
const SUBMIT_WITHIN := 3

func test_every_tool_that_types_a_seed_also_presses_enter() -> void:
	var offenders: Array[String] = []
	for path in _tool_scripts():
		var lines := _text(path).split("\n")
		for i in lines.size():
			if not _assigns_a_seed(lines[i]):
				continue
			var submitted := false
			for j in range(i + 1, mini(i + 1 + SUBMIT_WITHIN, lines.size())):
				if _submits_a_seed(lines[j]):
					submitted = true
					break
			if not submitted:
				offenders.append("%s:%d  %s" % [path, i + 1, lines[i].strip_edges()])
	assert_eq(offenders, [] as Array[String],
		("these set a seed field and never submit it, so the roster stays random:\n  %s"
			% "\n  ".join(offenders)))

# ---------------------------------------------------------------------------
# The negative half
# ---------------------------------------------------------------------------

## A detector nobody has seen go red is furniture, and both of these are string
## matches, which is the kind that quietly stops matching.
func test_the_guard_fires_on_the_line_every_one_of_them_carried() -> void:
	assert_true(_assigns_a_seed('\tselect._seed_edit.text = "00000001"'),
		"the exact line four tools carried must be flagged")
	assert_true(_assigns_a_seed('\t\tedits[0].text = FIXED_SEED'),
		"PlaytestRun's own version of it must be flagged")
	assert_true(_submits_a_seed('\tselect._seed_edit.text_submitted.emit("00000001")'),
		"the fix must be recognised as a fix")

	assert_false(_assigns_a_seed('\t## select._seed_edit.text = "00000001" in a comment'),
		"a comment must not be flagged")
	assert_false(_assigns_a_seed('\ttitle.text = "UI theming (#115)"'),
		"writing a label must not be flagged")
	assert_false(_submits_a_seed('\t# text_submitted.emit is what a player does'),
		"a comment must not count as a submit")

## The screen still has to be listening for what the tools now emit.
func test_party_select_still_listens_for_text_submitted() -> void:
	var text := _text("res://Scripts/UI/PartySelect.gd")
	assert_true(text.contains("_seed_edit.text_submitted.connect"),
		"the tools press Enter; if the screen stops listening they go quiet, not red")
	assert_true(text.contains("func reroll_from_seed"),
		"submitting is only worth anything because it rerolls the roster")
