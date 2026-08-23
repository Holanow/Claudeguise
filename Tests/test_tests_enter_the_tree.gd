extends "res://Tests/TestCase.gd"

## A scene built with `instantiate()` and never entered into a tree never gets
## its children's `_ready`, so the test asserts against a half-built object.
## Issue 370 converted twenty files; this stops the twenty-first arriving
## unnoticed, which it already did once from a branch that predated the change.

const TEST_DIR := "res://Tests"

func test_no_test_instantiates_a_scene_without_entering_the_tree() -> void:
	var offenders: Array[String] = []
	var dir := DirAccess.open(TEST_DIR)
	assert_true(dir != null, "cannot open %s" % TEST_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("test_") and entry.ends_with(".gd"):
			var text := FileAccess.get_file_as_string(TEST_DIR.path_join(entry))
			var line_no := 0
			for line in text.split("\n"):
				line_no += 1
				var stripped := String(line).strip_edges()
				if stripped.begins_with("#"):
					continue
				if stripped.contains(".instantiate()") and not stripped.contains("in_tree("):
					offenders.append("%s:%d" % [entry, line_no])
		entry = dir.get_next()
	dir.list_dir_end()
	assert_true(offenders.is_empty(),
		"these instantiate a scene without entering it: %s -- use in_tree()" % ", ".join(offenders))
