extends "res://Tests/TestCase.gd"


## Issue 529: the byte-identical proof has to stay impossible to take wrongly.

const TOOL := "res://Tools/SampleFights.gd"
const SCRIPT := "res://Tools/sim_fingerprint.ps1"
const RECORD := "res://Tools/sim_fingerprint.txt"
const GATE := "res://Tools/gate.ps1"

## The only lines allowed to call `print` are the one that maintains the digest
## and the two the checker reads back.
const PRINTERS := [
	"\tprint(line)",
	"\tprint(\"lines: %d\" % _lines.size())",
	"\tprint(\"fingerprint: %s\" % body.sha256_text())",
]

## Everything under `Scripts/` that the simulation never reads. A new directory
## goes in the fingerprint's source set unless it is one of these.
## Issue 570: `Audio` joined these. `SoundBank.gd` is read by `BattleView` and
## by nothing below the presentation layer, so hashing it made a view-only edit
## pay for a full `SampleFights` run.
const VIEW_ONLY := ["UI", "Art", "Audio"]

## The simulation layers, walked directly by the guard below.
const SIM_DIRS := ["Combat", "Content", "Core", "Floor", "Plans", "Rooms"]

## How many view `class_name` globals the scan must find before it is believed.
## A scan that silently returned nothing would make the guard pass forever,
## which is #536's empty-capture failure wearing a different hat.
const MIN_VIEW_TYPES := 20


func _text(path: String) -> String:
	return FileAccess.get_file_as_string(path)

## Every `.gd` under `dir_path`, including subdirectories. Issue 579: the old
## scan used `get_files()`, which does not recurse, so all of
## `Scripts/Content/Modules` -- every class, action, item, enemy and room in the
## game -- was invisible to it.
func _gd_files(dir_path: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	for sub in d.get_directories():
		_gd_files("%s/%s" % [dir_path, sub], out)
	for file in d.get_files():
		if file.ends_with(".gd"):
			out.append("%s/%s" % [dir_path, file])

## Every `class_name` declared under the view-only directories, read from the
## source rather than listed here. Issue 579: there are 41, and a hand-written
## copy would agree with itself forever while the code moved.
func _view_type_names() -> Array[String]:
	var names: Array[String] = []
	var re := RegEx.new()
	re.compile("^class_name\\s+(\\w+)")
	for sub in VIEW_ONLY:
		var files: Array[String] = []
		_gd_files("res://Scripts/%s" % sub, files)
		for path in files:
			for line in _text(path).split("\n"):
				var m := re.search(line.strip_edges())
				if m != null:
					names.append(m.get_string(1))
	names.sort()
	return names

## The file with its comment lines removed. Issue 579: seven doc comments in the
## simulation name a view type -- `BattleView hands state.terrain to ArenaFloor`
## is one -- and a guard that fires on those is wrong on day one and teaches
## everyone to ignore it inside a week.
func _code_only(text: String) -> String:
	var kept := PackedStringArray()
	for line in text.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		kept.append(line)
	return "\n".join(kept)

# ---------------------------------------------------------------------------
# The digest must cover every line the tool prints
# ---------------------------------------------------------------------------

## A line printed around `_say` would be in the report and not in the digest,
## so two runs could differ visibly and hash the same.
func test_sample_fights_prints_only_through_the_buffer() -> void:
	var offenders: Array[String] = []
	var line_no := 0
	for line in _text(TOOL).split("\n"):
		line_no += 1
		var trimmed := line.rstrip(" \t\r")
		if not trimmed.strip_edges().begins_with("print("):
			continue
		if PRINTERS.has(trimmed):
			continue
		offenders.append("%d  %s" % [line_no, trimmed.strip_edges()])
	assert_eq(offenders, [] as Array[String],
		"these print outside the buffer the fingerprint is taken over:\n  %s"
			% "\n  ".join(offenders))

## The negative half. A detector nobody has seen go red is furniture, and this
## one is a string match, which is the kind that quietly stops matching.
func test_the_print_guard_fires_on_a_line_that_would_skip_the_buffer() -> void:
	assert_false(PRINTERS.has("\tprint(\"party: \" + _short(party_ids))"),
		"a stray print must not be mistaken for one of the two allowed lines")
	assert_true(_text(TOOL).contains("func _say("), "the buffer must still exist")
	assert_true(_text(TOOL).contains("sha256_text()"),
		"the tool must still hash its own output rather than leaving it to a pipeline")

## The digest is printed, and it is printed LAST and outside itself.
func test_the_fingerprint_is_not_part_of_what_it_covers() -> void:
	var text := _text(TOOL)
	assert_true(text.contains("print(\"fingerprint: %s\" % body.sha256_text())"),
		"the digest line must be a bare print, or it would hash itself")
	assert_false(text.contains("_say(\"fingerprint"),
		"the digest must not go through the buffer it is taken over")

## Issue 536: a blind reviewer ran the documented pipeline and got a zero-line
## file on both arms, hashing to e3b0c442 -- the empty string -- and reading as
## "byte-identical". The checker refuses a capture too short to be a run, and it
## can only do that if the tool says how much it printed.
func test_the_tool_reports_how_many_lines_it_printed() -> void:
	assert_true(_text(TOOL).contains("print(\"lines: %d\" % _lines.size())"),
		"without this the checker cannot tell a real run from an empty capture")
	assert_true(_text(SCRIPT).contains("MIN_REPORT_LINES"),
		"the checker must refuse a short capture rather than hashing it")
	assert_true(_text(SCRIPT).contains("e3b0c442"),
		"the empty-string digest is named, so a reader knows what is being refused")

# ---------------------------------------------------------------------------
# The recording, and the gate that reads it
# ---------------------------------------------------------------------------

func test_the_recording_carries_both_hashes() -> void:
	assert_true(FileAccess.file_exists(RECORD), "%s is missing" % RECORD)
	var source := ""
	var output := ""
	for line in _text(RECORD).split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("source: "):
			source = trimmed.substr(8)
		elif trimmed.begins_with("output: "):
			output = trimmed.substr(8)
	assert_eq(source.length(), 64, "the source hash must be a sha256")
	assert_eq(output.length(), 64, "the output hash must be a sha256")
	assert_true(source.is_valid_hex_number(), "source is not hex: %s" % source)
	assert_true(output.is_valid_hex_number(), "output is not hex: %s" % output)

## A verdict that stops being called is a verdict nobody can fail.
func test_the_gate_still_runs_the_fingerprint() -> void:
	assert_true(_text(GATE).contains("sim_fingerprint.ps1"),
		"gate.ps1 no longer runs the fingerprint; the proof is optional again")

# ---------------------------------------------------------------------------
# The source set must not rot as the codebase grows
# ---------------------------------------------------------------------------

## Issue 529's real long-term risk. The fast path says "the simulation's source
## did not move", and a directory that is in neither list makes that a lie the
## moment somebody adds one.
func test_every_script_directory_is_either_fingerprinted_or_view_only() -> void:
	var text := _text(SCRIPT)
	var dir := DirAccess.open("res://Scripts")
	assert_true(dir != null, "res://Scripts is unreadable")
	var missing: Array[String] = []
	for name in dir.get_directories():
		if VIEW_ONLY.has(name):
			continue
		if not text.contains("'%s'" % name):
			missing.append(name)
	assert_eq(missing, [] as Array[String],
		("Scripts/%s is in neither the fingerprint's source set nor VIEW_ONLY, so a "
		+ "change there would read as 'the simulation did not move'") % ", ".join(missing))

## And the other direction: the view-only claim is what lets the fast path skip
## the run, so it has to keep being true.
func test_the_simulation_does_not_read_the_view() -> void:
	var type_names := _view_type_names()
	var matchers := {}
	for name in type_names:
		var re := RegEx.new()
		re.compile("\\b%s\\b" % name)
		matchers[name] = re
	var offenders: Array[String] = []
	for sub in SIM_DIRS:
		var files: Array[String] = []
		_gd_files("res://Scripts/%s" % sub, files)
		for path in files:
			var code := _code_only(_text(path))
			var flagged := false
			for view_dir in VIEW_ONLY:
				if code.contains("res://Scripts/%s/" % view_dir):
					offenders.append("%s (loads Scripts/%s)" % [path, view_dir])
					flagged = true
					break
			if flagged:
				continue
			for name in type_names:
				if matchers[name].search(code) != null:
					offenders.append("%s (names %s)" % [path, name])
					break
	assert_eq(offenders, [] as Array[String],
		("these simulation files read view code, so 'the sim source did not move' "
		+ "no longer proves the output did not:\n  %s") % "\n  ".join(offenders))


## The derivation has to actually find the types, or the guard above checks
## nothing and passes on anything. Issue 579: 41 of them at the time of writing.
func test_the_view_type_list_is_derived_and_not_empty() -> void:
	var names := _view_type_names()
	assert_true(names.size() >= MIN_VIEW_TYPES,
		("only %d view class_names were found under %s; the scan is broken and the guard "
		+ "above would pass on anything") % [names.size(), str(VIEW_ONLY)])
	assert_true(names.has("SoundBank"), "SoundBank is the #570 case and must be in the derived set")
	assert_true(names.has("BattleView"), "BattleView is the most obvious view type and must be found")


## And the comment stripper, because the guard's correctness rests on it: seven
## real doc comments in the simulation name a view type.
func test_comments_are_not_searched_for_view_types() -> void:
	var stripped := _code_only("## BattleView hands terrain to ArenaFloor\nvar x := 1\n")
	assert_false(stripped.contains("BattleView"), "a doc comment must not reach the scan")
	assert_true(stripped.contains("var x := 1"), "the stripper must keep the code")
	assert_false(_code_only("\t## `ArenaFloor` at fight start\n").contains("ArenaFloor"),
		"an indented doc comment must not reach the scan either")
