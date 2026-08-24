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
const VIEW_ONLY := ["UI", "Art"]


func _text(path: String) -> String:
	return FileAccess.get_file_as_string(path)

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
	var offenders: Array[String] = []
	for sub in ["Combat", "Content", "Core", "Plans", "Floor", "Audio"]:
		var dir := DirAccess.open("res://Scripts/%s" % sub)
		if dir == null:
			continue
		for file in dir.get_files():
			if not file.ends_with(".gd"):
				continue
			var path := "res://Scripts/%s/%s" % [sub, file]
			var text := _text(path)
			if text.contains("res://Scripts/UI/") or text.contains("res://Scripts/Art/"):
				offenders.append(path)
	assert_eq(offenders, [] as Array[String],
		("these simulation files load view code, so 'the sim source did not move' "
		+ "no longer proves the output did not:\n  %s") % "\n  ".join(offenders))
