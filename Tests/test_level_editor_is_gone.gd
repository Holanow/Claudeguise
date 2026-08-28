extends "res://Tests/TestCase.gd"


## Issue 720. Rooms became `.tscn` in #689 and the level editor kept writing
## JSON with no reader; the player: "now that levels are scenes we can just
## ditch the editor." This keeps it deleted.

const GONE_FILES := [
	"res://Scripts/UI/LevelEditorView.gd",
	"res://Scripts/UI/LevelEditorCanvas.gd",
	"res://Scripts/UI/LevelEditorOverlay.gd",
	"res://Scenes/LevelEditor.tscn",
]

const GONE_SYMBOLS := [
	"LevelEditorView", "LevelEditorCanvas", "LevelEditorOverlay",
	"SCENE_LEVEL_EDITOR", "show_level_editor", "level_editor_requested",
]

## Real code only. A comment recalling the editor is history and a quoted
## sample line is a fixture -- same split `test_registry_is_gone.gd` draws.
func _uses_a_gone_symbol(source: String) -> bool:
	for raw in source.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("#"):
			continue
		var code := line
		var hash_at := code.find("#")
		if hash_at >= 0:
			code = code.substr(0, hash_at)
		var stripped := _stripped_of_strings(code)
		for symbol in GONE_SYMBOLS:
			if _contains_word(stripped, symbol):
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

## Whole-word match, so e.g. `LevelEditorViewSomething` cannot false-positive
## and a bare `Registry.` -style dot-call is not required for a class name.
static func _contains_word(text: String, word: String) -> bool:
	var re := RegEx.new()
	re.compile("\\b%s\\b" % word)
	return re.search(text) != null


func test_the_files_are_gone() -> void:
	var still_here: Array[String] = []
	for path in GONE_FILES:
		if FileAccess.file_exists(path):
			still_here.append(path)
	assert_eq(still_here, [], "the level editor is back: %s" % str(still_here))


func test_nothing_references_it() -> void:
	var offenders: Array[String] = []
	for dir_path in ["res://Scripts", "res://Tests", "res://Tools"]:
		_scan(dir_path, offenders)
	assert_eq(offenders, [],
		"these reference a deleted level editor symbol: %s" % str(offenders))

func _scan(dir_path: String, offenders: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for name in dir.get_files():
		if not name.ends_with(".gd"):
			continue
		var path := "%s/%s" % [dir_path, name]
		if path.ends_with("test_level_editor_is_gone.gd"):
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null and _uses_a_gone_symbol(f.get_as_text()):
			offenders.append(path)
	for sub in dir.get_directories():
		_scan("%s/%s" % [dir_path, sub], offenders)


## The guard has to be able to fail. Seven on this board could not.
func test_the_detector_can_actually_fail() -> void:
	assert_true(_uses_a_gone_symbol("\tvar v := LevelEditorView.create()"),
		"a real reference must be caught, or the scan above passes forever")
	assert_true(_uses_a_gone_symbol("\tscreen.level_editor_requested.connect(f)"),
		"a signal connection must be caught too")
	assert_false(_uses_a_gone_symbol("## Deleted the level editor in #720"),
		"a comment recalling the deleted editor is history, not a reference")
	assert_false(_uses_a_gone_symbol("\tassert_true(_takes('var v := LevelEditorView.create()'))"),
		"a sample line held in a string is a fixture, not a reference")
