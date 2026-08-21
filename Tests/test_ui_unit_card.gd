extends "res://Tests/TestCase.gd"

const BattleScene := preload("res://Scenes/Battle.tscn")

## Issue 377: nothing in the arena was clickable, so a player watching a pawn
## could not ask it why.

func _make_party() -> Array[PawnData]:
	var cls := ClassDef.new()
	cls.id = &"test_class"
	cls.display_name = "Test Class"
	var pawn := PawnData.new()
	pawn.id = &"test_pawn"
	pawn.display_name = "Test Pawn"
	pawn.pawn_class = cls
	var out: Array[PawnData] = [pawn]
	return out

func _make_encounter() -> Encounter:
	var e := Encounter.new()
	e.enemy_spawns = [{"enemy_id": &"test_dummy", "position": Vector2(300.0, 0.0)}]
	e.party_spawns = [Vector2(-300.0, 0.0)]
	return e

func _spawn_battle_view():
	var view = BattleScene.instantiate()
	view._ready()
	var config := RunConfig.new()
	config.seed = 1
	config.party = _make_party()
	view.config = config
	view.begin_with_encounter(config, _make_encounter())
	return view

func _unit_named(state: CombatState, name: String) -> CombatUnit:
	for u in state.units:
		if u.display_name == name:
			return u
	return null

## ---------------------------------------------------------------------------
## Picking

func test_a_point_on_a_body_picks_that_unit() -> void:
	var view = _spawn_battle_view()
	for u in view.state.units:
		assert_eq(BattleView.unit_at(view.state, u.position), u.id,
			"a click on %s's own centre must pick it" % u.display_name)
	view.free()

func test_a_point_in_empty_space_picks_nothing() -> void:
	var view = _spawn_battle_view()
	assert_eq(BattleView.unit_at(view.state, Vector2(0.0, -400.0)), -1)
	view.free()

func test_a_dead_unit_cannot_be_picked() -> void:
	var view = _spawn_battle_view()
	var u: CombatUnit = view.state.units[0]
	u.hp = 0
	u.alive = false
	assert_eq(BattleView.unit_at(view.state, u.position), -1)
	view.free()

## The playtester's own sentence: "I still do not know if it is a wall, a
## geyser, or the Warrior's block." The plate is part of the shielder.
func test_a_point_on_the_shield_wall_picks_the_shielder() -> void:
	var view = _spawn_battle_view()
	var u: CombatUnit = view.state.units[0]
	u.facing = Vector2.RIGHT
	u.statuses[CG.Status.SHIELDING] = view.state.tick + 100
	var standoff := u.radius * UnitView.DISPLAY_SCALE
	var on_plate := u.position + Vector2(standoff + ShieldWall.DEPTH * 0.5, ShieldWall.half_width() * 0.8)
	assert_eq(BattleView.unit_at(view.state, on_plate), u.id)
	view.free()

func test_the_shield_wall_is_not_pickable_when_the_status_is_down() -> void:
	var view = _spawn_battle_view()
	var u: CombatUnit = view.state.units[0]
	u.facing = Vector2.RIGHT
	var standoff := u.radius * UnitView.DISPLAY_SCALE
	var on_plate := u.position + Vector2(standoff + ShieldWall.DEPTH * 0.5, ShieldWall.half_width() * 0.8)
	assert_eq(BattleView.unit_at(view.state, on_plate), -1)
	view.free()

## ---------------------------------------------------------------------------
## What the card says

func test_the_card_names_the_unit_and_its_side() -> void:
	var view = _spawn_battle_view()
	var u: CombatUnit = view.state.units[0]
	assert_true(UnitCard.title_text(u).begins_with(u.display_name))
	assert_true(UnitCard.side_text(u).findn("party") >= 0)
	view.free()

## "OOM" was three letters of jargon pointing at a stat with no bar on screen.
func test_an_empty_resource_is_spelled_out_rather_than_abbreviated() -> void:
	var view = _spawn_battle_view()
	var u: CombatUnit = view.state.units[0]
	u.resource_max = 80
	u.resource = 0
	u.resource_kind = CG.ResourceKind.MANA
	var text := "\n".join(UnitCard.lines(view.state, u))
	assert_true(text.findn("mana") >= 0, "must name the resource: %s" % text)
	assert_true(text.find("OOM") < 0, "the card explains OOM rather than repeating it")
	assert_true(text.findn("0 of 80") >= 0, "must show the numbers: %s" % text)
	view.free()

func test_a_unit_with_no_resource_says_so_rather_than_showing_nothing() -> void:
	var view = _spawn_battle_view()
	var u: CombatUnit = view.state.units[0]
	u.resource_max = 0
	var text := "\n".join(UnitCard.lines(view.state, u))
	assert_true(text.findn("no resource") >= 0, text)
	view.free()

## Seven badges with no key. The card names every one of them, including the
## ones the two-badge row drops.
func test_every_status_is_named_and_explained_including_the_hidden_ones() -> void:
	var view = _spawn_battle_view()
	var u: CombatUnit = view.state.units[0]
	for s in [CG.Status.BLEED, CG.Status.BURN, CG.Status.SLOWED, CG.Status.HASTE]:
		u.statuses[s] = view.state.tick + 60
	u.status_magnitude[CG.Status.BLEED] = 11.0
	var text := "\n".join(UnitCard.lines(view.state, u))
	for s in [CG.Status.BLEED, CG.Status.BURN, CG.Status.SLOWED, CG.Status.HASTE]:
		assert_true(text.find(Glossary.status_name(s)) >= 0,
			"%s is on the unit and must be on the card" % Glossary.status_name(s))
		assert_true(text.find(Glossary.status_text(s)) >= 0,
			"%s must carry its explanation, not just its name" % Glossary.status_name(s))
	assert_true(text.find("11 stacks") >= 0, "eleven stacks of Bleed showed nowhere: %s" % text)
	view.free()

## The dark-cyan shape following the Warrior, named.
func test_a_shielding_unit_names_its_directional_block() -> void:
	var view = _spawn_battle_view()
	var u: CombatUnit = view.state.units[0]
	u.statuses[CG.Status.SHIELDING] = view.state.tick + 100
	var text := "\n".join(UnitCard.lines(view.state, u))
	assert_true(text.find(Glossary.status_name(CG.Status.SHIELDING)) >= 0, text)
	view.free()

## The circled (2) and (3) on the Rat King and the Warden.
func test_the_card_says_how_many_units_are_aiming_at_this_one() -> void:
	var view = _spawn_battle_view()
	var target: CombatUnit = view.state.units[0]
	var count := 0
	for other in view.state.units:
		if other.id != target.id:
			other.focus_id = target.id
			count += 1
	assert_true(count > 0, "the fixture needs at least one other unit")
	var text := "\n".join(UnitCard.lines(view.state, target))
	assert_true(text.findn("aiming at") >= 0, text)
	assert_true(text.find(str(count)) >= 0, text)
	view.free()

func test_a_winding_up_unit_says_what_it_is_winding_up_and_how_long_is_left() -> void:
	var view = _spawn_battle_view()
	var u: CombatUnit = view.state.units[0]
	u.current_action = &"warrior_block"
	u.action_ticks_total = CG.TICKS_PER_SECOND
	u.action_ticks_left = CG.TICKS_PER_SECOND
	var text := "\n".join(UnitCard.lines(view.state, u))
	assert_true(text.find("Directional Block") >= 0, text)
	assert_true(text.find("1.0s") >= 0, text)
	view.free()

func test_a_stunned_unit_says_it_cannot_act_rather_than_looking_idle() -> void:
	var view = _spawn_battle_view()
	var u: CombatUnit = view.state.units[0]
	u.statuses[CG.Status.STUN] = view.state.tick + 30
	var text := "\n".join(UnitCard.lines(view.state, u))
	assert_true(text.findn("cannot act") >= 0, text)
	view.free()

## ---------------------------------------------------------------------------
## The route in, and what it does to the fight

func test_clicking_a_unit_opens_the_card_on_that_unit() -> void:
	var view = _spawn_battle_view()
	var u: CombatUnit = view.state.units[0]
	view.select_unit_at(u.position)
	assert_true(view._unit_card.visible)
	assert_eq(view._unit_card.unit_id, u.id)
	view.free()

func test_clicking_a_unit_holds_the_fight() -> void:
	var view = _spawn_battle_view()
	assert_false(view.paused)
	view.select_unit_at(view.state.units[0].position)
	assert_true(view.paused, "a click on a unit pauses, so there is time to read it")
	view.free()

func test_closing_the_card_resumes_a_fight_the_card_itself_held() -> void:
	var view = _spawn_battle_view()
	view.select_unit_at(view.state.units[0].position)
	view._unit_card.close()
	assert_false(view.paused)
	assert_false(view._unit_card.visible)
	view.free()

## The one case auto-resume must not fire in: the player paused first, on
## purpose, and the card is not what took the fight away from them.
func test_closing_the_card_leaves_a_deliberate_pause_alone() -> void:
	var view = _spawn_battle_view()
	view.set_paused(true)
	view.select_unit_at(view.state.units[0].position)
	view._unit_card.close()
	assert_true(view.paused)
	view.free()

func test_clicking_empty_space_closes_the_card() -> void:
	var view = _spawn_battle_view()
	view.select_unit_at(view.state.units[0].position)
	view.select_unit_at(Vector2(0.0, -400.0))
	assert_false(view._unit_card.visible)
	view.free()

func test_the_card_starts_hidden() -> void:
	var view = _spawn_battle_view()
	assert_false(view._unit_card.visible)
	view.free()

## A card left open on a unit that has died stops answering for it: the fight
## moves on and a frozen card is the stale-comment failure in a panel.
func test_the_card_closes_when_the_unit_it_describes_dies() -> void:
	var view = _spawn_battle_view()
	var u: CombatUnit = view.state.units[0]
	view.select_unit_at(u.position)
	u.hp = 0
	u.alive = false
	view._unit_card.refresh(view.state)
	assert_false(view._unit_card.visible)
	view.free()

## The card is a route into the panel the same playtester called "genuinely
## good", so a player pawn offers it and an enemy -- which has no PawnData and
## no plans -- must not.
func test_only_a_player_pawn_offers_a_way_through_to_its_plans() -> void:
	var view = _spawn_battle_view()
	for u in view.state.units:
		view.select_unit_at(u.position)
		assert_eq(view._unit_card._plans_button.visible, u.pawn != null,
			"%s: plans button visible must match having plans" % u.display_name)
	view.free()

func test_the_card_does_not_cover_the_whole_screen() -> void:
	var view = _spawn_battle_view()
	view.select_unit_at(view.state.units[0].position)
	assert_true(view._unit_card.get_combined_minimum_size().x <= UnitCard.MAX_WIDTH + 1.0,
		"the screen is already crowded; the card is a panel, not a takeover")
	view.free()

## The defect the click probe found in the first version: a card placed beside
## the unit covered the field and ate the next click, so eight of eleven
## sprites still reported "nothing happened".
func test_the_card_is_docked_rather_than_placed_over_the_field() -> void:
	var view = _spawn_battle_view()
	var first: CombatUnit = view.state.units[0]
	view.select_unit_at(first.position)
	var where: Vector2 = view._unit_card.position
	view.select_unit_at(view.state.units[-1].position)
	assert_eq(view._unit_card.position, where,
		"the card must not move to whichever unit was clicked")
	assert_almost_eq(view._unit_card.anchor_top, 1.0, 0.0001, "docked to the bottom edge")
	assert_almost_eq(view._unit_card.anchor_left, 0.0, 0.0001, "docked to the left edge")
	view.free()

## ---------------------------------------------------------------------------
## Issue 397: the Plans button, the leaving-the-arena close, and the hint

## Two pawns, so "opened the wrong one" is a thing the assertion can see. The
## one-pawn fixture above cannot fail this test at all.
func _make_pair() -> Array[PawnData]:
	var out: Array[PawnData] = []
	for id in [&"first_pawn", &"second_pawn"]:
		var cls := ClassDef.new()
		cls.id = id
		cls.display_name = String(id).capitalize()
		var pawn := PawnData.new()
		pawn.id = id
		pawn.display_name = String(id).capitalize()
		pawn.pawn_class = cls
		out.append(pawn)
	return out

func _spawn_battle_view_with_pair():
	var view = BattleScene.instantiate()
	view._ready()
	var config := RunConfig.new()
	config.seed = 1
	config.party = _make_pair()
	var e := _make_encounter()
	e.party_spawns = [Vector2(-300.0, 0.0), Vector2(-300.0, 120.0)]
	view.config = config
	view.begin_with_encounter(config, e)
	return view

## The playtester clicked Plans on the Warrior's card and got the Geysermancer.
func test_the_plans_button_opens_the_pawn_whose_card_it_is() -> void:
	var view = _spawn_battle_view_with_pair()
	for u in view.state.units:
		if u.pawn == null:
			continue
		view.select_unit_at(u.position)
		view._on_card_plans_requested()
		assert_eq(view.config.party[view._inspect_panel._selected_index].id, u.pawn.id,
			"%s's card must open %s's plans" % [u.display_name, u.display_name])
		view._inspect_panel.close()
	view.free()

## Docked bottom-left, which is where the plans screen puts its pawn selector.
func test_opening_the_plans_screen_puts_the_card_away() -> void:
	var view = _spawn_battle_view_with_pair()
	view.select_unit_at(view.state.units[0].position)
	assert_true(view._unit_card.visible)
	view._on_card_plans_requested()
	assert_false(view._unit_card.visible,
		"a card left open covers the selector you need to correct it")
	view.free()

func test_the_toolbar_plans_button_also_puts_the_card_away() -> void:
	var view = _spawn_battle_view_with_pair()
	view.select_unit_at(view.state.units[0].position)
	view._on_inspect_pressed()
	assert_false(view._unit_card.visible)
	view.free()

## Dismissing rather than closing: the pause the card took has to survive the
## trip through the plans screen, or the fight runs on behind the overlay.
func test_the_fight_stays_held_while_the_plans_screen_is_up_and_resumes_after() -> void:
	var view = _spawn_battle_view_with_pair()
	view.select_unit_at(view.state.units[0].position)
	view._on_card_plans_requested()
	assert_true(view.paused, "the plans screen is not a reason to let the fight run")
	view._inspect_panel.close()
	assert_false(view.paused)
	view.free()

## focus_id pointing at self is legitimate -- PlanInterpreter.action_target_id
## aims a targets_self action at the caster -- so the card must not report it
## as "Aiming at <its own name>".
func test_a_self_targeted_unit_does_not_read_as_aiming_at_itself() -> void:
	var view = _spawn_battle_view()
	var u: CombatUnit = view.state.units[0]
	u.focus_id = u.id
	var text := "\n".join(UnitCard.lines(view.state, u))
	assert_true(text.find("Aiming at %s" % u.display_name) < 0,
		"self-focus must not read as aiming at itself: %s" % text)
	assert_true(text.findn("itself") >= 0, text)
	view.free()

func test_the_hint_says_units_are_clickable_until_one_has_been_clicked() -> void:
	BattleView.card_discovered = false
	var view = _spawn_battle_view()
	assert_true(view._click_hint.visible, "three of four fights were played without finding the card")
	assert_true(view._click_hint.text.findn("click") >= 0, view._click_hint.text)
	view.select_unit_at(view.state.units[0].position)
	assert_false(view._click_hint.visible, "the hint costs no space once it has been read")
	view.free()

func test_the_hint_does_not_come_back_for_a_player_who_has_used_the_card() -> void:
	BattleView.card_discovered = true
	var view = _spawn_battle_view()
	assert_false(view._click_hint.visible)
	BattleView.card_discovered = false
	view.free()

## The log owns the right column in landscape and the bottom band in portrait,
## and the hint is the size of a line of text in the other place.
func test_the_hint_keeps_clear_of_the_combat_log_in_both_orientations() -> void:
	var view = _spawn_battle_view()
	view._place_click_hint(true)
	assert_true(view._click_hint.offset_right <= -CombatLogView.LOG_WIDTH,
		"landscape: the log is the right-hand column")
	view._place_click_hint(false)
	assert_true(view._click_hint.offset_bottom <= CombatLogView.LOG_MARGIN - CombatLogView.LOG_HEIGHT,
		"portrait: the log is the bottom band")
	view.free()

## ---------------------------------------------------------------------------
## Issue 396: the card cut `Shielding (5.0s left): Stops an` at its bottom edge

## The cut has to land between lines, not through one.
func test_the_body_is_a_whole_number_of_lines() -> void:
	assert_eq(UnitCard.body_height(1000.0, 380.0, 24.0), 360.0,
		"380 over a 24px line is 15.8 lines, and the 0.8 is the clipped sentence")
	assert_eq(UnitCard.body_height(48.0, 380.0, 24.0), 48.0,
		"a card shorter than the ceiling stays its own height")
	assert_eq(UnitCard.body_height(1000.0, 10.0, 24.0), 24.0,
		"a ceiling under one line still shows one whole line")

## A flat 380 is exactly right at 720 and wrong at every other height.
func test_the_body_ceiling_follows_the_window() -> void:
	assert_true(BattleView.card_body_ceiling(900.0) > BattleView.card_body_ceiling(720.0),
		"180 more pixels of window must reach the card")
	assert_true(BattleView.card_body_ceiling(400.0) >= UnitCard.MIN_BODY_HEIGHT,
		"a short window still shows a few lines rather than none")
	assert_true(BattleView.card_body_ceiling(720.0) <= 720.0)

func test_the_card_takes_the_ceiling_the_view_gives_it() -> void:
	var view = _spawn_battle_view()
	view.select_unit_at(view.state.units[0].position)
	assert_true(view._unit_card.body_ceiling > 0.0,
		"the card was never told how much screen it has")
	view.free()
