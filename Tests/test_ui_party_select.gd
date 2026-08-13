extends "res://Tests/TestCase.gd"

const RunConfig := preload("res://Scripts/Core/RunConfig.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const ClassDef := preload("res://Scripts/Core/ClassDef.gd")
const Palette := preload("res://Scripts/Core/Palette.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PartySelect := preload("res://Scripts/UI/PartySelect.gd")

## Swapping the party between runs is an acceptance criterion for the slice, so
## PartySelect is not a placeholder. These tests drive selection through
## toggle_pawn() (what the checkboxes call) rather than through the tree, so
## they do not depend on Registry having content yet.

func _make_pawn(id: String, name: String) -> PawnData:
	var cls := ClassDef.new()
	cls.id = StringName(id)
	cls.display_name = name
	var pawn := PawnData.new()
	pawn.id = StringName(id)
	pawn.display_name = name
	pawn.pawn_class = cls
	return pawn

func test_toggle_pawn_adds_and_removes_from_the_party() -> void:
	var screen := PartySelect.new()
	var pawn := _make_pawn("warrior", "Warrior")
	screen.toggle_pawn(pawn, true)
	assert_eq(screen.selected_pawns().size(), 1)
	screen.toggle_pawn(pawn, false)
	assert_eq(screen.selected_pawns().size(), 0)
	screen.free()

func test_toggle_pawn_respects_the_four_pawn_cap() -> void:
	var screen := PartySelect.new()
	var pawns: Array[PawnData] = []
	for i in 5:
		var pawn := _make_pawn("class_%d" % i, "Class %d" % i)
		pawns.append(pawn)
		screen.toggle_pawn(pawn, true)
	assert_eq(screen.selected_pawns().size(), 4, "a fifth pawn must not join the party")
	screen.free()

func test_current_config_carries_the_selected_party_and_seed() -> void:
	var screen := PartySelect.new()
	# _seed_edit is built in _ready(), which does not run outside a tree. A
	# missing edit falls back to seed 0 rather than crashing.
	var pawn := _make_pawn("priest", "Priest")
	screen.toggle_pawn(pawn, true)
	var config := screen.current_config()
	assert_eq(config.party.size(), 1)
	assert_eq(config.party[0].display_name, "Priest")
	screen.free()

func test_two_different_selections_produce_different_configs() -> void:
	# The party can be swapped and it shows: two different selections must not
	# collapse into the same RunConfig.
	var screen := PartySelect.new()
	var warrior := _make_pawn("warrior", "Warrior")
	var priest := _make_pawn("priest", "Priest")

	screen.toggle_pawn(warrior, true)
	var config_a := screen.current_config()

	screen.toggle_pawn(warrior, false)
	screen.toggle_pawn(priest, true)
	var config_b := screen.current_config()

	assert_ne(config_a.party[0].display_name, config_b.party[0].display_name)
	screen.free()

func test_prefill_seed_sets_the_seed_field() -> void:
	var screen := PartySelect.new()
	screen._ready()
	screen.prefill_seed("0000002A")
	var config := screen.current_config()
	assert_eq(config.seed_text(), "0000002A")
	screen.free()

func test_start_button_explains_why_it_is_disabled_with_no_party() -> void:
	var screen := PartySelect.new()
	screen._ready()
	assert_true(screen._start_button.disabled)
	assert_ne(screen._start_button.text, "Start Fight", "must say why, not just be greyed out")
	screen.free()

func test_start_button_enables_and_reads_start_once_a_pawn_is_picked() -> void:
	var screen := PartySelect.new()
	screen._ready()
	var pawn := _make_pawn("warrior", "Warrior")
	screen.toggle_pawn(pawn, true)
	assert_false(screen._start_button.disabled)
	assert_eq(screen._start_button.text, "Start Fight")
	screen.free()

func test_a_fifth_selection_is_visibly_refused_not_silently_ignored() -> void:
	var screen := PartySelect.new()
	screen._ready()
	for i in 4:
		screen.toggle_pawn(_make_pawn("class_%d" % i, "Class %d" % i), true)
	var status_before := screen._status_label.text
	screen._on_card_toggled(true, _make_pawn("class_4", "Class 4"))
	assert_ne(screen._status_label.text, status_before,
		"the fifth attempt must change something visible, not do nothing at all")
	assert_eq(screen.selected_pawns().size(), 4)
	screen.free()

## Issue 17: "a checkbox glyph is nowhere near TOUCH_TARGET_MIN". Asserted
## rather than eyeballed — a 47px control looks fine in a screenshot and
## fails a thumb.
func test_the_start_button_meets_the_minimum_touch_target() -> void:
	var screen := PartySelect.new()
	screen._ready()
	assert_true(screen._start_button.custom_minimum_size.y >= Palette.TOUCH_TARGET_MIN)
	screen.free()

func test_the_seed_field_meets_the_minimum_touch_target() -> void:
	var screen := PartySelect.new()
	screen._ready()
	assert_true(screen._seed_edit.custom_minimum_size.y >= Palette.TOUCH_TARGET_MIN)
	screen.free()

## The real defect: hand-building PawnData in _build_roster left `plans`
## empty, so every pawn a player has ever actually fielded ran on
## DefaultBehavior only — no preset plan has fired outside a test or a
## devtools script. Needs real Registry content (PresetPlans is keyed off
## real class ids), so this is a no-op rather than a false pass while the
## registry is empty.
func test_every_roster_pawn_carries_its_preset_plans() -> void:
	var screen := PartySelect.new()
	screen._ready()
	var class_ids := Registry.all_class_ids()
	if class_ids.is_empty():
		return
	for pawn in screen.available_pawns():
		assert_false(pawn.plans.is_empty(), "%s has no plans" % pawn.display_name)
	screen.free()

func test_every_card_meets_the_minimum_touch_target() -> void:
	var screen := PartySelect.new()
	screen._ready()
	for id in screen._cards:
		var card = screen._cards[id]
		assert_true(card.custom_minimum_size.x >= Palette.TOUCH_TARGET_MIN)
		assert_true(card.custom_minimum_size.y >= Palette.TOUCH_TARGET_MIN)
	screen.free()
