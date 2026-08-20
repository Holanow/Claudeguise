extends "res://Tests/TestCase.gd"


## Issue 112: every popout outside a menu is pinnable and draggable, as one
## mechanism rather than per call site.
##
## The mechanism is the thing under test, not any one popout: a host that has a
## glossary sentence gets pinning by being a GlossaryLabel, a GlossaryButton or
## a PartyCard, which is every hoverable control the project has.

## A screen with a control on it. `PopoutLayer.of` walks to the outermost
## Control, so a host needs a real ancestor for the layer to land anywhere
## sensible -- the same shape the real screens have.
func _screen_with(host: Control) -> Control:
	var screen := Control.new()
	screen.size = Vector2(800.0, 600.0)
	screen.add_child(host)
	return screen

func _click(button: int) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	return event

func _chip(text: String, tooltip: String) -> Label:
	var chip := Label.new()
	chip.set_script(GlossaryLabel)
	chip.mouse_filter = Control.MOUSE_FILTER_STOP
	chip.text = text
	chip.tooltip_text = tooltip
	return chip

func _layer_of(screen: Control) -> Control:
	for child in screen.get_children():
		if child is Control and child.name == PopoutLayer.LAYER_NAME:
			return child
	return null

# ---------------------------------------------------------------------------
# The gesture
# ---------------------------------------------------------------------------

func test_a_right_click_on_a_glossary_chip_pins_a_popout() -> void:
	var chip := _chip("STR 12", "Adds 8 hp per point.")
	var screen := _screen_with(chip)
	chip._gui_input(_click(MOUSE_BUTTON_RIGHT))

	var layer := _layer_of(screen)
	assert_not_null(layer, "a pin must create the screen's popout layer")
	assert_eq(layer.pinned_count(), 1)
	var popout: Control = layer.pinned()[0]
	assert_eq(popout.title_text(), "STR 12", "the chip's own text titles the popout")
	assert_eq(popout.body_text(), "Adds 8 hp per point.")
	screen.free()

## The negative half. A left-click is what every other thing on these screens
## uses, and pinning on it would make the feature fire constantly -- which,
## per rule 4 on the board, is the failure mode that turns a feature into
## furniture faster than one that never fires.
func test_a_left_click_does_not_pin() -> void:
	var chip := _chip("STR 12", "Adds 8 hp per point.")
	var screen := _screen_with(chip)
	chip._gui_input(_click(MOUSE_BUTTON_LEFT))
	assert_eq(_layer_of(screen), null, "a left-click must not pin anything")
	screen.free()

## A control with nothing to say must not pin an empty box. Every glossary host
## is built by `set_script` on a plain node, so a host whose `tooltip_text` was
## never set is a reachable state rather than a hypothetical.
func test_a_host_with_no_glossary_text_pins_nothing() -> void:
	var chip := _chip("Untagged", "")
	var screen := _screen_with(chip)
	chip._gui_input(_click(MOUSE_BUTTON_RIGHT))
	assert_eq(_layer_of(screen), null, "an empty popout is worse than none")
	screen.free()

## The host that proves the gesture had to be right-click: this button starts
## the fight. A pin must not also press it.
func test_pinning_a_glossary_button_does_not_press_it() -> void:
	var button := Button.new()
	button.set_script(GlossaryButton)
	button.text = "Start Fight"
	button.tooltip_text = "Runs one fight with the current party and seed, right now."
	var screen := _screen_with(button)
	var presses := [0]
	button.pressed.connect(func(): presses[0] += 1)

	button._gui_input(_click(MOUSE_BUTTON_RIGHT))
	assert_eq(presses[0], 0, "a right-click must not start the fight")
	assert_eq(_layer_of(screen).pinned_count(), 1, "and must pin")
	screen.free()

## And the other way round on the card: picking a pawn still works.
func test_a_party_card_still_selects_on_a_left_click_and_pins_on_a_right_one() -> void:
	var card := Control.new()
	card.set_script(PartyCard)
	card._ready()
	var cls := ClassDef.new()
	cls.id = &"warrior"
	cls.display_name = "Warrior"
	cls.role_primary = CG.Role.TANK
	cls.style = CG.Style.MELEE
	cls.method = CG.Method.MARTIAL
	card.class_def = cls
	var screen := _screen_with(card)

	var toggles := [0]
	card.toggled.connect(func(_pressed): toggles[0] += 1)
	card._gui_input(_click(MOUSE_BUTTON_LEFT))
	assert_eq(toggles[0], 1, "left-click must still pick the pawn")
	assert_eq(_layer_of(screen), null, "and must not pin")

	card._gui_input(_click(MOUSE_BUTTON_RIGHT))
	assert_eq(toggles[0], 1, "right-click must not pick the pawn")
	var popout: Control = _layer_of(screen).pinned()[0]
	assert_eq(popout.title_text(), "Warrior", "a card draws its name rather than carrying a Label, so the class names the popout")
	screen.free()

# ---------------------------------------------------------------------------
# Several at once, which is the point of the feature
# ---------------------------------------------------------------------------

## The issue's own reasoning: pinning is worth building because it lets two
## things be compared, and one popout replacing another would be the same
## tooltip with extra steps.
func test_two_popouts_can_be_pinned_at_once_and_do_not_land_on_top_of_each_other() -> void:
	var one := _chip("STR 12", "Adds 8 hp per point.")
	var two := _chip("CON 14", "Adds 12 hp per point.")
	var screen := _screen_with(one)
	screen.add_child(two)
	one._gui_input(_click(MOUSE_BUTTON_RIGHT))
	two._gui_input(_click(MOUSE_BUTTON_RIGHT))

	var layer := _layer_of(screen)
	assert_eq(layer.pinned_count(), 2, "pinning a second must not replace the first")
	assert_ne(layer.pinned()[0].position, layer.pinned()[1].position,
		"two popouts stacked exactly is one popout as far as a player can tell")
	screen.free()

func test_closing_a_popout_removes_it() -> void:
	var chip := _chip("STR 12", "Adds 8 hp per point.")
	var screen := _screen_with(chip)
	chip._gui_input(_click(MOUSE_BUTTON_RIGHT))
	var layer := _layer_of(screen)
	layer.pinned()[0]._on_close()
	# _on_close uses queue_free(), which does not flush inside one call; the
	# node is gone from the tree's point of view once it is queued.
	assert_true(layer.pinned()[0].is_queued_for_deletion(), "closing must remove the popout")
	screen.free()

# ---------------------------------------------------------------------------
# Dragging
# ---------------------------------------------------------------------------

func test_a_popout_moves_where_it_is_dragged() -> void:
	var chip := _chip("STR 12", "Adds 8 hp per point.")
	var screen := _screen_with(chip)
	chip._gui_input(_click(MOUSE_BUTTON_RIGHT))
	var popout: Control = _layer_of(screen).pinned()[0]
	popout.move_to(Vector2(120.0, 90.0))
	assert_eq(popout.position, Vector2(120.0, 90.0))
	screen.free()

## "A drag that drops the popout behind the arena" is one of the two failures
## the issue names as invisible to a unit test that never opens a window. It is
## not invisible to this one: a popout dragged past an edge is a popout that
## cannot be picked up again, so the clamp is the feature, not politeness.
func test_a_popout_cannot_be_dragged_off_the_screen() -> void:
	var chip := _chip("STR 12", "Adds 8 hp per point.")
	var screen := _screen_with(chip)
	var layer: Control = PopoutHost.pin_from(chip, "STR 12", "Adds 8 hp per point.").get_parent()
	layer.size = Vector2(800.0, 600.0)
	var popout: Control = layer.pinned()[0]
	popout.size = Vector2(200.0, 100.0)

	popout.move_to(Vector2(-500.0, -500.0))
	assert_eq(popout.position, Vector2.ZERO, "dragged past the top-left, it stops at the corner")
	popout.move_to(Vector2(5000.0, 5000.0))
	# Read back rather than written as a literal: a popout will not shrink below
	# the body label's own 260-wide minimum, so its real size is not the 200 set
	# above and a hand-typed expectation here would be testing arithmetic
	# against itself.
	assert_eq(popout.position, layer.size - popout.size,
		"dragged past the bottom-right, it stops at its own size from the edge")
	assert_true(popout.position.x > 0.0 and popout.position.y > 0.0,
		"and that has to be a real corner, not the origin the clamp fell back to")
	screen.free()

# ---------------------------------------------------------------------------
# mouse_filter, which the issue names as the trap and which has already cost
# this project one shipped-but-unreachable feature.
# ---------------------------------------------------------------------------

## The layer covers the whole screen. STOP or PASS on it would put a
## transparent sheet over every control on every screen -- the same defect as
## PR #76's, pointed the other way.
func test_the_layer_does_not_cover_the_screen_underneath_it() -> void:
	var chip := _chip("STR 12", "Adds 8 hp per point.")
	var screen := _screen_with(chip)
	chip._gui_input(_click(MOUSE_BUTTON_RIGHT))
	assert_eq(_layer_of(screen).mouse_filter, Control.MOUSE_FILTER_IGNORE,
		"a full-screen layer that stops input makes the game unclickable")
	screen.free()

## The popout itself must stop input or a drag never reaches it, and its labels
## must ignore input or they swallow the drag first. `Label` defaults to IGNORE
## and `Control` defaults to STOP, which is exactly the mismatch that made every
## glossary chip unhoverable until PR #76, so neither is left to a default.
func test_the_popout_takes_input_and_its_labels_do_not() -> void:
	var popout := Popout.build("STR 12", "Adds 8 hp per point.")
	assert_eq(popout.mouse_filter, Control.MOUSE_FILTER_STOP, "a popout that ignores input cannot be dragged")
	var labels := 0
	for node in _all(popout):
		if node is Label:
			assert_eq(node.mouse_filter, Control.MOUSE_FILTER_IGNORE,
				"a Label inside the popout swallows the drag before the panel sees it")
			labels += 1
		if node is Button:
			assert_eq(node.mouse_filter, Control.MOUSE_FILTER_STOP,
				"the close button must beat the drag")
	assert_eq(labels, 2, "title and body")
	popout.free()

func _all(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for child in node.get_children():
		out.append_array(_all(child))
	return out

# ---------------------------------------------------------------------------
# Discoverability
# ---------------------------------------------------------------------------

## A gesture nobody can find is not a feature. The hint goes in the hover box,
## which is the one place a player is already reading at the moment the gesture
## becomes useful -- and it is added by `GlossaryTooltip` rather than written
## into fifteen `tooltip_text` strings, so a new hoverable control cannot ship
## without it.
func test_the_hover_box_says_how_to_pin() -> void:
	var box := GlossaryTooltip.build("Adds 8 hp per point.")
	var text := ""
	for node in _all(box):
		if node is Label:
			text += node.text
	assert_true(text.contains("Adds 8 hp per point."), "the glossary sentence must still be the box")
	assert_true(text.contains(PopoutHost.PIN_HINT), "and the box must name the gesture that pins it")
	# The hint has to name the button the code actually reads, or it teaches a
	# gesture that does nothing -- which is worse than no hint.
	assert_true(PopoutHost.PIN_HINT.to_lower().contains("right-click"),
		"the code pins on MOUSE_BUTTON_RIGHT, so the hint must say right-click")
	box.free()

## The hint belongs to the box, not to the data. Every caller and several tests
## read `tooltip_text` as the glossary sentence, and it still is one.
func test_the_hint_is_not_written_into_the_glossary_text_itself() -> void:
	var chip := _chip("STR 12", "Adds 8 hp per point.")
	assert_eq(chip.tooltip_text, "Adds 8 hp per point.")
	chip.free()

# ---------------------------------------------------------------------------
# Reachability
# ---------------------------------------------------------------------------

## Ten features have shipped here built and unreachable, and this issue exists
## partly because of one of them. Driven on the real screen, through the real
## control: right-click the button a player meets first and read the popout back
## off the screen's own tree.
func test_a_popout_can_be_pinned_on_the_real_party_select_screen() -> void:
	var screen := PartySelect.create()
	screen._ready()
	var host: Button = null
	for node in _all(screen):
		if node is Button and node.text.begins_with("Start Fight") or (node is Button and node.text.begins_with("Pick a party to fight")):
			host = node
	assert_not_null(host, "party select must carry the glossary button this pins from")
	host._gui_input(_click(MOUSE_BUTTON_RIGHT))

	var layer := _layer_of(screen)
	assert_not_null(layer, "the layer must be created on the real screen, with nothing wired by hand")
	assert_eq(layer.pinned_count(), 1)
	assert_true(layer.pinned()[0].body_text().contains("one fight"),
		"and must carry that button's own glossary sentence")
	screen.free()

## A popout is pinned to the screen, not to the panel it came from. The plan
## editor frees every child of its detail box on every edit, so a popout parented
## anywhere inside it would vanish the moment the player changed a block -- which
## is the case pinning exists for.
func test_a_popout_outlives_the_panel_it_was_pinned_from() -> void:
	var chip := _chip("STR 12", "Adds 8 hp per point.")
	var panel := Control.new()
	panel.add_child(chip)
	var screen := Control.new()
	screen.size = Vector2(800.0, 600.0)
	screen.add_child(panel)

	chip._gui_input(_click(MOUSE_BUTTON_RIGHT))
	var layer := _layer_of(screen)
	assert_not_null(layer, "the layer belongs to the screen, not to the panel")
	assert_eq(layer.get_parent(), screen)
	panel.free()
	assert_eq(layer.pinned_count(), 1, "freeing the panel must not take the popout with it")
	screen.free()
