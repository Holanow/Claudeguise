extends RefCounted


## Issue 19's other half: kite's level editor writes a real room to
## `res://Assets/Rooms/<id>.json` (`Scripts/UI/LevelEditorView.gd`); nothing
## read it back until this file, so a saved room never reached the
## generator. This module closes that gap the same way every other content
## module reaches `Registry` -- one file, one line in `Registry.MODULES`,
## `encounters()` is the only non-empty function.

const ROOMS_DIR := "res://Assets/Rooms"

static func classes() -> Array[ClassDef]:
	return []

static func actions() -> Array[ActionDef]:
	return []

static func enemies() -> Array[EnemyDef]:
	return []

## `dir_path` defaults to the real save location; the parameter exists so a
## test can point this at a scratch `user://` directory instead of writing
## into `res://Assets/Rooms/` -- a tracked directory a gate run must not
## leave files in, same reasoning `Tests/test_ui_level_editor.gd` already
## states for why it never exercises the encoder's own disk-writing tail.
static func encounters(dir_path: String = ROOMS_DIR) -> Array[Encounter]:
	var out: Array[Encounter] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		# No Assets/Rooms directory yet is the normal case -- nobody has
		# saved a room. Not an error.
		return out
	for file_name in dir.get_files():
		if not file_name.ends_with(".json"):
			continue
		var path := "%s/%s" % [dir_path, file_name]
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			push_error("authored_rooms: could not open %s (%s)" % [path, error_string(FileAccess.get_open_error())])
			continue
		var text := f.get_as_text()
		f.close()
		var parsed: Variant = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("authored_rooms: %s is not a JSON object, skipped" % path)
			continue
		var e := EncounterCodec.dict_to_encounter(parsed)
		if e == null:
			push_error("authored_rooms: %s did not decode to a valid Encounter, skipped" % path)
			continue
		out.append(e)
	return out

static func items() -> Array[EquipmentDef]:
	return []
