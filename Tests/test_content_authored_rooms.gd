extends "res://Tests/TestCase.gd"

const AuthoredRooms := preload("res://Scripts/Content/Modules/authored_rooms.gd")

## Issue 19's other half: kite's level editor writes a room to
## `res://Assets/Rooms/<id>.json`; `EncounterCodec` and
## `Scripts/Content/Modules/authored_rooms.gd` are what let `Registry` read
## one back. `EncounterCodec`'s format is fixed by
## `LevelEditorView._encounter_dict`, agreed on the board before this file
## was written -- `test_encounter_to_dict_matches_the_encoder_kite_already_
## shipped` below checks against that exact shape, not a re-derived one.
##
## No test here writes into `res://Assets/Rooms/` -- same reasoning
## `Tests/test_ui_level_editor.gd` already states: a tracked directory a
## gate run must not leave files in. Tests that need a real file write into
## a scratch `user://` directory instead (outside the repo entirely) and
## remove it in `teardown()`.

var _scratch_dir: String = ""

func teardown() -> void:
	if _scratch_dir == "":
		return
	var dir := DirAccess.open(_scratch_dir)
	if dir != null:
		for f in dir.get_files():
			dir.remove(f)
	DirAccess.remove_absolute(_scratch_dir)
	_scratch_dir = ""

func _make_scratch_dir() -> String:
	_scratch_dir = "user://test_authored_rooms_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_scratch_dir)
	return _scratch_dir

func _write(dir_path: String, file_name: String, text: String) -> void:
	var f := FileAccess.open("%s/%s" % [dir_path, file_name], FileAccess.WRITE)
	f.store_string(text)
	f.close()

# ---------------------------------------------------------------------------
# EncounterCodec.encounter_to_dict
# ---------------------------------------------------------------------------

func _make_encounter() -> Encounter:
	var e := Encounter.new()
	e.id = &"authored_the_pit"
	e.display_name = "The Pit"
	e.enemy_spawns = [{"enemy_id": &"goblin", "position": Vector2(150.0, -150.0)}]
	e.party_spawns = [Vector2(-350.0, -195.0)]
	var wall := Terrain.make(Terrain.Kind.WALL, Rect2(-20.0, -270.0, 40.0, 170.0))
	e.terrain = [wall]
	return e

## Matches the exact literal from kite's own board post, byte for byte --
## the contract this file exists to satisfy.
func test_encounter_to_dict_matches_the_agreed_save_format() -> void:
	var d := EncounterCodec.encounter_to_dict(_make_encounter())
	assert_eq(d["id"], "authored_the_pit")
	assert_eq(d["display_name"], "The Pit")
	assert_eq(d["enemy_spawns"], [{"enemy_id": "goblin", "x": 150.0, "y": -150.0}])
	assert_eq(d["party_spawns"], [{"x": -350.0, "y": -195.0}])
	assert_eq(d["terrain"], [{
		"kind": "WALL", "x": -20.0, "y": -270.0, "w": 40.0, "h": 170.0,
		"damage_per_tick": 0, "damage_type": "PHYSICAL",
	}])

# ---------------------------------------------------------------------------
# EncounterCodec.dict_to_encounter
# ---------------------------------------------------------------------------

func test_dict_to_encounter_round_trips_through_the_encoder() -> void:
	var original := _make_encounter()
	var decoded := EncounterCodec.dict_to_encounter(EncounterCodec.encounter_to_dict(original))
	assert_not_null(decoded)
	assert_eq(decoded.id, original.id)
	assert_eq(decoded.display_name, original.display_name)
	assert_eq(decoded.enemy_spawns.size(), 1)
	assert_eq(decoded.enemy_spawns[0]["enemy_id"], &"goblin")
	assert_eq(decoded.enemy_spawns[0]["position"], Vector2(150.0, -150.0))
	assert_eq(decoded.party_spawns, [Vector2(-350.0, -195.0)])
	assert_eq(decoded.terrain.size(), 1)
	assert_eq(decoded.terrain[0].kind, Terrain.Kind.WALL)
	assert_eq(decoded.terrain[0].rect, Rect2(-20.0, -270.0, 40.0, 170.0))

## Round-trips through JSON.stringify/parse_string too, not just the two
## Dictionary functions -- a JSON number always comes back as a float, and
## this is what actually catches an int/float mismatch the pure functions
## alone would not.
func test_dict_to_encounter_round_trips_through_real_json_text() -> void:
	var original := _make_encounter()
	var text := JSON.stringify(EncounterCodec.encounter_to_dict(original))
	var parsed: Variant = JSON.parse_string(text)
	assert_eq(typeof(parsed), TYPE_DICTIONARY)
	var decoded := EncounterCodec.dict_to_encounter(parsed)
	assert_not_null(decoded)
	assert_eq(decoded.id, original.id)
	assert_eq(decoded.terrain[0].rect, Rect2(-20.0, -270.0, 40.0, 170.0))


func test_dict_to_encounter_returns_null_without_an_id() -> void:
	assert_eq(EncounterCodec.dict_to_encounter({"display_name": "No Id"}), null)


func test_dict_to_encounter_returns_null_with_an_empty_id() -> void:
	assert_eq(EncounterCodec.dict_to_encounter({"id": "", "display_name": "Empty Id"}), null)


func test_dict_to_encounter_returns_null_without_a_display_name() -> void:
	assert_eq(EncounterCodec.dict_to_encounter({"id": "no_name"}), null)


## An unknown Terrain.Kind string (a hand-edited file, or a future kind an
## older build does not know about) skips that one feature rather than
## failing the whole room -- same "does nothing rather than crashes"
## posture the rest of the content layer takes on a bad reference.
func test_dict_to_encounter_skips_an_unknown_terrain_kind() -> void:
	var d := {
		"id": "bad_terrain", "display_name": "Bad Terrain",
		"terrain": [{"kind": "NOT_A_REAL_KIND", "x": 0.0, "y": 0.0, "w": 1.0, "h": 1.0, "damage_per_tick": 0, "damage_type": "PHYSICAL"}],
	}
	var e := EncounterCodec.dict_to_encounter(d)
	assert_not_null(e)
	assert_eq(e.terrain.size(), 0)


func test_dict_to_encounter_defaults_missing_arrays_to_empty() -> void:
	var e := EncounterCodec.dict_to_encounter({"id": "bare", "display_name": "Bare"})
	assert_not_null(e)
	assert_eq(e.enemy_spawns, [])
	assert_eq(e.party_spawns, [])
	assert_eq(e.terrain, [])

# ---------------------------------------------------------------------------
# authored_rooms.gd -- real disk I/O, scratch user:// directory only
# ---------------------------------------------------------------------------

func test_encounters_returns_empty_for_a_directory_that_does_not_exist() -> void:
	var result := AuthoredRooms.encounters("user://this_directory_does_not_exist_%d" % Time.get_ticks_usec())
	assert_eq(result, [])


func test_encounters_reads_a_real_saved_room_from_disk() -> void:
	var dir := _make_scratch_dir()
	_write(dir, "authored_the_pit.json", JSON.stringify(EncounterCodec.encounter_to_dict(_make_encounter())))
	var result := AuthoredRooms.encounters(dir)
	assert_eq(result.size(), 1)
	assert_eq(result[0].id, &"authored_the_pit")
	assert_eq(result[0].display_name, "The Pit")


func test_encounters_ignores_non_json_files_in_the_same_directory() -> void:
	var dir := _make_scratch_dir()
	_write(dir, "authored_the_pit.json", JSON.stringify(EncounterCodec.encounter_to_dict(_make_encounter())))
	_write(dir, "README.txt", "not a room")
	var result := AuthoredRooms.encounters(dir)
	assert_eq(result.size(), 1)


func test_encounters_skips_a_malformed_file_and_still_reads_the_rest() -> void:
	var dir := _make_scratch_dir()
	_write(dir, "broken.json", "{ this is not valid json")
	_write(dir, "authored_the_pit.json", JSON.stringify(EncounterCodec.encounter_to_dict(_make_encounter())))
	var result := AuthoredRooms.encounters(dir)
	assert_eq(result.size(), 1)
	assert_eq(result[0].id, &"authored_the_pit")


func test_encounters_reads_more_than_one_room() -> void:
	var dir := _make_scratch_dir()
	var a := _make_encounter()
	var b := _make_encounter()
	b.id = &"authored_the_second_room"
	b.display_name = "The Second Room"
	_write(dir, "a.json", JSON.stringify(EncounterCodec.encounter_to_dict(a)))
	_write(dir, "b.json", JSON.stringify(EncounterCodec.encounter_to_dict(b)))
	var result := AuthoredRooms.encounters(dir)
	assert_eq(result.size(), 2)
	var ids := []
	for e in result:
		ids.append(String(e.id))
	ids.sort()
	assert_eq(ids, ["authored_the_pit", "authored_the_second_room"])
