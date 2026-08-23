extends "res://Tests/TestCase.gd"


## No tool may press a button whose words no screen carries.

## Where a button's words can come from: a scene file, or a string literal in
## the code that builds the screen.
const TEXT_DIRS := ["res://Scripts/UI", "res://Scenes"]

const TOOLS_DIR := "res://Tools"


func test_every_button_a_tool_presses_still_exists() -> void:
	# Issue 371: #351 deleted the "Inspect classes" button and two capture tools
	# went on pressing it, then returned silently when the press failed. Both
	# reported success for weeks with the plan-editor captures never taken.
	var known := _button_words()
	var offenders: Array[String] = []
	for path in _tool_scripts():
		for pressed in _pressed_prefixes(path):
			if not _matches_any(pressed["prefix"], known):
				offenders.append("%s:%d  presses '%s', which no screen says" % [
					path, pressed["line"], pressed["prefix"]])
	assert_eq(offenders, [] as Array[String],
		"these press a button that does not exist:\n  %s" % "\n  ".join(offenders))


func test_the_guard_fires_on_the_button_that_was_deleted() -> void:
	# The negative half: the exact line both tools carried, and the comment in
	# `InspectPanel.gd` that still quotes the dead label, which must not count
	# as the button existing.
	var known := _button_words()
	assert_false(_matches_any("inspect classes", known),
		"the deleted 'Inspect classes' button must not be found")
	assert_false(_matches_any("equip pawns", known),
		"the deleted 'Equip pawns' button must not be found")
	assert_true(_matches_any("start fight", known),
		"a button that does exist must be found")

	assert_eq(_prefixes_in('	if not _press_named("inspect classes"):', 1),
		[{"prefix": "inspect classes", "line": 1}],
		"a press call must be read out of a line")
	assert_eq(_prefixes_in('## the button that used to open this said "Inspect classes"', 1),
		[], "a comment must not look like a press call")


## The words on every button the game can build, lowercased.
func _button_words() -> Array[String]:
	var out: Array[String] = []
	for dir in TEXT_DIRS:
		for path in _files_under(dir, [".gd", ".tscn"]):
			for line in FileAccess.get_file_as_string(path).split("\n"):
				if _is_comment(line):
					continue
				for literal in _literals(line):
					out.append(literal.to_lower())
	return out


## True when the prefix a tool presses starts the words of a real button.
func _matches_any(prefix: String, known: Array[String]) -> bool:
	for text in known:
		if text.begins_with(prefix.to_lower()):
			return true
	return false


func _is_comment(line: String) -> bool:
	return line.strip_edges().begins_with("#")


func _literals(line: String) -> Array[String]:
	var out: Array[String] = []
	var parts := line.split("\"")
	var i := 1
	while i < parts.size():
		out.append(parts[i])
		i += 2
	return out


func _pressed_prefixes(path: String) -> Array:
	var out := []
	var line_no := 0
	for line in FileAccess.get_file_as_string(path).split("\n"):
		line_no += 1
		out.append_array(_prefixes_in(line, line_no))
	return out


## A `_press("...")` or `_press_named("...")` call, which is how every tool in
## this repo names the control it wants.
func _prefixes_in(line: String, line_no: int) -> Array:
	if _is_comment(line):
		return []
	var out := []
	for call: String in ["_press(\"", "_press_named(\""]:
		var at := line.find(call)
		while at != -1:
			var start := at + call.length()
			var end := line.find("\"", start)
			if end == -1:
				break
			out.append({"prefix": line.substr(start, end - start), "line": line_no})
			at = line.find(call, end)
	return out


func _tool_scripts() -> Array[String]:
	return _files_under(TOOLS_DIR, [".gd"])


func _files_under(dir: String, suffixes: Array) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for name in d.get_files():
		for suffix in suffixes:
			if name.ends_with(suffix):
				out.append("%s/%s" % [dir, name])
				break
	for sub in d.get_directories():
		out.append_array(_files_under("%s/%s" % [dir, sub], suffixes))
	return out
