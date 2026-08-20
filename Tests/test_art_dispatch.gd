extends "res://Tests/TestCase.gd"


## Nothing may reach a unit's PNG except through `UnitArt.texture_for`.

const SKIP_DIRS := [".godot", ".git", "addons"]

## The only file allowed to name a unit art path, plus this one, which quotes the
## patterns it looks for.
const ALLOWED := ["res://Scripts/Art/UnitArt.gd", "res://Tests/test_art_dispatch.gd"]

const PATH_MARKERS := ["res://Assets/Units", "UnitArt.ART_DIR"]


func test_only_unitart_names_a_unit_art_path() -> void:
	# `texture_for` tries `<id>.<side>.png` before `<id>.png`, and six of the
	# nineteen units ship side-specific files. Code that builds the path itself
	# gets the right sprite for thirteen and the wrong one for six, which reads
	# as working. This is the defect issue #280 records three times.
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
	assert_true(_names_a_unit_png('\tvar p := "%s/%s.png" % [UnitArt.ART_DIR, id]'),
		"building the path from ART_DIR must be flagged")
	assert_false(_names_a_unit_png('\tvar r := FileAccess.get_file_as_string("res://Assets/Units/README.md")'),
		"the README is not art and must not be flagged")
	assert_false(_names_a_unit_png('## a PNG in res://Assets/Units/brute.png, said a comment'),
		"a comment must not be flagged")
	assert_false(_names_a_unit_png('\tvar dir := DirAccess.open(UnitArt.ART_DIR)'),
		"listing the directory is not loading a sprite")


func test_side_specific_art_still_exists_or_this_guard_guards_nothing() -> void:
	# The guard's whole reason is that `<id>.player.png` and `<id>.enemy.png`
	# resolve differently. If that convention ever leaves the project, delete the
	# guard rather than leaving it standing on a premise that stopped being true.
	var split := 0
	for id in Silhouettes.shape_ids():
		if UnitArt.texture_for(id, CG.Team.PLAYER) != UnitArt.texture_for(id, CG.Team.ENEMY):
			split += 1
	assert_true(split > 0, "no unit has side-specific art any more; test_art_dispatch.gd is obsolete")


## True when a line of GDScript names a unit sprite file outside the dispatch.
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
