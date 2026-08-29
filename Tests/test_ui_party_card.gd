extends "res://Tests/TestCase.gd"


## Issue 17: a class used to be a checkbox next to a bare word. PartyCard is
## the whole card — silhouette, name, role, style — and the whole thing is
## the touch target rather than a small glyph in front of the text.

func _make_class(id: String, name: String, style: CG.Style, method: CG.Method, role: CG.Role) -> ClassDef:
	var cls := ClassDef.new()
	cls.id = StringName(id)
	cls.display_name = name
	cls.style = style
	cls.method = method
	cls.role_primary = role
	cls.damage_types = [CG.DamageType.WATER]
	return cls

func test_card_meets_the_minimum_touch_target_on_both_sides() -> void:
	var card := PartyCard.new()
	card._ready()
	assert_true(card.custom_minimum_size.x >= 48.0, "touch target width")
	assert_true(card.custom_minimum_size.y >= 48.0, "touch target height")
	card.free()

func test_clicking_the_card_toggles_it() -> void:
	var card := PartyCard.new()
	card._ready()
	card.class_def = _make_class("priest", "Priest", CG.Style.RANGED, CG.Method.MAGICAL, CG.Role.HEALER)

	var emitted: Array = []
	card.toggled.connect(func(pressed: bool): emitted.append(pressed))

	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	card._gui_input(press)

	assert_eq(emitted, [true], "an unselected card must ask to become selected")
	card.free()

func test_role_text_names_the_primary_role() -> void:
	var card := PartyCard.new()
	card.class_def = _make_class("priest", "Priest", CG.Style.RANGED, CG.Method.MAGICAL, CG.Role.HEALER)
	assert_eq(card._role_text(), "Healer")
	card.free()

## Issue 19: "ANTI_SUPPORT" was a raw enum name with an underscore on the
## first screen of the game. Role text must never carry one through to what
## a player reads, whichever role it is.
func test_role_text_never_contains_a_raw_underscore() -> void:
	var card := PartyCard.new()
	card.class_def = _make_class("siege_master", "Siege Master", CG.Style.SUMMONER, CG.Method.MARTIAL, CG.Role.ANTI_SUPPORT)
	assert_false(card._role_text().contains("_"), card._role_text())
	assert_eq(card._role_text(), "Anti Support")
	card.free()

func test_style_text_distinguishes_ranged_from_melee() -> void:
	var ranged := PartyCard.new()
	ranged.class_def = _make_class("priest", "Priest", CG.Style.RANGED, CG.Method.MAGICAL, CG.Role.HEALER)
	var melee := PartyCard.new()
	melee.class_def = _make_class("warrior", "Warrior", CG.Style.MELEE, CG.Method.MARTIAL, CG.Role.TANK)

	assert_true(ranged._style_text().contains("Ranged"))
	assert_true(melee._style_text().contains("Melee"))
	assert_ne(ranged._style_text(), melee._style_text())
	ranged.free()
	melee.free()

# ---------------------------------------------------------------------------
# Hover-info-box system, phase 1: the whole card is one tooltip.
# ---------------------------------------------------------------------------

func test_class_def_sets_tooltip_text_to_the_glossary_tags() -> void:
	var card := PartyCard.new()
	var cls := _make_class("warrior", "Warrior", CG.Style.MELEE, CG.Method.MARTIAL, CG.Role.TANK)
	card.class_def = cls
	assert_eq(card.tooltip_text, Glossary.class_tags_text(cls.role_primary, cls.style, cls.method))
	card.free()

func test_make_custom_tooltip_returns_a_control_carrying_the_text() -> void:
	var card := PartyCard.new()
	card.class_def = _make_class("priest", "Priest", CG.Style.RANGED, CG.Method.MAGICAL, CG.Role.HEALER)
	var popup = card._make_custom_tooltip(card.tooltip_text)
	assert_not_null(popup)
	# `contains`, not `==`, since issue 112: the box carries the glossary
	# sentence plus the sentence naming the gesture that pins it. Disclosed in
	# the PR. The assertion still fails if the card's own text goes missing.
	var found := false
	for child in popup.get_children():
		if child is Label and child.text.contains(card.tooltip_text):
			found = true
	assert_true(found, "the tooltip popup must carry the card's own tooltip text")
	popup.free()
	card.free()

func test_a_healer_and_a_ranged_class_read_differently() -> void:
	# The specific check issue 17 asks for: can a player tell the ranged one
	# from the healer without playing. Role and style are independent axes
	# (a class can be ranged AND the healer), so this checks both together.
	var priest := PartyCard.new()
	priest.class_def = _make_class("priest", "Priest", CG.Style.RANGED, CG.Method.MAGICAL, CG.Role.HEALER)
	assert_eq(priest._role_text(), "Healer")
	assert_true(priest._style_text().contains("Ranged"))

	var warrior := PartyCard.new()
	warrior.class_def = _make_class("warrior", "Warrior", CG.Style.MELEE, CG.Method.MARTIAL, CG.Role.TANK)
	assert_ne(warrior._role_text(), "Healer")

	priest.free()
	warrior.free()

# ---------------------------------------------------------------------------
# The panel_border drop-in, wired
# ---------------------------------------------------------------------------


## PLAYTEST-NOTES-2 item 15. `UIArt.draw_border`, `draw_nine_slice` and
## `has_art` were written for it and had no game caller at all -- sable found
## that in #103 and flagged rather than deleted it. They have callers now.
func test_the_panel_border_drop_in_is_reachable_under_the_advertised_name() -> void:
	var path := "res://Assets/UI/panel_border.png"
	## Issue 807 ships a file under this name, so the empty state has to be made
	## rather than assumed. It is put back at the end; deleting it outright is
	## how the suite destroyed committed art the first time both existed.
	var real := ProjectSettings.globalize_path(path)
	var shipped := FileAccess.get_file_as_bytes(real) if FileAccess.file_exists(real) else PackedByteArray()
	DirAccess.remove_absolute(path)

	# Negative half first, and it is the half that matters: with no file the
	# pipeline says so, which is what makes `draw_border` fall through to the
	# flat outline the screens drew before this change.
	UIArt.clear_cache()
	assert_false(UIArt.has_art(&"panel_border"), "with no file dropped in, nothing must claim there is art")

	DirAccess.make_dir_recursive_absolute("res://Assets/UI")
	var image := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 0.0, 1.0, 1.0))
	assert_eq(image.save_png(path), OK, "could not write the test border to %s" % path)

	UIArt.clear_cache()
	assert_true(UIArt.has_art(&"panel_border"), "a PNG dropped in under the advertised name was not found")

	DirAccess.remove_absolute(path)
	UIArt.clear_cache()
	assert_false(UIArt.has_art(&"panel_border"), "the test border survived its own deletion")

	if not shipped.is_empty():
		var f := FileAccess.open(real, FileAccess.WRITE)
		f.store_buffer(shipped)
		f.close()
	UIArt.clear_cache()
	assert_eq(UIArt.has_art(&"panel_border"), not shipped.is_empty(),
		"the shipped panel_border.png did not come back")

## Selection is the one thing a dropped-in border must not be able to erase: a
## nine-slice is drawn as painted, so it cannot carry the selected/unselected
## colour the flat fallback carries. Asserted on the card's own state rather
## than on pixels, which these tests cannot render: with art present the card
## draws an extra ring, and the inset it uses has to be inside the card.
func test_a_dropped_in_border_cannot_erase_the_selection_ring() -> void:
	var card := PartyCard.new()
	card.set_script(PartyCard)
	assert_true(PartyCard.SELECTION_INSET > 0.0, "the ring must sit inside the border, not on top of it")
	assert_true(PartyCard.SELECTION_INSET * 2.0 < PartyCard.CARD_SIZE.x,
		"an inset wider than the card would draw an inside-out rect")
	card.free()

## **A structural check, and here is the property it stands for**: that a
## dropped-in PNG changes what these two screens draw. The real form of that
## assertion is a rendered pixel comparison, and this runner cannot take one --
## `case.call(name)` is synchronous and a viewport texture needs a frame. So
## this asserts only that the wiring is still present, and it cannot tell a
## correct `draw_border` call from a broken one.
func test_both_wired_screens_still_draw_their_frame_through_the_pipeline() -> void:
	var party_card_source := FileAccess.get_file_as_string("res://Scripts/UI/PartyCard.gd")
	var arena_source := FileAccess.get_file_as_string("res://Scripts/UI/ArenaFloor.gd")
	assert_false(party_card_source.is_empty(), "could not read PartyCard.gd")
	assert_false(arena_source.is_empty(), "could not read ArenaFloor.gd")
	assert_true(party_card_source.contains("UIArt.draw_border("), "PartyCard must draw its frame through the pipeline")
	assert_true(arena_source.contains("UIArt.draw_border("), "ArenaFloor must draw its frame through the pipeline")
