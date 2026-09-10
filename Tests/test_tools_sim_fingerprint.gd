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


# ---------------------------------------------------------------------------
# The instrument's own `Tools/` files: a list, and a guard that enforces it
# ---------------------------------------------------------------------------

## How many `class_name` globals the `Tools/` scan must find before the guard
## below is believed. A scan that silently returned nothing would make it pass
## on anything, which is #536's empty capture wearing a third hat.
const MIN_TOOL_TYPES := 5

## `$INSTRUMENT_FILES` read out of the checker itself, so this file cannot hold
## a second copy that agrees with itself forever while the script moves.
func _instrument_files() -> Array[String]:
	var text := _text(SCRIPT)
	var out: Array[String] = []
	var entry := RegEx.new()
	entry.compile("\\$INSTRUMENT_ENTRY\\s*=\\s*'([^']+)'")
	var m := entry.search(text)
	if m != null:
		out.append(m.get_string(1))
	var list := RegEx.new()
	list.compile("(?s)\\$INSTRUMENT_FILES\\s*=\\s*@\\((.*?)\\)")
	var lm := list.search(text)
	if lm != null:
		var quoted := RegEx.new()
		quoted.compile("'([^']+)'")
		for q in quoted.search_all(lm.get_string(1)):
			if not out.has(q.get_string(1)):
				out.append(q.get_string(1))
	return out

## Every `class_name` declared anywhere under `Tools/`, mapped to the file that
## declares it. Recursive, unlike the `Tools/` scans in the other test files.
func _tool_type_files() -> Dictionary:
	var out := {}
	var re := RegEx.new()
	re.compile("^class_name\\s+(\\w+)")
	var files: Array[String] = []
	_gd_files("res://Tools", files)
	for path in files:
		for line in _text(path).split("\n"):
			var m := re.search(line.strip_edges())
			if m != null:
				out[m.get_string(1)] = path.substr(6)
	return out

## Every way `code` reaches a `Tools/` file that `hashed` does not cover.
func _reach_offenders(rel: String, code: String, hashed: Array[String],
		types: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var path_re := RegEx.new()
	path_re.compile("res://(Tools/[A-Za-z0-9_/]+\\.gd)")
	for m in path_re.search_all(code):
		var hit := m.get_string(1)
		if not hashed.has(hit):
			out.append("%s loads res://%s" % [rel, hit])
	for name in types:
		if hashed.has(types[name]):
			continue
		var re := RegEx.new()
		re.compile("\\b%s\\b" % name)
		if re.search(code) != null:
			out.append("%s names %s, declared by %s" % [rel, name, types[name]])
	return out

## Issue 837: the instrument's `Tools/` files were one hardcoded name, which is
## the shape that lost `.tres` in #633 and `.tscn` in #680 one level down.
func test_the_instrument_reaches_no_tools_file_outside_the_hashed_set() -> void:
	var hashed := _instrument_files()
	assert_true(hashed.has("Tools/SampleFights.gd"),
		"the checker no longer names SampleFights as instrument source: %s" % str(hashed))
	var types := _tool_type_files()
	var offenders: Array[String] = []
	for rel in hashed:
		var code := _code_only(_text("res://" + rel))
		offenders.append_array(_reach_offenders(rel, code, hashed, types))
	assert_eq(offenders, [] as Array[String],
		("these Tools/ files decide the fingerprint's output and are not hashed with it, so "
		+ "editing one reads as 'the simulation did not move'. Add each to $INSTRUMENT_FILES "
		+ "in Tools/sim_fingerprint.ps1, then re-record:\n  %s") % "\n  ".join(offenders))

## The negative half, both directions. This guard passes trivially while the set
## holds one file, so it is exactly the kind nobody would ever watch go red.
func test_the_reach_guard_fires_on_a_helper_outside_the_set() -> void:
	var one: Array[String] = ["Tools/SampleFights.gd"]
	var both: Array[String] = ["Tools/SampleFights.gd", "Tools/PartySpec.gd"]
	var types := {"PartySpec": "Tools/PartySpec.gd"}
	assert_eq(_reach_offenders("Tools/SampleFights.gd", "var x := PartySpec.new()", one, types).size(),
		1, "a class_name declared by an unhashed Tools/ file must be flagged")
	assert_eq(_reach_offenders("Tools/SampleFights.gd",
		"var x := preload(\"res://Tools/Helper.gd\")", one, types).size(),
		1, "a res:// load of an unhashed Tools/ file must be flagged")
	assert_eq(_reach_offenders("Tools/SampleFights.gd", "var x := PartySpec.new()", both, types),
		[] as Array[String], "a helper that IS in the hashed set must not be flagged")
	assert_eq(_reach_offenders("Tools/SampleFights.gd", "var x := PartySpecial.new()", one, types),
		[] as Array[String], "a longer name that merely begins with one must not match")
	assert_false(_code_only("## PartySpec is what the sweep builds\n").contains("PartySpec"),
		"a doc comment naming a Tools/ type must not reach the scan")

## The derivation has to find the types, or the guard above checks nothing.
func test_the_tools_type_scan_is_derived_and_not_empty() -> void:
	var types := _tool_type_files()
	assert_true(types.size() >= MIN_TOOL_TYPES,
		("only %d class_name globals were found under Tools/; the scan is broken and the "
		+ "guard above would pass on anything") % types.size())
	assert_true(types.has("PartySpec"), "PartySpec is declared in Tools/ and must be found")

## The list is only a rule while every site reads it instead of the path.
func test_the_checker_names_its_instrument_file_exactly_once() -> void:
	var text := _text(SCRIPT)
	assert_true(_instrument_files().size() > 0,
		"$INSTRUMENT_FILES could not be read out of the checker, so the guard reads nothing")
	assert_eq(text.count("Tools/SampleFights.gd"), 1,
		"the instrument's path is written more than once; the copies are what drift apart")
	assert_true(text.count("$INSTRUMENT_FILES") >= 3,
		"$INSTRUMENT_FILES must be defined and then read by both Get-SourceHash and Test-SourceDirty")

## The third way one script reaches another, and the guard above cannot see it.
func test_no_autoload_points_into_tools() -> void:
	assert_false(_text("res://project.godot").contains("res://Tools/"),
		"project.godot references res://Tools/; an autoload would reach the instrument invisibly")
