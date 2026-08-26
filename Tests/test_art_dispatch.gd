extends "res://Tests/TestCase.gd"


## Nothing may reach a part PNG except through `UnitArt.part_texture`.

const SKIP_DIRS := [".godot", ".git", "addons"]

## The only file allowed to name a unit art path, plus this one, which quotes the
## patterns it looks for.
const ALLOWED := ["res://Scripts/Art/UnitArt.gd", "res://Tests/test_art_dispatch.gd"]

const PATH_MARKERS := ["res://Assets/Units", "UnitArt.PARTS_DIR"]


func test_only_unitart_names_a_unit_art_path() -> void:
	# A part is loaded once and shared by every recipe that names it, on both
	# sides. Code that builds the path itself gets a second copy of a texture the
	# cache already holds, which reads as working and quietly undoes the sharing
	# that makes a hundred units cost twenty-seven textures.
	var offenders: Array[String] = []
	for path in _scripts("res://"):
		if ALLOWED.has(path):
			continue
		var text := FileAccess.get_file_as_string(path)
		var line_no := 0
		for line in text.split("\n"):
			line_no += 1
			if _names_a_unit_png(line):
				offenders.append("%s:%d  %s" % [path, line_no, line.strip_edges()])
	assert_eq(offenders, [] as Array[String],
		"these load unit art without going through UnitArt.texture_for:\n  %s" % "\n  ".join(offenders))


func test_the_guard_fires_on_a_line_that_bypasses_the_dispatch() -> void:
	# The negative half: a detector nobody has seen go red is furniture.
	assert_true(_names_a_unit_png('\tvar tex := load("res://Assets/Units/brute.png")'),
		"a direct load of a unit PNG must be flagged")
	assert_true(_names_a_unit_png('\tvar p := "%s/%s.png" % [UnitArt.PARTS_DIR, part]'),
		"building the path from PARTS_DIR must be flagged")
	assert_false(_names_a_unit_png('\tvar r := FileAccess.get_file_as_string("res://Assets/Units/README.md")'),
		"the README is not art and must not be flagged")
	assert_false(_names_a_unit_png('## a PNG in res://Assets/Units/parts/hat.png, said a comment'),
		"a comment must not be flagged")
	assert_false(_names_a_unit_png('\tvar dir := DirAccess.open(UnitArt.PARTS_DIR)'),
		"listing the directory is not loading a sprite")


## True when a line of GDScript names a part sprite file outside the dispatch.
func _names_a_unit_png(line: String) -> bool:
	var code := _strip_comment(line)
	if not code.contains(".png"):
		return false
	for marker in PATH_MARKERS:
		if code.contains(marker):
			return true
	return false


## The line with any trailing `#` comment removed, quotes respected.
func _strip_comment(line: String) -> String:
	var quote := ""
	for i in line.length():
		var c := line[i]
		if quote != "":
			if c == quote:
				quote = ""
		elif c == "\"" or c == "'":
			quote = c
		elif c == "#":
			return line.substr(0, i)
	return line


func _scripts(root: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	for d in dir.get_directories():
		if SKIP_DIRS.has(d):
			continue
		out.append_array(_scripts(root.path_join(d)))
	for f in dir.get_files():
		if f.ends_with(".gd"):
			out.append(root.path_join(f))
	out.sort()
	return out
