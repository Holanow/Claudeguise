extends "res://Tests/TestCase.gd"

const OverlayScript := preload("res://Scripts/UI/LevelEditorOverlay.gd")

## The deploy screen's names, which had no de-collision at all: every label drew
## itself at its own marker knowing nothing about the others, so a fourth blind
## playtester read `Ghoul` over `Cultist` as `ltist` every single time.

func _marker(text: String, at: Vector2, radius: float = 22.0) -> Dictionary:
	return {"text": text, "at": at, "radius": radius}

func _rects(layout: Array) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for entry in layout:
		out.append(entry["rect"])
	return out

func _overlapping_pairs(rects: Array[Rect2]) -> int:
	var pairs := 0
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			if rects[i].intersects(rects[j]):
				pairs += 1
	return pairs

## The fixture is the playtester's own: two markers close enough that the names
## overprint. Row 0 is where every label used to be drawn, so this asserts the
## defect is real before the next test asserts it is gone -- a check that cannot
## fail is not a check.
func test_row_zero_is_the_defect_the_playtester_reported() -> void:
	var a := OverlayScript.label_rect("Ghoul", Vector2(0.0, 0.0), 22.0, 0)
	var b := OverlayScript.label_rect("Cultist", Vector2(18.0, 6.0), 22.0, 0)
	assert_true(a.intersects(b), "the fixture must reproduce the overprint, or the fix proves nothing")

## The playtester's exact sighting, in the room the game opens on: `ghoul` at
## (190, -220) and `cultist` at (210, -200). Both names used to draw on row 0,
## which is why `Ghoul` over `Cultist` read as `ltist` every single time.
func test_the_default_room_is_where_ltist_came_from() -> void:
	var markers: Array = []
	for spawn in Registry.get_encounter(CG.DEFAULT_ENCOUNTER).enemy_spawns:
		markers.append(_marker(OverlayScript.enemy_label(spawn), spawn.position,
			float(spawn.get("radius", 22.0))))
	var row_zero: Array[Rect2] = []
	for m in markers:
		row_zero.append(OverlayScript.label_rect(String(m["text"]), m["at"], float(m["radius"]), 0))
	assert_true(_overlapping_pairs(row_zero) > 0,
		"sanity: the room really does overprint without a search, or nothing below proves anything")
	assert_eq(_overlapping_pairs(_rects(OverlayScript.label_layout(markers))), 0)

func test_crowded_markers_get_rows_that_do_not_overprint() -> void:
	var layout := OverlayScript.label_layout([
		_marker("Ghoul", Vector2(0.0, 0.0)),
		_marker("Cultist", Vector2(18.0, 6.0)),
		_marker("Geysermancer", Vector2(-6.0, 12.0)),
		_marker("Goblin Archer", Vector2(10.0, -4.0)),
	])
	assert_eq(layout.size(), 4)
	assert_eq(_overlapping_pairs(_rects(layout)), 0, "no two names may share a pixel")

## Fourteen names on one marker is past anything a room can produce, and the
## search still has a free row for every one of them.
func test_the_search_does_not_run_out_on_a_full_scrum() -> void:
	var markers: Array = []
	for i in 14:
		markers.append(_marker("Goblin Archer", Vector2(0.0, 0.0)))
	var layout := OverlayScript.label_layout(markers)
	assert_eq(_overlapping_pairs(_rects(layout)), 0, "fourteen names on one point must all find a row")

## The negative case: nothing moves when nothing collides. Without this a layout
## that lifted every label unconditionally would pass the tests above.
func test_labels_that_do_not_collide_stay_on_their_own_markers() -> void:
	var layout := OverlayScript.label_layout([
		_marker("Ghoul", Vector2(-300.0, -100.0)),
		_marker("Cultist", Vector2(300.0, 140.0)),
	])
	for entry in layout:
		assert_eq(int(entry["row"]), 0, "an uncrowded name must sit where it always sat")
	assert_eq(layout[0]["rect"], OverlayScript.label_rect("Ghoul", Vector2(-300.0, -100.0), 22.0, 0))

## Same markers, same rects, every time: the screen redraws on every mouse move
## and a name that hops rows between frames is its own defect.
func test_the_layout_is_the_same_every_time_it_is_asked() -> void:
	var markers: Array = [
		_marker("Ghoul", Vector2(0.0, 0.0)),
		_marker("Cultist", Vector2(18.0, 6.0)),
	]
	assert_eq(_rects(OverlayScript.label_layout(markers)), _rects(OverlayScript.label_layout(markers)))

## Every enemy in every pickable room, at the positions the room really places
## them, through the same layout the screen draws.
func test_no_pickable_room_overprints_its_own_enemy_names() -> void:
	var checked := 0
	for id in Registry.pickable_encounter_ids():
		var encounter = Registry.get_encounter(id)
		var markers: Array = []
		for spawn in encounter.enemy_spawns:
			markers.append(_marker(OverlayScript.enemy_label(spawn), spawn.position,
				float(spawn.get("radius", 22.0))))
		if markers.size() < 2:
			continue
		checked += 1
		assert_eq(_overlapping_pairs(_rects(OverlayScript.label_layout(markers))), 0,
			"%s overprints its own enemy names" % id)
	assert_true(checked >= 4, "the walk must actually reach rooms, not skip them all")
