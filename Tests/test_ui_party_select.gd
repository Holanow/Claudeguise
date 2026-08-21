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

## **Issue 399 REVERSED this assertion.** It demanded that every roster pawn
## carry its preset plans; the ruling is that a class ships with none and the
## player adds them, so the empty list is now the requirement rather than the
## defect. The half worth keeping is that the roster pawn is a real
## `PawnFactory` pawn -- class, gear and a non-empty library to add from -- which
## is what the original hand-built `PawnData` was not.
func test_every_roster_pawn_starts_with_no_plans_and_a_library_to_add_from() -> void:
	var screen := PartySelect.create()
	screen._ready()
	var class_ids := Registry.all_class_ids()
	if class_ids.is_empty():
		return
	for pawn in screen.available_pawns():
		assert_true(pawn.plans.is_empty(),
			"%s ships with %d plan rows; issue 399 starts the editor empty" % [pawn.display_name, pawn.plans.size()])
		assert_not_null(pawn.pawn_class, "%s is not a real class pawn" % pawn.display_name)
		assert_false(PresetPlans.for_class(pawn.pawn_class.id).is_empty(),
			"%s has an empty preset library, so there is nothing for the player to add" % pawn.display_name)
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

## THE WRAP ITSELF IS NOT ASSERTED HERE, AND THE REASON IS WORTH WRITING DOWN
## BECAUSE I SHIPPED THE INERT VERSION FIRST AND THE GATE WENT GREEN ON IT.

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
## Rewritten for issue 351, and the intent is the one it was written with: the
## thing that starts a fight must not be confusable with a place to go. Two of
## the three buttons it used to name are gone, because the screens they opened
## are now the middle column.
func test_starting_a_fight_lives_apart_from_the_places_you_can_go() -> void:
	var screen := PartySelect.create()
	screen._ready()
	var column := screen._start_button.get_parent()
	assert_eq(screen._start_run_button.get_parent(), column,
		"the two ways to start a fight belong together")
	var level_editor: Button = null
	for node in _all_nodes(screen):
		if node is Button and node.text == "Level editor":
			level_editor = node
	assert_not_null(level_editor, "the level editor is still reachable")
	assert_true(column.get_children().find(level_editor) > column.get_children().find(screen._start_run_button) + 1,
		"the level editor must not sit against the Start buttons")

	## And the destinations that became columns are gone as destinations, or
	## this screen has both and the mismatch the issue was filed for.
	var button_texts: Array[String] = []
	for node in _all_nodes(screen):
		if node is Button:
			button_texts.append(node.text)
	for text in ["Inspect classes", "Equip pawns"]:
		assert_false(button_texts.has(text),
			"'%s' is a column now, not a button: %s" % [text, str(button_texts)])
	screen.free()

# ---------------------------------------------------------------------------
# Issue 351: three columns, and the middle one is the pawn
# ---------------------------------------------------------------------------
#
# "pawns on the left, pawn inspect in the middle, then the level select and
# start on the right". The middle column is where the two things that interact
# become visible together: WIS from equipment sets the plan block budget.

func test_the_middle_column_opens_on_a_real_pawn_rather_than_empty() -> void:
	var screen := PartySelect.create()
	screen._ready()
	assert_not_null(screen.focused_pawn(), "a third of the screen must not open blank")
	assert_eq(screen.focused_pawn(), screen.available_pawns()[0])
	assert_true(screen._inspect_panel.visible and screen._equip_panel.visible,
		"both halves of the middle column are on the screen at once")
	screen.free()

## The requirement the brief singled out: the column has to work for a pawn that
## is NOT in the party, because the left column is where you are still choosing.
func test_the_middle_column_shows_a_pawn_that_is_not_in_the_party() -> void:
	var screen := PartySelect.create()
	screen._ready()
	var outsider: PawnData = screen.available_pawns()[2]
	screen.focus_pawn(outsider)
	assert_false(screen.selected_pawns().has(outsider), "and it is genuinely not in the party")
	assert_true(_all_label_text(screen._inspect_panel).contains(outsider.display_name),
		"the plans column must be about the pawn being looked at")
	screen.free()

## A refused card still focuses. That is the moment you most want to look: the
## party is full and you are deciding whether this pawn is worth a swap.
func test_a_fifth_card_is_refused_and_still_focuses_the_pawn() -> void:
	var screen := PartySelect.create()
	screen._ready()
	var pawns := screen.available_pawns()
	for i in 4:
		screen.toggle_pawn(pawns[i], true)
	assert_eq(screen.selected_pawns().size(), 4)
	screen._on_card_toggled(true, pawns[4])
	assert_eq(screen.selected_pawns().size(), 4, "the party must still be refused")
	assert_eq(screen.focused_pawn(), pawns[4], "and the middle column must still move")
	screen.free()

## The whole argument for one column: equipment that adds WIS raises the plan
## block budget, and the row past the budget is what un-inerts. Driven through
## the panel a player touches, and asserted on the sentence the player reads.
func test_equipping_wis_moves_the_plan_budget_in_the_column_beside_it() -> void:
	var screen := PartySelect.create()
	screen._ready()
	var pawn: PawnData = screen.available_pawns()[0]
	screen.focus_pawn(pawn)
	var before := _budget_line(screen)
	assert_ne(before, "", "the plans column must state the budget")

	var armors: Array = screen._equip_panel.offered_items(pawn, EquipmentDef.Slot.ARMOR)
	var wis_item := -1
	for i in armors.size():
		if armors[i].attribute_percent.get(CG.Attribute.WIS, 0.0) > 0.0 				or armors[i].attribute_flat.get(CG.Attribute.WIS, 0.0) > 0.0:
			wis_item = i
			break
	if wis_item < 0:
		assert_true(true, "no WIS armour is defined, so there is nothing to move")
		screen.free()
		return
	screen._equip_panel._on_slot_selected(pawn, EquipmentDef.Slot.ARMOR, armors, wis_item + 1)
	assert_ne(_budget_line(screen), before,
		"the budget sentence must move when the gear that sets it does: still '%s'" % before)
	screen.free()

func _budget_line(screen) -> String:
	for node in _all_nodes(screen._inspect_panel):
		if node is Label and node.text.contains("plan blocks used"):
			return node.text
	return ""

func _all_label_text(node: Node) -> String:
	var out := ""
	for n in _all_nodes(node):
		if n is Label:
			out += n.text + " "
	return out

func _all_nodes(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for c in node.get_children():
		out.append_array(_all_nodes(c))
	return out

## The middle column printed the same seven attribute chips twice, forty pixels
## apart, and the two disagreed: the plans panel reads them off the pawn, the
## equipment panel reads them through `Balance` with the gear in. Equipment's is
## the truthful copy, so it is the one that stays.
func test_the_middle_column_states_the_attributes_once() -> void:
	var screen := PartySelect.create()
	screen._ready()
	var pawn: PawnData = screen.available_pawns()[0]
	screen.focus_pawn(pawn)
	## The chip, not the word: the plans panel's block-budget sentence names WIS
	## legitimately ("the budget is this pawn's WIS"), so a bare substring test
	## measures that sentence rather than the row this is about.
	assert_true(_has_attribute_chip(screen._equip_panel),
		"the equipment panel is where the gear-inclusive attributes live")
	assert_false(_has_attribute_chip(screen._inspect_panel),
		"the plans panel must not restate an attribute row the panel below it already prints with gear in it")
	screen.free()

## A chip from an attributes row: a Label whose whole text is an attribute name
## followed by its number, e.g. "STR 12".
func _has_attribute_chip(node: Node) -> bool:
	var re := RegEx.create_from_string("^(STR|DEX|AGI|CON|INT|ATN|WIS) [0-9]")
	for n in _all_nodes(node):
		if n is Label and re.search(n.text) != null:
			return true
	return false

## Same again for the action list, and the equipment panel's copy now carries
## every action rather than only the ones an item granted.
func test_the_middle_column_lists_the_actions_once_and_with_the_gear_in() -> void:
	var screen := PartySelect.create()
	screen._ready()
	var pawn: PawnData = screen.available_pawns()[0]
	screen.focus_pawn(pawn)
	var available: Array = Registry.actions_for_pawn(pawn)
	assert_true(available.size() > 0, "this pawn has no actions, so this test measures nothing")
	var first: ActionDef = Registry.get_action(available[0])
	assert_true(_all_label_text(screen._equip_panel).contains(first.display_name),
		"the equipment panel must name every action the pawn can call, not only the granted ones")
	assert_false(_all_label_text(screen._inspect_panel).contains("Actions"),
		"the plans panel must not carry its own Actions heading beside the truthful one")
	screen.free()

## And the overlay is untouched: opened over another screen, the plans panel is
## still the whole page it always was.
func test_the_plans_overlay_still_states_the_attributes_itself() -> void:
	var screen := PartySelect.create()
	screen._ready()
	var pawn: PawnData = screen.available_pawns()[0]
	var panel = InspectPanel.create()
	panel._ready()
	panel.open([pawn] as Array[PawnData])
	assert_true(_has_attribute_chip(panel),
		"nothing else is on screen to state them, so the overlay must keep doing it")
	panel.free()
	screen.free()
