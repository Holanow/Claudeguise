extends "res://Tests/TestCase.gd"


## Issue 658. `Registry` was a forwarding layer over the libraries and a second
## place content could be looked up. It is deleted; this keeps it deleted.

const GONE := "res://Scripts/Content/Registry.gd"

## Real code only. A comment recalling what Registry used to do is history and
## a quoted one is a fixture -- `test_tools_reach_every_class.gd` carries the
## exact line a deleted tool once had, and that is a record, not a call.
func _calls_registry(source: String) -> bool:
	for raw in source.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("#"):
			continue
		var code := line
		var hash_at := code.find("#")
		if hash_at >= 0:
			code = code.substr(0, hash_at)
		if _stripped_of_strings(code).contains("Registry."):
			return true
	return false

## Everything between quotes removed, so a sample line held in a string reads
## as the data it is.
static func _stripped_of_strings(code: String) -> String:
	var out := ""
	var quote := ""
	for i in code.length():
		var c := code[i]
		if quote != "":
			if c == quote:
				quote = ""
			continue
		if c == "\"" or c == "'":
			quote = c
			continue
		out += c
	return out


func test_the_file_is_gone() -> void:
	assert_false(FileAccess.file_exists(GONE),
		"Registry.gd is back. Content lookups belong on the libraries.")


func test_nothing_calls_it() -> void:
	var offenders: Array[String] = []
	for dir_path in ["res://Scripts", "res://Tests", "res://Tools"]:
		_scan(dir_path, offenders)
	assert_eq(offenders, [],
		"these call a Registry that does not exist: %s" % str(offenders))

func _scan(dir_path: String, offenders: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for name in dir.get_files():
		if not name.ends_with(".gd"):
			continue
		var path := "%s/%s" % [dir_path, name]
		if path.ends_with("test_registry_is_gone.gd"):
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null and _calls_registry(f.get_as_text()):
			offenders.append(path)
	for sub in dir.get_directories():
		_scan("%s/%s" % [dir_path, sub], offenders)


## The guard has to be able to fail. Seven on this board could not.
func test_the_detector_can_actually_fail() -> void:
	assert_true(_calls_registry("\tvar r := Registry.get_room(&\"a\")"),
		"a real call must be caught, or the scan above passes forever")
	assert_false(_calls_registry("## Moved off Registry.get_action in #658"),
		"a comment recalling the old name is history, not a call")
	assert_false(_calls_registry("	assert_true(_takes('\tvar a := Registry.all_class_ids()'))"),
		"a sample line held in a string is a fixture, not a call")
