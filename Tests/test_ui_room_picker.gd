extends "res://Tests/TestCase.gd"


## Issue 176: the room picker.

func _screen() -> PartySelect:
	var screen := PartySelect.create()
	screen._ready()
	return screen

# ---------------------------------------------------------------------------
# The guard that stops this happening again
# ---------------------------------------------------------------------------

## **The check that would have caught the original defect.** Every registered
## encounter must be either offered by the picker or listed in `NOT_OFFERED`
func test_every_registered_room_is_either_offered_or_explicitly_not() -> void:
	var offered := PartySelect.offered_rooms()
	var unclassified: Array[String] = []
	for id in RoomLibrary.all_ids():
		if offered.has(id):
			continue
		if PartySelect.NOT_OFFERED.has(id):
			assert_true(String(PartySelect.NOT_OFFERED[id]).length() > 10,
				"'%s' is excluded with no real reason given" % id)
			continue
		unclassified.append(String(id))
	assert_eq(unclassified.size(), 0,
		"these rooms are registered, not offered, and not explicitly excluded -- a player cannot reach them and nothing says that is intended: %s" % str(unclassified))

## And the other direction: nothing may be both offered and excluded, and every
## room the picker names must actually exist in the registry.
func test_the_offered_list_and_the_excluded_list_do_not_disagree() -> void:
	for id in PartySelect.offered_rooms():
		assert_false(PartySelect.NOT_OFFERED.has(id),
			"'%s' is both offered and excluded" % id)
	# Issue #180 made this structural rather than filtered: offered rooms are
	# the ones whose `Encounter` sets `pickable`, so an offered room that does
	# not exist is no longer expressible. The assertion stays because it is what
	# says so.
	for id in PartySelect.offered_rooms():
		assert_not_null(RoomLibrary.get_room(id),
			"the picker offers '%s' and no such room is registered" % id)

## Compared against `offered_rooms()`, which since issue #180 is the registry
## filtered by `Encounter.pickable` -- there is no longer a hand-written list to
## compare against, and a classification cannot arrive ahead of its content.
func test_the_picker_offers_every_offered_room_in_authored_order() -> void:
	var screen := _screen()
	var picker: OptionButton = screen._room_picker
	assert_true(picker != null, "the screen must carry a room picker")
	var offered := PartySelect.offered_rooms()
	assert_true(offered.size() >= 4, "got %d" % offered.size())
	assert_eq(picker.item_count, offered.size())
	for i in offered.size():
		assert_eq(picker.get_item_metadata(i), offered[i],
			"order must be authored, not sorted -- StringName sorts by interned pointer")
	screen.free()

## Every offered room must show its own name, not its id. A picker reading
## `floor1_cover` is a picker showing internals.
func test_each_room_is_offered_under_its_display_name() -> void:
	var screen := _screen()
	var picker: OptionButton = screen._room_picker
	for i in picker.item_count:
		var id = picker.get_item_metadata(i)
		assert_eq(picker.get_item_text(i), RoomLibrary.get_room(id).display_name)
		assert_false(picker.get_item_text(i).begins_with("floor1_"), "raw id on screen")
	screen.free()

# ---------------------------------------------------------------------------
# Issue 32's rule, kept rather than replaced
# ---------------------------------------------------------------------------

## The old fix was correct AND it became a lid. The rule it encodes is still
## live: never pick an encounter by index, because `Array[StringName].sort()`
func test_the_picker_starts_on_the_default_room_not_whatever_sorts_first() -> void:
	var screen := _screen()
	assert_eq(screen.selected_room(), CG.DEFAULT_ENCOUNTER)
	assert_eq(screen.current_config().encounter_id, CG.DEFAULT_ENCOUNTER)
	screen.free()

## A screen with no picker built yet must still never fall through to
## `all_encounter_ids()[0]`.
func test_a_screen_with_no_picker_still_names_the_default_room() -> void:
	var screen := PartySelect.create()
	assert_eq(screen.current_config().encounter_id, CG.DEFAULT_ENCOUNTER,
		"the issue-32 fallback must survive")
	screen.free()

# ---------------------------------------------------------------------------
# Picking actually changes the fight
# ---------------------------------------------------------------------------

## Driven through the control a player touches. Asserted for **every** offered
## room rather than one, because a picker that always returns its first item
## would pass a single-room check.
func test_picking_a_room_changes_the_room_the_fight_will_use() -> void:
	var screen := _screen()
	var picker: OptionButton = screen._room_picker
	for i in picker.item_count:
		picker.selected = i
		picker.item_selected.emit(i)
		var want = picker.get_item_metadata(i)
		assert_eq(screen.selected_room(), want)
		assert_eq(screen.current_config().encounter_id, want,
			"picking '%s' must reach the RunConfig the fight is built from" % want)
	screen.free()

# ---------------------------------------------------------------------------
# The summary beside the picker
# ---------------------------------------------------------------------------

## Derived from the `Encounter`, never authored beside it: a hand-written blurb
## goes quietly false the day somebody moves a pillar. Checked against the real
## counts, so if the room changes underneath, this fails.
func test_the_summary_counts_what_the_room_really_contains() -> void:
	for id in PartySelect.offered_rooms():
		var room = RoomLibrary.get_room(id)
		var summary := PartySelect.room_summary(id)
		assert_true(summary.contains("%d enemies" % room.enemy_spawns.size()),
			"'%s' summary must state the real headcount, got: %s" % [id, summary])
		var pillars := 0
		for c in room.cells.values():
			if c.kind == Terrain.Kind.PILLAR:
				pillars += 1
		if pillars > 0:
			assert_true(summary.contains("%d pillar" % pillars),
				"'%s' has %d pillars and the summary does not say so: %s" % [id, pillars, summary])

## A room with no terrain must say something rather than trailing off after the
## headcount -- "open ground" is information, an empty clause is not.
func test_a_room_with_no_terrain_says_open_ground() -> void:
	var bare: StringName = &""
	for id in PartySelect.offered_rooms():
		if RoomLibrary.get_room(id).cells.is_empty():
			bare = id
			break
	assert_true(bare != &"", "no offered room is open ground, so this check is vacuous")
	assert_true(PartySelect.room_summary(bare).contains("open ground"),
		"got: %s" % PartySelect.room_summary(bare))
