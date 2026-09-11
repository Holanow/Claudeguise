extends "res://Tests/TestCase.gd"

## Issue 892: the library auto-opens as a fresh pawn's teaching state, so its
## first row has to be on screen **without scrolling**, which is the assertion
## every probe here misses by calling `ensure_control_visible` first.

## Issue 826's three sizes are two layouts: `canvas_items`/`expand` stretch maps
## 844x390 onto the same 1558x720 viewport, measured with the windowed probe.
const SIZES := [Vector2(1280.0, 720.0), Vector2(1558.0, 720.0)]

## What PresetLibraryProbe reads for `DetailScroll` in a real window at both
## viewport widths, and the check that this file lays out the same screen.
const PROBE_FOLD_HEIGHT := 372.0

## Every class ships a library, and the rows are different lengths, so the one
## the roster happens to roll first is not the measurement.
const CLASS_IDS := [&"warrior", &"priest", &"geysermancer", &"siege_master", &"abomination"]

## Container sorting is deferred to a frame the synchronous suite never runs, so
## it is driven by hand here, parents first.
func _sort(node: Node) -> void:
	if node is Container:
		node.notification(Container.NOTIFICATION_SORT_CHILDREN)
	for child in node.get_children():
		_sort(child)

## An autowrap Label caches its height against the width it had when something
## first asked, and `update_minimum_size` clears that cache on a deferred call
## no synchronous test reaches -- so every control is given its width before
## the first query rather than after it.
func _seed_widths(node: Control, width: float) -> void:
	node.size.x = width
	## `get_line_count` is what re-shapes the text at the width just given it.
	if node is Label:
		(node as Label).get_line_count()
	var row := node as HBoxContainer
	if row == null:
		for child in node.get_children():
			if child is Control:
				_seed_widths(child, width)
		return
	var separation := float(row.get_theme_constant("separation"))
	var kids: Array[Control] = []
	for child in row.get_children():
		if child is Control and (child as Control).visible:
			kids.append(child)
	var fixed := 0.0
	var ratios := 0.0
	for kid in kids:
		if kid.size_flags_horizontal & Control.SIZE_EXPAND:
			ratios += kid.size_flags_stretch_ratio
		else:
			fixed += maxf(kid.get_minimum_size().x, kid.custom_minimum_size.x)
	var spare: float = maxf(0.0, width - fixed - separation * maxf(0.0, kids.size() - 1))
	for kid in kids:
		if kid.size_flags_horizontal & Control.SIZE_EXPAND:
			_seed_widths(kid, spare * kid.size_flags_stretch_ratio / maxf(ratios, 1.0))
		else:
			_seed_widths(kid, maxf(kid.get_minimum_size().x, kid.custom_minimum_size.x))

## The party screen a new player lands on, laid out at `size` with nothing
## scrolled.
func _party_screen(size: Vector2) -> PartySelect:
	var screen: PartySelect = in_tree(PartySelect.create())
	screen.size = size
	_sort(screen)
	return screen

func _walk(node: Node, out: Array = []) -> Array:
	out.append(node)
	for child in node.get_children():
		_walk(child, out)
	return out

func _first_add(panel) -> Button:
	for node in _walk(panel._detail_box):
		if node is Button and node.text == InspectPanel.LIBRARY_ADD:
			return node
	return null

## How far the first library row's bottom edge falls past the bottom of the
## scroll's visible rect, unscrolled. Zero or less is on screen.
func _below_the_fold(screen: PartySelect, pawn: PawnData) -> float:
	var panel = screen._inspect_panel
	## Rebuilt once the column's real width is known, so the fresh controls are
	## measured at that width rather than at zero.
	panel.show_pawn(pawn)
	_seed_widths(panel._detail_box, panel._detail_scroll.size.x)
	panel._apply_detail_scale()
	_sort(screen)
	var add := _first_add(panel)
	if add == null:
		return NAN
	return add.get_global_rect().end.y - panel._detail_scroll.get_global_rect().end.y

func _starter(class_id: StringName) -> PawnData:
	return PawnFactory.make_starter_pawn(class_id, StringName("%s_0" % class_id), String(class_id).capitalize())

## The premise: a fresh pawn, the library open by itself, nothing scrolled.
func test_the_teaching_state_is_the_one_measured() -> void:
	var screen := _party_screen(SIZES[0])
	var panel = screen._inspect_panel
	var pawn := _starter(CLASS_IDS[0])
	panel.show_pawn(pawn)
	assert_true(pawn.plans.is_empty(), "a fresh pawn carries no rows")
	assert_true(panel._library_open, "so the library opens by itself")
	assert_eq(panel._detail_scroll.scroll_vertical, 0, "and nothing has scrolled")
	assert_true(_first_add(panel) != null, "the open library offers at least one Add")

## Laying out by hand has to produce the windowed probe's geometry or it is
## measuring nothing.
func test_the_hand_laid_out_fold_matches_the_windowed_probe() -> void:
	for size in SIZES:
		var screen := _party_screen(size)
		var fold: Rect2 = screen._inspect_panel._detail_scroll.get_global_rect()
		assert_true(absf(fold.size.y - PROBE_FOLD_HEIGHT) <= 1.0,
			"%s: the scroll is %s, the probe reads %.0f px tall" % [size, fold, PROBE_FOLD_HEIGHT])
		assert_true(fold.size.x > 100.0, "%s: the scroll has a real width: %s" % [size, fold])

## The issue itself. Reachable-after-scrolling is what the probes assert, and
## asserting it is what hid a 152 px drop between #470 and #892.
func test_the_first_library_row_is_inside_the_fold_unscrolled() -> void:
	for size in SIZES:
		var screen := _party_screen(size)
		for class_id in CLASS_IDS:
			var below := _below_the_fold(screen, _starter(class_id))
			assert_true(below <= 0.0,
				"%s %s: the first library row ends %.0f px below the fold" % [size, class_id, below])
		## The pawn the screen actually rolled, whose name is longer than a
		## class id and whose heading can wrap where the fixtures above cannot.
		var rolled := _below_the_fold(screen, screen.focused_pawn())
		assert_true(rolled <= 0.0,
			"%s %s: the first library row ends %.0f px below the fold" % [
				size, screen.focused_pawn().display_name, rolled])

## Issue 920: the trait strip rides the pawn's name rather than taking a row,
## because a row is 33 px and the margin above is 25. Measured: two chips
## squeeze "Siege Master" into two lines of 30 px type and cost 49 px, so the
## name is set to ellipsize instead. Additive to the assertion above -- the
## fixtures there carry at most one verb, and four of them carry none.
func test_a_pawn_wearing_two_verbs_does_not_push_the_library_under() -> void:
	for size in SIZES:
		var screen := _party_screen(size)
		for class_id in CLASS_IDS:
			var pawn := _starter(class_id)
			pawn.accessory = ItemLibrary.get_equipment(&"censer")
			assert_false(InspectPanel.trait_lines(pawn).is_empty(),
				"%s: the fixture has to carry a verb or this proves nothing" % class_id)
			var below := _below_the_fold(screen, pawn)
			assert_true(below <= 0.0,
				"%s %s: the first library row ends %.0f px below the fold" % [size, class_id, below])
