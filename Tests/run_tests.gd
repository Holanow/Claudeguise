extends SceneTree


## The whole gate. Run it with:

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
		# Typed to match `collected`. An untyped Array assigned back into a
		# typed one is a hard crash in GDScript, not a warning -- which is
		# exactly what this did on its first real use, by swift, on the very
		# run the standing policy tells everyone to use.
		var kept: Array[String] = []
		for path in collected:
			if String(path).findn(filter) != -1:
				kept.append(String(path))
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

			## A test that finishes having recorded no assertion at all either
			## crashed part-way or asserts nothing, and **both used to count as
			## a pass.**
			##
			## `Object.call` on a method that raises a runtime error aborts the
			## method and returns normally. `case.failures` stays empty because
			## the method died before it could assert, `_tests_run` increments,
			## and the gate prints PASS. wren hit this by deleting a function
			## while a test still called it: the only symptom anywhere was the
			## assertion count moving 4399 -> 4398.
			if case.assertions == 0:
				var vacuous := "%s::%s  ran and recorded no assertion -- it crashed part-way, or it asserts nothing" % [path.get_file(), name]
				_test_failures.append(vacuous)
				printerr("FAIL  %s" % vacuous)

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
