extends "res://Tests/TestCase.gd"


## Issue 245, the player: *"I should be able to mouse over a status icon in the
## party overview and get a more indepth description of the status."*
##
## **Correcting the premise this arrived with, because it changes what was
## built**: there was already a per-status description, `Glossary.status_text`,
## and the team panel's chips already hovered and already pinned -- all of that
## landed with #113. What was missing is the half that makes it an explanation
## rather than a glossary, which is what the badge is carrying **right now**.
##
## So these tests are about the live numbers and the two ways they can lie:
## printing a number that is not a magnitude at all, and printing one that was
## true when it was pinned.

func _unit(name: String) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = 1
	u.team = CG.Team.PLAYER
	u.display_name = name
	u.hp_max = 100
	u.hp = 100
	u.alive = true
	u.pawn = PawnData.new()
	return u

# ---------------------------------------------------------------------------
# What the popup says
# ---------------------------------------------------------------------------

## The three parts, in one string: which status, what it does, what it is doing
## to this unit at this tick.
func test_the_popup_names_the_status_explains_it_and_reports_what_it_is_carrying() -> void:
	var u := _unit("Warrior")
	u.statuses[CG.Status.BLEED] = 60
	u.status_magnitude[CG.Status.BLEED] = 3.0
	var text := Glossary.status_popup_text(u, CG.Status.BLEED, 15)
	assert_false(text.contains("Bleed"),
		("the name belongs to the title on both surfaces, not to the body. " +
		"It was in both once and the pinned copy said 'Taunting' twice, which " +
		"no test saw because the string was right in both places: %s") % text)
	assert_true(text.contains(Glossary.status_text(CG.Status.BLEED)),
		"the popup dropped the general explanation")
	assert_true(text.contains("3 stacks"), "three stacks and one stack must not read the same: %s" % text)
	assert_true(text.contains("Warrior"), "the live line does not say whose status it is: %s" % text)
	# 60 - 15 = 45 ticks at 15 per second.
	assert_true(text.contains("3.0s left"), "the popup does not say how long is left: %s" % text)

## The instrument check for the assertion above. If one stack and three stacks
## produce the same string, "3 stacks" was matching something else.
func test_one_stack_and_three_stacks_do_not_read_the_same() -> void:
	var one := _unit("Warrior")
	one.statuses[CG.Status.BLEED] = 60
	one.status_magnitude[CG.Status.BLEED] = 1.0
	var three := _unit("Warrior")
	three.statuses[CG.Status.BLEED] = 60
	three.status_magnitude[CG.Status.BLEED] = 3.0
	assert_ne(Glossary.status_popup_text(one, CG.Status.BLEED, 0),
		Glossary.status_popup_text(three, CG.Status.BLEED, 0))
	assert_true(Glossary.status_popup_text(one, CG.Status.BLEED, 0).contains("1 stack,"),
		"one stack is not plural")

## A status with no magnitude gets the countdown and nothing invented.
func test_a_status_that_carries_no_magnitude_reports_only_its_countdown() -> void:
	var u := _unit("Priest")
	u.statuses[CG.Status.POISON] = 30
	var text := Glossary.status_popup_text(u, CG.Status.POISON, 0)
	assert_true(text.contains("2.0s left"), text)
	assert_false(text.contains("stack"), "poison does not stack and must not say it does: %s" % text)
	assert_false(text.contains("strength"), "poison has no strength to report: %s" % text)

## **The trap this function exists to avoid, and it is not hypothetical.**
## `status_magnitude` is one dictionary holding different kinds of number:
## TAUNTED stores the taunter's unit id and SUSTAINING stores an action. A
## generic "print the magnitude when it is not zero" publishes a unit id to the
## player as a strength. `CombatLogView` worked this out once; this is the same
## rule with one owner.
func test_a_status_whose_magnitude_is_not_a_magnitude_reports_no_number() -> void:
	var u := _unit("Geysermancer")
	u.statuses[CG.Status.TAUNTED] = 45
	u.status_magnitude[CG.Status.TAUNTED] = 7.0
	var text := Glossary.status_popup_text(u, CG.Status.TAUNTED, 0)
	assert_false(text.contains("7"),
		"unit id 7 reached the player as if it were a number about the status: %s" % text)
	assert_true(text.contains("3.0s left"), "the countdown is still real and still wanted: %s" % text)

## A unit that does not have the status gets the general sentence and no
## invented live line, which is what an inspect screen away from a fight wants.
func test_a_unit_without_the_status_gets_the_explanation_and_no_live_line() -> void:
	var u := _unit("Warrior")
	assert_eq(Glossary.status_now_text(u, CG.Status.BURN, 0), "")
	assert_eq(Glossary.status_popup_text(u, CG.Status.BURN, 0), Glossary.status_text(CG.Status.BURN))
	assert_eq(Glossary.status_now_text(null, CG.Status.BURN, 0), "",
		"a null unit must not crash the popup builder")

## A status already expired reads as none left rather than as a negative.
func test_an_expired_status_never_reports_negative_time() -> void:
	var u := _unit("Warrior")
	u.statuses[CG.Status.SHIELD] = 10
	var text := Glossary.status_now_text(u, CG.Status.SHIELD, 40)
	assert_true(text.contains("0.0s left"), text)
	assert_false(text.contains("-"), "a status past its expiry printed a negative countdown: %s" % text)

# ---------------------------------------------------------------------------
# One owner for the wording
# ---------------------------------------------------------------------------

## The combat log's magnitude wording now comes from the same function, so a log
## line and a popup cannot describe one badge two different ways. Asserted as
## the log's real output rather than by reading the call: the point of the move
## was that the log's lines do not change.
func test_the_log_and_the_popup_agree_about_what_a_badge_is_carrying() -> void:
	var view := CombatLogView.new()
	var state := CombatState.new(1)
	var u := _unit("Warrior")
	state.units.append(u)
	var e := CombatEvent.new()
	e.kind = CG.EventKind.STATUS_APPLIED
	e.source_id = -1
	e.target_id = u.id
	e.status = CG.Status.BLEED
	e.amount = 3
	assert_true(view.line_for_event(state, e).contains("(3 stacks)"),
		"the log's own wording changed: %s" % view.line_for_event(state, e))
	e.status = CG.Status.BURN
	e.amount = 18
	assert_true(view.line_for_event(state, e).contains("(strength 18)"),
		"the log's own wording changed: %s" % view.line_for_event(state, e))
	e.status = CG.Status.TAUNTED
	e.amount = 7
	assert_false(view.line_for_event(state, e).contains("7"),
		"the log published a unit id as a magnitude")
	view.free()

## `TeamStatusView.status_name` is the name four screens read. It moved into
## `Glossary` and the old entry point still answers, because a rename that
## quietly breaks a caller is the thing this project keeps paying for.
func test_the_panel_and_the_glossary_spell_a_status_the_same_way() -> void:
	for s in CG.Status.values():
		assert_eq(TeamStatusView.status_name(s), Glossary.status_name(s))

## **The defect the screenshot found and no string check could.** The chip's
## title and its body are both correct on their own; the pinned popout draws
## them one above the other and said the status's name twice. So the assertion
## is about the pair, and it counts the name in the two fields that end up in
## one box.
func test_a_chip_names_its_status_exactly_once_across_the_title_and_the_body() -> void:
	var panel := Control.new()
	panel.set_script(TeamStatusView)
	panel._ready()
	var state := CombatState.new(1)
	var u := _unit("Warrior")
	u.statuses[CG.Status.TAUNTING] = 240
	state.units.append(u)
	panel.sync(state)

	var named := 0
	var seen := 0
	for node in _descendants(panel):
		if node.get_script() == IconChip and node.visible \
				and node.kind == IconChip.Kind.STATUS:
			seen += 1
			if node.pin_title.contains("Taunting"):
				named += 1
			if node.tooltip_text.contains("Taunting"):
				named += 1
	assert_true(seen > 0, "no status chip was built, so this assertion saw nothing")
	assert_eq(named, 1, "the status is named %d times between the chip's title and its body" % named)
	panel.free()

func _descendants(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for c in node.get_children():
		out.append_array(_descendants(c))
	return out

## The hover box and the pinned popout are two renderings of one pair of
## strings, so the tooltip has to carry the title too -- it is the surface with
## no title row of its own, and dropping the name there would leave a player
## hovering an unfamiliar badge with no idea what it is called.
func test_the_hover_box_shows_the_title_the_pinned_copy_shows() -> void:
	var box := GlossaryTooltip.build("Forces nearby enemies to target this unit.", "Taunting")
	var text := ""
	for node in _descendants(box):
		if node is Label:
			text = node.text
	assert_true(text.begins_with("Taunting"), "the hover box does not name what is hovered: %s" % text)
	assert_true(text.contains("Forces nearby enemies"), text)
	box.free()

	var plain := GlossaryTooltip.build("Adds 8 hp per point.")
	var plain_text := ""
	for node in _descendants(plain):
		if node is Label:
			plain_text = node.text
	assert_true(plain_text.begins_with("Adds 8 hp per point."),
		"a caller passing no title must get exactly what it always got: %s" % plain_text)
	plain.free()

# ---------------------------------------------------------------------------
# A pinned popout stays true
# ---------------------------------------------------------------------------

func _layer() -> Control:
	var screen := Control.new()
	screen.size = Vector2(800.0, 600.0)
	var layer := Control.new()
	layer.set_script(PopoutLayer)
	layer.name = PopoutLayer.LAYER_NAME
	layer._ready()
	screen.add_child(layer)
	return screen

## **The defect this half exists to stop.** A pinned popout used to be a
## snapshot: the body was copied out of `tooltip_text` and never read again. That
## was harmless while every popout described a constant and it stops being
## harmless the moment one carries a countdown -- a pinned box reading "3.0s
## left" four seconds later is not stale, it is wrong.
##
## Reproduced in the failing direction first: without `refresh` the body is still
## the string it was pinned with, which is what the second assertion here checks
## by pinning, changing the source, and reading the body BEFORE refreshing.
func test_a_pinned_popout_is_re_read_from_the_chip_it_was_pinned_from() -> void:
	var screen := _layer()
	var layer := screen.get_child(0)
	var chip := Control.new()
	chip.set_script(IconChip)
	chip._ready()
	screen.add_child(chip)
	chip.tooltip_text = "Bleed\n\n3 stacks, 3.0s left."
	var popout: Control = PopoutHost.pin_from(chip, "Bleed", chip.tooltip_text)
	assert_true(popout != null, "nothing was pinned, so this test measures nothing")
	assert_true(popout.body_text().contains("3.0s"), popout.body_text())

	chip.tooltip_text = "Bleed\n\n3 stacks, 1.0s left."
	assert_true(popout.body_text().contains("3.0s"),
		"the popout updated without being asked, so refresh is not what is being measured")
	layer.refresh()
	assert_true(popout.body_text().contains("1.0s"),
		"the pinned popout still says what was true when it was pinned: %s" % popout.body_text())
	screen.free()

## The negative case. A popout pinned from nothing -- every popout before this
## change -- must be left exactly as it was, and one whose host has been freed
## must keep the last thing it truthfully said rather than blanking or crashing.
func test_refresh_leaves_a_sourceless_popout_alone_and_survives_a_freed_host() -> void:
	var screen := _layer()
	var layer := screen.get_child(0)
	var kept: Control = layer.pin("Strength", "Adds hp per point.", Vector2.ZERO)
	layer.refresh()
	assert_eq(kept.body_text(), "Adds hp per point.",
		"a popout with no source was rewritten by refresh")

	var chip := Control.new()
	chip.set_script(IconChip)
	chip._ready()
	screen.add_child(chip)
	chip.tooltip_text = "Bleed. 3 stacks."
	var orphan: Control = PopoutHost.pin_from(chip, "Bleed", chip.tooltip_text)
	screen.remove_child(chip)
	chip.free()
	layer.refresh()
	assert_eq(orphan.body_text(), "Bleed. 3 stacks.",
		"a popout whose chip is gone must keep what it last truthfully said")
	screen.free()
