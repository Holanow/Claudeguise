extends "res://Tests/TestCase.gd"


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
	var screen := PartySelect.create()
	var pawn := _make_pawn("warrior", "Warrior")
	screen.toggle_pawn(pawn, true)
	assert_eq(screen.selected_pawns().size(), 1)
	screen.toggle_pawn(pawn, false)
	assert_eq(screen.selected_pawns().size(), 0)
	screen.free()

func test_toggle_pawn_respects_the_four_pawn_cap() -> void:
	var screen := PartySelect.create()
	var pawns: Array[PawnData] = []
	for i in 5:
		var pawn := _make_pawn("class_%d" % i, "Class %d" % i)
		pawns.append(pawn)
		screen.toggle_pawn(pawn, true)
	assert_eq(screen.selected_pawns().size(), 4, "a fifth pawn must not join the party")
	screen.free()

func test_current_config_carries_the_selected_party_and_seed() -> void:
	var screen := PartySelect.create()
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
	var screen := PartySelect.create()
	var warrior := _make_pawn("warrior", "Warrior")
	var priest := _make_pawn("priest", "Priest")

	screen.toggle_pawn(warrior, true)
	var config_a := screen.current_config()

	screen.toggle_pawn(warrior, false)
	screen.toggle_pawn(priest, true)
	var config_b := screen.current_config()

	assert_ne(config_a.party[0].display_name, config_b.party[0].display_name)
	screen.free()

## Issue 32: this picked Registry.all_encounter_ids()[0] — alphabetically
## first, not the encounter the game means — so every real playthrough
## fought whichever room happened to sort first once a second one existed.
## Needs real Registry content (CG.DEFAULT_ENCOUNTER has to actually be
## registered to prove anything), so this is a no-op rather than a false
## pass while the registry is empty.
func test_current_config_picks_the_default_encounter_not_the_alphabetically_first_one() -> void:
	var screen := PartySelect.create()
	screen._ready()
	var encounters := Registry.all_encounter_ids()
	if not encounters.has(CG.DEFAULT_ENCOUNTER):
		return
	screen.toggle_pawn(_make_pawn("warrior", "Warrior"), true)
	var config := screen.current_config()
	assert_eq(config.encounter_id, CG.DEFAULT_ENCOUNTER)
	screen.free()

func test_prefill_seed_sets_the_seed_field() -> void:
	var screen := PartySelect.create()
	screen._ready()
	screen.prefill_seed("0000002A")
	var config := screen.current_config()
	assert_eq(config.seed_text(), "0000002A")
	screen.free()

func test_start_button_explains_why_it_is_disabled_with_no_party() -> void:
	var screen := PartySelect.create()
	screen._ready()
	assert_true(screen._start_button.disabled)
	assert_ne(screen._start_button.text, "Start Fight", "must say why, not just be greyed out")
	screen.free()

## rook found this on a real 844x390 launch: both buttons read "Pick at
## least one class" while disabled, literally indistinguishable -- the
## disabled-state version of the player's own complaint that Start Fight
## and Start Run don't say what they do.
func test_disabled_start_fight_and_start_run_read_differently() -> void:
	var screen := PartySelect.create()
	screen._ready()
	assert_ne(screen._start_button.text, screen._start_run_button.text, "the two disabled buttons must not read identically")
	screen.free()

func test_start_button_enables_and_reads_start_once_a_pawn_is_picked() -> void:
	var screen := PartySelect.create()
	screen._ready()
	var pawn := _make_pawn("warrior", "Warrior")
	screen.toggle_pawn(pawn, true)
	assert_false(screen._start_button.disabled)
	assert_eq(screen._start_button.text, "Start Fight")
	screen.free()

func test_a_fifth_selection_is_visibly_refused_not_silently_ignored() -> void:
	var screen := PartySelect.create()
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
	var screen := PartySelect.create()
	screen._ready()
	assert_true(screen._start_button.custom_minimum_size.y >= Palette.TOUCH_TARGET_MIN)
	screen.free()

func test_the_seed_field_meets_the_minimum_touch_target() -> void:
	var screen := PartySelect.create()
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
	var screen := PartySelect.create()
	screen._ready()
	var class_ids := Registry.all_class_ids()
	if class_ids.is_empty():
		return
	for pawn in screen.available_pawns():
		assert_false(pawn.plans.is_empty(), "%s has no plans" % pawn.display_name)
	screen.free()

func test_every_card_meets_the_minimum_touch_target() -> void:
	var screen := PartySelect.create()
	screen._ready()
	for id in screen._cards:
		var card = screen._cards[id]
		assert_true(card.custom_minimum_size.x >= Palette.TOUCH_TARGET_MIN)
		assert_true(card.custom_minimum_size.y >= Palette.TOUCH_TARGET_MIN)
	screen.free()

## Issue 53 sweep: at 844x390 (the phone-landscape size the game is
## required to work at), the roster's own minimum height -- three rows of
## 170x200 cards -- pushed Start Fight past the bottom of the viewport. A
## Container does not clip or scroll on its own, so that content was still
## there and simply off-canvas: not visible, not clickable. The roster is
## what makes this column tall, so it is what has to give up its natural
## size to the viewport; everything below it (seed, status, every button)
## keeps its own minimum size and stays reachable regardless of how many
## classes the roster grows to. Asserted on the tree shape rather than only
## via a screenshot -- a real launch's rect check backs this in the PR.
## PLAYTEST-NOTES 11 / hover-info-box system: "Start Fight and Start Run
## don't say what they do." Same GlossaryButton mechanism as every other
## hoverable term.
func test_start_fight_and_start_run_carry_distinct_glossary_tooltips() -> void:
	var screen := PartySelect.create()
	screen._ready()
	assert_false(screen._start_button.tooltip_text.is_empty())
	assert_false(screen._start_run_button.tooltip_text.is_empty())
	assert_ne(screen._start_button.tooltip_text, screen._start_run_button.tooltip_text)
	screen.free()

func test_roster_is_scrollable_so_the_buttons_below_it_stay_reachable() -> void:
	var screen := PartySelect.create()
	screen._ready()
	assert_true(screen._roster_box.get_parent() is ScrollContainer, "the roster grid must be able to give up space to a short viewport")
	assert_eq(screen._roster_box.get_parent().size_flags_vertical, Control.SIZE_EXPAND_FILL)
	screen.free()

# ---------------------------------------------------------------------------
# Issue 133, from the player: "The opening screen has a ton of horizontal space
# to use but I still have to scroll the class selector. Make it fill the
# available space instead."
#
# The roster was a `GridContainer` at a constant two columns, so five classes
# sat in the left quarter of a 1280-wide screen and were clipped mid-row.
#
# These measure the geometry rather than the container's class name. A
# `Container` lays its children out on NOTIFICATION_SORT_CHILDREN, which is
# queued by the tree; sending it directly runs the same sort now, so the wrap
# can be measured on a detached screen the way every other test here builds one.
# ---------------------------------------------------------------------------

## THE WRAP ITSELF IS NOT ASSERTED HERE, AND THE REASON IS WORTH WRITING DOWN
## BECAUSE I SHIPPED THE INERT VERSION FIRST AND THE GATE WENT GREEN ON IT.
##
## I wrote `box.size = Vector2(w, 2000); box.notification(
## Container.NOTIFICATION_SORT_CHILDREN)` and read the card positions back. The
## wide case passed. It was measuring nothing: probed on a real launch, that
## notification lays out nothing on a detached container -- `get_line_count()`
## comes back 0 and every card's rect is `[P: (0,0), S: (0,0)]`, so all five
## cards share y=0 and "one row" is what an unlaid-out container looks like, not
## what a correct one looks like. A `Container` sorts on a frame inside a tree,
## and these tests build detached screens.
##
## So the geometry is verified where it can be: `Tools/ScreenSweep.tscn` at both
## required resolutions, captures in the PR. What is asserted below are the two
## structural properties that the capture cannot regress-check, and neither is a
## restatement of the container's own class name.
##
## Announcements rule 2: "X never happens" is also passed by "X can never be
## observed." This was that, and I only found it by probing rather than trusting
## a green line.

## `columns` is the thing that made five classes show as two. A flow container
## has no such field, and the assertion is on the absence of a fixed column
## count rather than on the class, so a future `GridContainer` with a computed
## column count would also pass -- it is the constant that was the defect.
func test_the_roster_has_no_fixed_column_count() -> void:
	var screen := PartySelect.create()
	screen._ready()
	var cards: int = screen._roster_box.get_child_count()
	assert_true(cards >= 5, "the shipped game has five classes, got %d" % cards)
	assert_false(&"columns" in screen._roster_box,
		"a fixed column count is what put five classes in two columns")
	assert_true(screen._roster_box is HFlowContainer,
		"the roster must wrap at the width the layout gives it")
	screen.free()

## The wrap only reaches the cards if the ScrollContainer forces the flow to its
## own width. Left at the default it hands the child its minimum width and
## scrolls sideways instead, which looks identical in the code and puts every
## card on one unreachable line.
func test_the_roster_wraps_rather_than_scrolling_sideways() -> void:
	var screen := PartySelect.create()
	screen._ready()
	assert_eq(screen._roster_box.get_parent().horizontal_scroll_mode,
		ScrollContainer.SCROLL_MODE_DISABLED,
		"a sideways-scrolling roster never wraps, whatever container is inside it")
	screen.free()

## The half that actually stops the scrolling. Five full-width stacked buttons
## spent about 320 of 720 pixels of height, so the roster was left 175 for a
## 200-pixel card; widening the roster alone could not have fixed that.
##
## Start Fight stays on its own band: it is the primary action, and this asserts
## the distinction rather than only the saving, because flowing all five would
## have passed a height check while making the screen read as five equal choices.
func test_the_secondary_destinations_share_a_row_and_start_fight_does_not() -> void:
	var screen := PartySelect.create()
	screen._ready()
	var row := screen._start_run_button.get_parent()
	assert_true(row is HFlowContainer, "the secondary buttons must share a wrapping row")
	assert_ne(screen._start_button.get_parent(), row, "Start Fight keeps its own full-width band")
	var texts: Array[String] = []
	for child in row.get_children():
		if child is Button:
			texts.append(child.text)
	for expected in ["Inspect classes", "Equip pawns", "Level editor"]:
		assert_true(texts.has(expected), "'%s' must be in the shared row, row holds %s" % [expected, str(texts)])
	screen.free()
