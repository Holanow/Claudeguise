extends "res://Tests/TestCase.gd"


## Issue 864: the walk five Tools/ guards share must reach a subdirectory.

const ROOT := "user://test_tool_scripts_scan"


func setup() -> void:
	_remove()
	DirAccess.make_dir_recursive_absolute(ROOT + "/nested/deeper")
	_write(ROOT + "/Top.gd")
	_write(ROOT + "/nested/Middle.gd")
	_write(ROOT + "/nested/deeper/Bottom.gd")
	_write(ROOT + "/nested/shot.png")


func teardown() -> void:
	_remove()
	super.teardown()


func test_a_script_in_a_subdirectory_is_seen() -> void:
	assert_eq(ToolScripts.under(ROOT), [
		ROOT + "/Top.gd",
		ROOT + "/nested/Middle.gd",
		ROOT + "/nested/deeper/Bottom.gd",
	], "a .gd below the top level must be found, sorted, at its full path")


func test_only_scripts_are_returned() -> void:
	assert_false(ToolScripts.under(ROOT).has(ROOT + "/nested/shot.png"),
		"Tools/preview holds PNGs; only .gd files are tool scripts")


func test_a_missing_root_is_empty_rather_than_a_crash() -> void:
	assert_eq(ToolScripts.under("user://no_such_dir_864"), [] as Array[String],
		"a root that does not exist yields nothing")


func _write(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("extends Node\n")
	f.close()


func _remove() -> void:
	for path in [
		ROOT + "/nested/deeper/Bottom.gd", ROOT + "/nested/Middle.gd",
		ROOT + "/nested/shot.png", ROOT + "/Top.gd",
		ROOT + "/nested/deeper", ROOT + "/nested", ROOT,
	]:
		DirAccess.remove_absolute(path)
