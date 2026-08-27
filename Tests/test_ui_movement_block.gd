extends "res://Tests/TestCase.gd"

## Issue 628: `starting_actions` holds ActionDef references rather than ids, so
## a fixture needs a real object even for an action nothing registers.
## Issue 658: `range_units` etc. now read from `targeting`, which a bare
## `ActionDef` leaves null (range 0). Before, an unregistered id fell through
## every per-tick gate because `Registry.get_action` returned null for it;
## a large range keeps that same free pass now the block carries the
## resource itself.
func _fixture_action(id: StringName) -> ActionDef:
	var a := ActionDef.new()
	a.id = id
	var t := ActionTargeting.new()
	t.range_units = 9999.0
	a.targeting = t
	return a

## Issue 386. `keep_distance` (#97) and `move_into_cover` (#347) are built,
## tested and correct, and a player cannot create either: `_new_plan` builds
## only TARGETING and ACTION, there is no movement picker, and no preset plan
## carries one. That is the pawn-behaviour principle one level up -- where a
## pawn stands is decided by `DefaultBehavior` for every plan a player can
## currently write.

func _make_pawn(wis: int = 8) -> PawnData:
	var cls := ClassDef.new()
	cls.id = &"test_class"
	cls.display_name = "Test Class"
	cls.role_primary = CG.Role.DPS
	cls.style = CG.Style.MELEE
	cls.method = CG.Method.MARTIAL
	cls.starting_actions = [_fixture_action(&"test_swing")]
	cls.base_attributes = {"WIS": wis}
	var pawn := PawnData.new()
	pawn.id = &"test_pawn"
	pawn.display_name = "Test Pawn"
	pawn.pawn_class = cls
	return pawn

func _unit(id: int, team: CG.Team, pos: Vector2) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.position = pos
	u.hp_max = 100
	u.hp = 100
	u.resource_max = 100
	u.resource = 100
	u.focus_id = -1
	return u

func _state_with(a: CombatUnit, b: CombatUnit) -> CombatState:
	var state := CombatState.new(0)
	state.units.append(a)
	state.units.append(b)
	return state

## A panel with one pawn holding one freshly added plan, which is the shape a
## player reaches by pressing "+ Add a plan".
func _panel_with_one_plan(wis: int = 8) -> Array:
	var pawn := _make_pawn(wis)
	pawn.plans = []
	var panel := InspectPanel.create()
	panel._ready()
	panel.open([pawn])
	panel._add_plan(pawn)
	return [panel, pawn]

func _decide(pawn: PawnData, gap: float):
	var attacker := _unit(0, CG.Team.PLAYER, Vector2.ZERO)
	attacker.pawn = pawn
	var enemy := _unit(1, CG.Team.ENEMY, Vector2(gap, 0.0))
	return PlanInterpreter.decide(_state_with(attacker, enemy), attacker)

## ---------------------------------------------------------------------------
## The picker exists and offers exactly what the interpreter accepts

func test_the_movement_picker_offers_no_movement_plus_every_interpreter_op() -> void:
	var pair := _panel_with_one_plan()
	var picker: OptionButton = pair[0]._movement_picker(pair[1], pair[1].plans[0])
	assert_eq(picker.item_count, BlockCatalog.MOVEMENT_OPS.size() + 1,
		"every op the interpreter accepts, plus leaving it to the default")
	assert_true(picker.get_item_text(0).findn("default") >= 0 or picker.get_item_text(0).findn("not") >= 0,
		"entry 0 is the no-movement one: %s" % picker.get_item_text(0))
	picker.free()
	pair[0].free()

## ---------------------------------------------------------------------------
## And it reaches the interpreter, which is the only thing that settles it

func test_picking_keep_distance_makes_a_block_the_interpreter_actually_runs() -> void:
	var pair := _panel_with_one_plan()
	var panel = pair[0]
	var pawn: PawnData = pair[1]

	## The pair, first: with no movement block the plan swings and leaves where
	## the pawn stands to DefaultBehavior. That is the defect, stated.
	var before = _decide(pawn, 10.0)
	assert_eq(before.action_id, &"test_swing", "without a movement block a plan only acts")

	panel._set_movement(pawn, pawn.plans[0], &"keep_distance")
	var intent = _decide(pawn, 10.0)
	assert_not_null(intent, "a movement block must fire, not just appear")
	assert_eq(intent.kind, CG.IntentKind.MOVE_TO,
		"standing inside the held distance, the pawn backs off")
	panel.free()

func test_picking_move_into_cover_reaches_the_interpreter_too() -> void:
	var pair := _panel_with_one_plan()
	pair[0]._set_movement(pair[1], pair[1].plans[0], &"move_into_cover")
	var block = _movement_block(pair[1].plans[0])
	assert_not_null(block, "the block must exist")
	assert_true(block is MoveIntoCoverBlock)
	_decide(pair[1], 200.0)
	pair[0].free()

func test_the_distance_is_editable_and_the_interpreter_reads_the_edit() -> void:
	var pair := _panel_with_one_plan()
	var panel = pair[0]
	var pawn: PawnData = pair[1]
	panel._set_movement(pawn, pawn.plans[0], &"keep_distance")
	var block = _movement_block(pawn.plans[0])

	panel._set_operand(block, &"range_units", 300.0)
	var far = _decide(pawn, 100.0)
	assert_eq(far.kind, CG.IntentKind.MOVE_TO, "100 units from a target it wants 300 from: back off")

	panel._set_operand(block, &"range_units", 10.0)
	var near = _decide(pawn, 100.0)
	assert_eq(near.kind, CG.IntentKind.MOVE_TO, "100 units from a target it wants 10 from: close in")
	assert_true(near.destination.length() < 100.0, "closing in moves toward the target: %s" % near.destination)
	panel.free()

## ---------------------------------------------------------------------------
## Taking it off again

func test_picking_no_movement_removes_the_block_and_gives_its_budget_back() -> void:
	var pair := _panel_with_one_plan()
	var panel = pair[0]
	var pawn: PawnData = pair[1]
	var before := pawn.plans[0].block_count()

	panel._set_movement(pawn, pawn.plans[0], &"keep_distance")
	assert_eq(pawn.plans[0].block_count(), before + 1, "a movement block costs 1, like a target and a skill")

	panel._set_movement(pawn, pawn.plans[0], InspectPanel.NO_MOVEMENT)
	assert_eq(pawn.plans[0].block_count(), before, "removing it gives the block back")
	assert_eq(_movement_block(pawn.plans[0]), null)
	var intent = _decide(pawn, 10.0)
	assert_eq(intent.action_id, &"test_swing", "with the block gone the plan acts again")
	panel.free()

func test_swapping_between_movement_ops_does_not_charge_a_second_block() -> void:
	var pair := _panel_with_one_plan()
	var panel = pair[0]
	var pawn: PawnData = pair[1]
	panel._set_movement(pawn, pawn.plans[0], &"keep_distance")
	var after_first := pawn.plans[0].block_count()
	panel._set_movement(pawn, pawn.plans[0], &"move_into_cover")
	assert_eq(pawn.plans[0].block_count(), after_first, "a swap replaces the block, it does not add one")
	panel.free()

## ---------------------------------------------------------------------------
## The budget, which rook asked to be checked rather than assumed

## WIS 2 buys exactly one two-block plan and leaves nothing. The picker must
## say why rather than silently doing nothing -- issue 95's own failure.
func test_the_picker_is_disabled_with_a_reason_when_no_block_is_free() -> void:
	var pair := _panel_with_one_plan(2)
	var pawn: PawnData = pair[1]
	assert_eq(Balance.plan_block_budget(pawn) - pair[0]._blocks_used(pawn), 0, "the fixture must be full")
	var picker: OptionButton = pair[0]._movement_picker(pawn, pawn.plans[0])
	assert_true(picker.disabled, "no free block, so nothing may be picked")
	assert_ne(picker.tooltip_text, "", "and it says why")
	picker.free()
	pair[0].free()

## The pair: with a block free it is live.
func test_the_picker_is_live_when_a_block_is_free() -> void:
	var pair := _panel_with_one_plan(8)
	var picker: OptionButton = pair[0]._movement_picker(pair[1], pair[1].plans[0])
	assert_false(picker.disabled)
	picker.free()
	pair[0].free()

## A plan that already carries one is never locked out by its own cost: taking
## it off is the way back under budget.
func test_a_plan_that_already_has_movement_can_still_edit_it_at_a_full_budget() -> void:
	var pair := _panel_with_one_plan(3)
	var panel = pair[0]
	var pawn: PawnData = pair[1]
	panel._set_movement(pawn, pawn.plans[0], &"keep_distance")
	assert_eq(panel._blocks_used(pawn), 3, "two blocks plus movement")
	var picker: OptionButton = panel._movement_picker(pawn, pawn.plans[0])
	assert_false(picker.disabled, "a row carrying one must always be able to take it off again")
	picker.free()
	panel.free()

## ---------------------------------------------------------------------------
## What the screen tells the player it costs

## Issue 590 moved the cost rules onto the budget counter's mouseover, so the
## sentence is read on hover rather than off the panel. What it must still do
## is name the movement block: a block that costs 1 and is nowhere in the bill
## is a charge with no line on it.
func test_the_budget_sentence_names_the_movement_block() -> void:
	var pair := _panel_with_one_plan()
	var text := _labels(pair[0]._detail_box) + _tooltips(pair[0]._detail_box)
	assert_true(text.findn("movement") >= 0,
		"a block that costs 1 and is not in the sentence is a bill with no line on it: %s" % text)
	pair[0].free()

func _tooltips(node: Node) -> String:
	var out := ""
	if node is Control:
		out += node.tooltip_text + " "
	for child in node.get_children():
		out += _tooltips(child)
	return out

func _movement_block(plan):
	for block in plan.blocks:
		if block is MovementBlock:
			return block
	return null

func _labels(node: Node) -> String:
	var out := ""
	if node is Label:
		out += node.text + " "
	for child in node.get_children():
		out += _labels(child)
	return out

## Through the control a player uses, not the handler under it. Two hundred and
## fifty-two tests once passed while a product's primary button ran the wrong
## program, because every one of them called the function underneath.
func test_selecting_the_op_on_the_picker_itself_creates_the_block() -> void:
	var pair := _panel_with_one_plan()
	var pawn: PawnData = pair[1]
	var picker: OptionButton = pair[0]._movement_picker(pawn, pawn.plans[0])
	var wanted: int = BlockCatalog.MOVEMENT_OPS.find(&"keep_distance")
	picker.item_selected.emit(wanted + 1)
	var block = _movement_block(pawn.plans[0])
	assert_not_null(block, "picking the entry must create the block")
	assert_true(block is KeepDistanceBlock)
	picker.free()
	pair[0].free()

## And back off it, on the same control.
func test_selecting_the_first_entry_on_the_picker_itself_removes_the_block() -> void:
	var pair := _panel_with_one_plan()
	var pawn: PawnData = pair[1]
	pair[0]._set_movement(pawn, pawn.plans[0], &"keep_distance")
	var picker: OptionButton = pair[0]._movement_picker(pawn, pawn.plans[0])
	picker.item_selected.emit(0)
	assert_eq(_movement_block(pawn.plans[0]), null)
	picker.free()
	pair[0].free()

## A fixed 96px SpinBox inside the narrow share clipped "Hold 120 units from
## the target" down to the letter H on a real capture.
func test_a_movement_block_carrying_a_value_gets_a_wider_share_of_the_row() -> void:
	var pair := _panel_with_one_plan()
	var panel = pair[0]
	var pawn: PawnData = pair[1]
	var bare: Control = panel._movement_editor(pawn, pawn.plans[0])
	panel._set_movement(pawn, pawn.plans[0], &"keep_distance")
	var with_value: Control = panel._movement_editor(pawn, pawn.plans[0])
	assert_true(with_value.size_flags_stretch_ratio > bare.size_flags_stretch_ratio,
		"a chip sharing its share with a SpinBox needs more of the row")
	bare.free()
	with_value.free()
	panel.free()

## And `move_into_cover` takes no argument, so it keeps the narrow share.
func test_a_movement_block_with_no_value_keeps_the_narrow_share() -> void:
	var pair := _panel_with_one_plan()
	var panel = pair[0]
	var pawn: PawnData = pair[1]
	panel._set_movement(pawn, pawn.plans[0], &"move_into_cover")
	var editor: Control = panel._movement_editor(pawn, pawn.plans[0])
	assert_almost_eq(editor.size_flags_stretch_ratio, InspectPanel.MOVEMENT_SHARE, 0.0001)
	editor.free()
	panel.free()
