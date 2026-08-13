extends SceneTree

const TestCase := preload("res://Tests/TestCase.gd")

## The whole gate. Run it with:
##
##   godot --headless --path . --script res://Tests/run_tests.gd
##
## or through Tools/gate.ps1, which is the same command with the Godot path
## resolved. Exit code 0 means every check passed. Anything else means stop.
##
## MANAGER-OWNED. Nobody else edits this file.
##
## Three checks, printed separately, because a summary line that folds them
## together hides the one that matters:
##
##   1. parse     every .gd in the repository loads
##   2. discovery every test_*.gd is somewhere the runner collects it
##   3. tests     every test method passes
##
## Check 2 exists because a test file the runner never opens produces no output
## and is indistinguishable from a passing one. It has caught this before.

const TEST_DIR := "res://Tests"
const SKIP_DIRS := [".godot", ".git", "addons"]

var _parse_failures: Array[String] = []
var _misplaced_tests: Array[String] = []
var _test_failures: Array[String] = []
var _tests_run := 0
var _assertions := 0
var _self_path := "res://Tests/run_tests.gd"

## An optional substring filter, for iterating on one file without paying for the
## whole suite:
##
##     godot --headless --path . --script res://Tests/run_tests.gd -- projectiles
##
## **Parse and discovery always run over everything, and that is deliberate.** A
## missing symbol in Scripts/Core is a parse-time failure in Godot that takes
## down every script transitively preloading it, so a filtered run that skipped
## the parse check could report green while the real gate is broken. Only the
## test-execution phase narrows.
##
## Added after swift was told to use a filter argument that did not exist. They
## checked the command instead of trusting it, found `_init` always walked the
## whole tree regardless, and said so rather than running something that looked
## like it worked. The suggestion was mine and so was the gap.
static func _filter_from_args() -> String:
	for a in OS.get_cmdline_user_args():
		var s := String(a).strip_edges()
		if s != "":
			return s
	return ""

func _init() -> void:
	var scripts := _walk("res://")
	scripts.sort()

	_check_parse(scripts)
	var collected := _check_discovery(scripts)

	var filter := _filter_from_args()
	if filter != "":
		var kept: Array = []
		for path in collected:
			if String(path).findn(filter) != -1:
				kept.append(path)
		print("")
		print("  FILTERED to \"%s\": %d of %d test files. This is NOT the gate." % [
			filter, kept.size(), collected.size()
		])
		collected = kept

	_run_tests(collected)

	print("")
	print("  parse      %s   (%d scripts)" % [_verdict(_parse_failures.is_empty()), scripts.size()])
	print("  discovery  %s   (%d test files)" % [_verdict(_misplaced_tests.is_empty()), collected.size()])
	print("  tests      %s   (%d tests, %d assertions)" % [_verdict(_test_failures.is_empty()), _tests_run, _assertions])
	print("")

	var ok := _parse_failures.is_empty() and _misplaced_tests.is_empty() and _test_failures.is_empty()
	if ok and _tests_run == 0:
		print("REFUSING: the gate collected zero tests. A gate that runs nothing")
		print("is not a gate. Either add a test or fix the discovery paths.")
		quit(1)
		return
	quit(0 if ok else 1)

func _verdict(ok: bool) -> String:
	return "pass" if ok else "FAIL"

## `load()` alone is not enough here, and the difference is not cosmetic. A .gd
## file with a type error prints three SCRIPT ERROR lines and then `load()`
## hands back a non-null GDScript anyway, so a null check reports "parse pass"
## next to a wall of parse errors. That is the worst possible gate output: it
## trains everyone to read the summary and ignore the errors above it. Caught by
## deliberately breaking a file and watching this check pass.
##
## `reload()` returns the actual compile result, so it is the thing to ask.
func _check_parse(scripts: Array[String]) -> void:
	for path in scripts:
		var res := load(path)
		if res == null:
			_parse_failures.append(path)
			printerr("PARSE FAIL  %s  (did not load at all)" % path)
			continue
		var script := res as GDScript
		if script == null:
			continue
		# Reloading the script that is currently executing always reports an
		# error, so the runner would fail itself on every clean run. It parsed:
		# it is running.
		if path == _self_path:
			continue
		if script.reload() != OK:
			_parse_failures.append(path)
			printerr("PARSE FAIL  %s" % path)

func _check_discovery(scripts: Array[String]) -> Array[String]:
	var collected: Array[String] = []
	for path in scripts:
		if not path.get_file().begins_with("test_"):
			continue
		if path.begins_with(TEST_DIR + "/"):
			collected.append(path)
		else:
			_misplaced_tests.append(path)
			printerr("NOT COLLECTED  %s" % path)
			printerr("               named test_*.gd but outside %s, so it never runs." % TEST_DIR)
	return collected

func _run_tests(collected: Array[String]) -> void:
	for path in collected:
		var script := load(path)
		if script == null:
			continue
		var instance = script.new()
		if not (instance is TestCase):
			_test_failures.append("%s: does not extend TestCase" % path)
			printerr("BAD TEST  %s does not extend TestCase" % path)
			continue
		for m in instance.get_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			var case: TestCase = script.new()
			case.setup()
			case.call(name)
			case.teardown()
			_tests_run += 1
			_assertions += case.assertions
			if not case.failures.is_empty():
				for f in case.failures:
					var line := "%s::%s  %s" % [path.get_file(), name, f]
					_test_failures.append(line)
					printerr("FAIL  %s" % line)

func _walk(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			if not SKIP_DIRS.has(entry):
				out.append_array(_walk(full))
		elif entry.ends_with(".gd"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return out
