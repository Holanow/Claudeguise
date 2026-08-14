extends "res://Tests/TestCase.gd"

const CG := preload("res://Scripts/Core/CG.gd")
const ClassDef := preload("res://Scripts/Core/ClassDef.gd")
const PartyCard := preload("res://Scripts/UI/PartyCard.gd")
const Glossary := preload("res://Scripts/UI/Glossary.gd")

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
	var found := false
	for child in popup.get_children():
		if child is Label and child.text == card.tooltip_text:
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
