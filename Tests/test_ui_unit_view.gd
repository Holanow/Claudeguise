extends "res://Tests/TestCase.gd"

const PawnDataScript := preload("res://Scripts/Core/PawnData.gd")
const BattleViewScript := preload("res://Scripts/UI/BattleView.gd")
const BattleScene := preload("res://Scenes/Battle.tscn")

## UnitView reads CombatUnit directly for position and bars (the issue allows
## this; only "things that happened" must come from events). These tests check
## it tracks position and alive/dead visibility without needing to render.

func _make_unit(id: int, pos: Vector2, alive: bool = true) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.position = pos
	u.hp = 5
	u.hp_max = 10
	u.alive = alive
	u.display_name = "Test"
	return u

func test_bind_places_the_view_at_the_unit_position() -> void:
	var state := CombatState.new(0)
	state.units.append(_make_unit(0, Vector2(100.0, -50.0)))
	var view := UnitView.new()
	view.bind(state, 0)
	assert_eq(view.position, Vector2(100.0, -50.0))
	view.free()

func test_sync_follows_a_moving_unit() -> void:
	var state := CombatState.new(0)
	state.units.append(_make_unit(0, Vector2.ZERO))
	var view := UnitView.new()
	view.bind(state, 0)
	state.units[0].position = Vector2(10.0, 20.0)
	view.sync(state)
	assert_eq(view.position, Vector2(10.0, 20.0))
	view.free()

func test_dead_unit_is_not_visible() -> void:
	var state := CombatState.new(0)
	state.units.append(_make_unit(0, Vector2.ZERO, true))
	var view := UnitView.new()
	view.bind(state, 0)
	assert_true(view.visible)

	state.units[0].alive = false
	view.sync(state)
	assert_false(view.visible, "a dead unit's view must not stay visible")
	view.free()

# ---------------------------------------------------------------------------
# display_radius (issue 642: one body size, and this is it)
# ---------------------------------------------------------------------------

func test_display_radius_is_the_units_own_radius() -> void:
	var u := _make_unit(0, Vector2.ZERO)
	u.radius = 22.0
	assert_almost_eq(UnitView.display_radius(u), u.radius, 0.001)

## The one regression that would matter most here: CombatSim reads
## unit.radius for real movement collision (TerrainGrid.move_blocked), so a
## rendering fix that mutated it would be a balance change wearing a UI
## issue's clothes. display_radius must only ever read it.
func test_display_radius_does_not_mutate_the_units_own_radius() -> void:
	var u := _make_unit(0, Vector2.ZERO)
	u.radius = 22.0
	UnitView.display_radius(u)
	assert_eq(u.radius, 22.0, "display scaling must never touch the simulation's own radius")


## STUN is a CG.Status and draws as a badge.
func test_a_stun_shows_as_a_badge_and_not_as_text_as_well() -> void:
	var u := _make_unit(0, Vector2.ZERO)
	u.statuses[CG.Status.STUN] = 100
	assert_eq(UnitView.status_badges(u), [CG.Status.STUN])




# ---------------------------------------------------------------------------
# Status badges (PLAYTEST-NOTES-2 item 2, drawn with sable's StatusIcons)
# ---------------------------------------------------------------------------

func test_an_unaffected_unit_gets_no_badges() -> void:
	var u := _make_unit(0, Vector2.ZERO)
	assert_true(UnitView.status_badges(u).is_empty())

## The negative half: a unit with a resource problem but no status must not
## grow a badge row. A badge that appears when nothing is wrong teaches a
## player to stop looking at badges.
func test_being_out_of_resource_is_not_a_badge() -> void:
	var u := _make_unit(0, Vector2.ZERO)
	u.resource_max = 10
	u.resource = 0
	assert_true(UnitView.status_badges(u).is_empty())

## Harmful first, and each group in CG.Status declaration order -- never the
## Dictionary's own insertion order, which is the order they happened to land
## during a fight. Applied here by giving a unit a beneficial status *first*:
func test_harmful_badges_come_before_beneficial_ones_whatever_order_they_landed() -> void:
	var u := _make_unit(0, Vector2.ZERO)
	u.statuses[CG.Status.SHIELD] = 100
	u.statuses[CG.Status.POISON] = 100
	assert_eq(UnitView.status_badges(u), [CG.Status.POISON, CG.Status.SHIELD])

func test_badge_order_does_not_depend_on_which_status_landed_first() -> void:
	var a := _make_unit(0, Vector2.ZERO)
	a.statuses[CG.Status.BURN] = 100
	a.statuses[CG.Status.BLEED] = 100
	var b := _make_unit(1, Vector2.ZERO)
	b.statuses[CG.Status.BLEED] = 100
	b.statuses[CG.Status.BURN] = 100
	assert_eq(UnitView.status_badges(a), UnitView.status_badges(b))

## Issue 161: the cap is unchanged as a ROW WIDTH rule -- the row still occupies
## at most `MAX_STATUS_BADGES` slots -- but the last slot is now a "+N" chip
## rather than a fourth badge whenever something would otherwise be dropped.
func test_a_badge_row_is_capped_so_it_never_grows_wider_than_the_unit() -> void:
	var u := _make_unit(0, Vector2.ZERO)
	for s in CG.Status.values():
		u.statuses[s] = 100
	var badges := UnitView.status_badges(u)
	var slots: int = badges.size() + (1 if UnitView.hidden_status_count(u) > 0 else 0)
	assert_eq(slots, UnitView.MAX_STATUS_BADGES, "the row must still be exactly the capped width")
	for s in badges:
		assert_true(CG.is_harmful(s), "the capped row must keep what is being done to the unit")

## **The defect sable measured: a fifth status was dropped with nothing saying
## so.** Four badges read as "this unit has four statuses", which is a statement
## the game makes and it was false.
func test_a_fifth_status_is_counted_rather_than_silently_dropped() -> void:
	var u := _make_unit(0, Vector2.ZERO)
	var applied: Array = []
	for s in CG.Status.values():
		if applied.size() >= UnitView.MAX_STATUS_BADGES + 1:
			break
		u.statuses[s] = 100
		applied.append(s)
	assert_eq(applied.size(), UnitView.MAX_STATUS_BADGES + 1, "the fixture must actually overflow")
	var shown := UnitView.status_badges(u).size()
	var hidden := UnitView.hidden_status_count(u)
	assert_true(hidden > 0, "with %d statuses on the unit nothing reports the overflow" % applied.size())
	assert_eq(shown + hidden, applied.size(),
		"every status must be either drawn or counted -- %d drawn + %d counted != %d on the unit" % [shown, hidden, applied.size()])

## The negative half, and the one that stops the chip becoming furniture: at or
## under the cap nothing is hidden and no "+0" may appear. A detector that
## always fires is one a player learns to ignore in minutes.
func test_nothing_is_reported_hidden_while_everything_fits() -> void:
	var u := _make_unit(0, Vector2.ZERO)
	var count := 0
	for s in CG.Status.values():
		if count >= UnitView.MAX_STATUS_BADGES:
			break
		u.statuses[s] = 100
		count += 1
	assert_eq(UnitView.hidden_status_count(u), 0, "a full-but-fitting row hides nothing")
	assert_eq(UnitView.status_badges(u).size(), UnitView.MAX_STATUS_BADGES,
		"and the whole cap is drawn, with no slot given up to a chip")

	# And the empty case, since `hidden_status_count` is consulted before the
	# early return in the drawing.
	var bare := _make_unit(1, Vector2.ZERO)
	assert_eq(UnitView.hidden_status_count(bare), 0)
	assert_true(UnitView.status_badges(bare).is_empty())

## The count must be derived from the same ordering the badges are, or the chip
## can disagree with the row it sits in.
func test_the_hidden_count_agrees_with_what_is_drawn() -> void:
	var u := _make_unit(0, Vector2.ZERO)
	for s in CG.Status.values():
		u.statuses[s] = 100
	var ordered := UnitView.ordered_statuses(u)
	var badges := UnitView.status_badges(u)
	assert_eq(badges.size() + UnitView.hidden_status_count(u), ordered.size())
	for i in badges.size():
		assert_eq(badges[i], ordered[i], "the drawn badges must be the first of the same ordering")

## Every badge this view can ask for has to have a glyph on the other side of
## the boundary. A status added to CG.Status with no entry in StatusIcons
## would otherwise crash at the exact moment it first lands in a fight, which
## is the least reproducible place for it to fail.
func test_every_status_this_view_can_draw_has_a_glyph() -> void:
	for s in CG.Status.values():
		assert_true(StatusIcons.has_glyph(s), "no glyph for %s" % CG.Status.keys()[s])

## The badge row is drawn below the body. Above is where the resource bar, hp
## bar, name label and crowding stagger all live, and issue #82 is about that
## band already being over-full.
func test_the_badge_row_sits_below_the_body() -> void:
	var u := _make_unit(0, Vector2.ZERO)
	u.radius = 22.0
	var radius := UnitView.display_radius(u)
	var rects := StatusIcons.layout_row(
		Vector2(0.0, radius + UnitView.STATUS_BADGE_TOP_GAP), 1, UnitView.STATUS_BADGE_SIZE)
	assert_true(rects[0].position.y > radius, "badges must clear the body downward")

## The badge row's own clearance has to be bigger than the gap between two
## badges, or a unit's row stops reading as one row belonging to that unit.
func test_the_badge_row_is_held_off_whatever_is_above_it() -> void:
	assert_true(UnitView.STATUS_BADGE_TOP_GAP > UnitView.STATUS_BADGE_GAP,
		"the row must separate from the thing above it more than its badges separate from each other")

# ---------------------------------------------------------------------------
# The wind-up progress bar and its ability icon (PLAYTEST-NOTES-2 item 3)
# ---------------------------------------------------------------------------

func _winding_up(elapsed: int, total: int) -> CombatUnit:
	var u := _make_unit(0, Vector2.ZERO)
	u.current_action = &"warrior_strike"
	u.action_ticks_total = total
	u.action_ticks_left = total - elapsed
	return u

func test_a_wind_up_bar_is_empty_at_the_start_and_full_at_the_end() -> void:
	assert_almost_eq(UnitView.wind_up_fraction(_winding_up(0, 30)), 0.0, 0.001)
	assert_almost_eq(UnitView.wind_up_fraction(_winding_up(15, 30)), 0.5, 0.001)
	assert_almost_eq(UnitView.wind_up_fraction(_winding_up(30, 30)), 1.0, 0.001)

## The reason the half-speed change (CG.TICKS_PER_SECOND 30 -> 15) moved
## nothing here: the bar is a ratio of elapsed to this action's own total, not
## a count of ticks against any constant. A wind-up half as long in ticks
## reads identically at the same point through itself.
func test_a_wind_up_bar_is_a_ratio_not_a_tick_count() -> void:
	assert_almost_eq(UnitView.wind_up_fraction(_winding_up(45, 90)),
		UnitView.wind_up_fraction(_winding_up(22, 44)), 0.02,
		"the same fraction through two differently-scaled wind-ups must read the same")

## The case the ring was built for and the one a derivation from the action's
## own base wind_up_ticks would have got wrong: HASTE shortens the wind-up, and
## action_ticks_total captures the post-haste length.
func test_a_hasted_wind_up_still_reads_zero_to_full_across_its_own_length() -> void:
	var hasted := _winding_up(0, 20)
	assert_almost_eq(UnitView.wind_up_fraction(hasted), 0.0, 0.001)
	hasted.action_ticks_left = 0
	assert_almost_eq(UnitView.wind_up_fraction(hasted), 1.0, 0.001)

## An instant action has nothing to wait for, so the bar is full rather than
## dividing by zero or reading as a countdown that never moves.
func test_an_action_with_no_wind_up_reads_as_full() -> void:
	var u := _winding_up(0, 0)
	u.action_ticks_left = 1
	assert_almost_eq(UnitView.wind_up_fraction(u), 1.0, 0.001)

## Bar plus icon plus their gap is exactly the hp bar's width. A unit's chrome
## must not get wider at the moment the arena is most crowded -- that is issue
## #82's own failure mode.
func test_the_wind_up_block_is_no_wider_than_the_hp_bar() -> void:
	for radius in [4.0, 11.0, 16.5, 22.0, 33.0, 200.0]:
		var display_radius: float = radius * UnitView.DISPLAY_SCALE
		# Issue 190: the icon scales with the block now, so the invariant sums the
		# real icon size rather than the constant. The property is unchanged --
		# bar + gap + icon is exactly the hp bar's width -- and it now has to
		# hold for a goblin-sized body too, which is where it used to be
		# impossible: a fixed 24px icon does not fit inside a 20px block.
		assert_almost_eq(
			UnitView.wind_up_bar_width(display_radius) + UnitView.WIND_UP_ICON_GAP
				+ UnitView.wind_up_icon_size(display_radius),
			UnitView.bar_width(display_radius), 0.001,
			"the block must match the hp bar at radius %.1f" % radius)
		assert_true(UnitView.wind_up_bar_width(display_radius) > 0.0,
			"the bar must survive the icon taking its share at radius %.1f" % radius)

## The point of issue 82's change: a bar belongs to a body. A goblin's bar must
## be narrower than a party pawn's, and neither may exceed the old fixed width.
func test_a_smaller_unit_gets_a_narrower_bar() -> void:
	var goblin := UnitView.bar_width(11.0 * UnitView.DISPLAY_SCALE)
	var pawn := UnitView.bar_width(22.0 * UnitView.DISPLAY_SCALE)
	assert_true(goblin < pawn, "a goblin's bar must be narrower than a pawn's (%.1f vs %.1f)" % [goblin, pawn])
	assert_true(pawn <= UnitView.BAR_WIDTH * UnitView.DISPLAY_SCALE,
		"no bar may be wider than the old fixed one")
	assert_true(goblin >= UnitView.MIN_BAR_WIDTH, "and none may collapse below the floor")

## Issue 190: the point of the whole change. A goblin's bar must be close to the
## goblin, not to the space the simulation reserves for it. Measured against the
## drawn silhouette, which is the thing a player compares the bar against.
func test_a_bar_is_sized_to_the_drawn_body_not_the_collision_footprint() -> void:
	var radius := 11.0 * UnitView.DISPLAY_SCALE
	var drawn := UnitView.drawn_half_width(&"goblin", CG.Team.ENEMY, radius) * 2.0
	var bar := UnitView.bar_width(radius, &"goblin", CG.Team.ENEMY)
	assert_true(drawn < radius * 2.0, "fixture check: the goblin must under-fill its footprint")
	assert_true(bar <= drawn * 1.4,
		"a goblin's bar is %.1f against a %.1f body -- the decoration outweighs the unit" % [bar, drawn])
	# And the wind-up block still fits inside that smaller bar.
	assert_true(UnitView.wind_up_bar_width(radius, &"goblin", CG.Team.ENEMY) > 0.0,
		"the wind-up bar vanished once the hp bar shrank")

## The invariant, not a shape. **My first version asserted the abomination keeps
## a full-width bar "because it fills its footprint" -- it does not, it is 0.79,
## and I had taken that from the same polygon-only measurement that also called
## the goblin the worst shape in the game.** A test whose premise comes from the
## bad data cannot catch the bad data.
func test_every_bar_tracks_its_shapes_measured_fill() -> void:
	var checked := 0
	for row in [[&"goblin", 11.0, CG.Team.ENEMY], [&"ghoul", 11.0, CG.Team.ENEMY],
			[&"rat", 9.0, CG.Team.ENEMY], [&"warrior", 22.0, CG.Team.PLAYER],
			[&"priest", 22.0, CG.Team.PLAYER], [&"siege_master", 22.0, CG.Team.PLAYER],
			[&"abomination", 22.0, CG.Team.PLAYER]]:
		var id: StringName = row[0]
		var radius: float = row[1] * UnitView.DISPLAY_SCALE
		var team: CG.Team = row[2]
		var fill: Vector2 = Silhouettes.fill_ratio(id, team)
		assert_true(fill.x > 0.0, "%s measured as no width at all" % id)
		var expected: float = clampf(fill.x * radius * 2.0, UnitView.MIN_BAR_WIDTH,
			UnitView.BAR_WIDTH * UnitView.DISPLAY_SCALE)
		assert_almost_eq(UnitView.bar_width(radius, id, team), expected, 0.5,
			"%s: bar must follow its measured fill of %.2f" % [id, fill.x])
		checked += 1
	assert_true(checked >= 7, "only checked %d shapes" % checked)

## The vertical axis, which was never measured before #200 and is worse than the
## horizontal. `siege_master` fills 0.33 of its box vertically, so anchoring the
## bar stack to `radius` put it two thirds of a body above the art.
func test_the_bar_anchor_follows_art_that_sits_low_in_its_canvas() -> void:
	var radius := 22.0 * UnitView.DISPLAY_SCALE
	var fill: Vector2 = Silhouettes.fill_ratio(&"rat", CG.Team.ENEMY)
	assert_true(fill.y < 0.75, "fixture check: rat must under-fill vertically, got %.2f" % fill.y)
	var top := UnitView.drawn_top(&"rat", CG.Team.ENEMY, radius)
	assert_true(top < radius * 0.75,
		"the stack still anchors to the footprint at %.1f of %.1f" % [top, radius])

## The telegraph is coloured by the ACTION's damage type, not by the class
## accent. A Priest's class accent is Divine and priest_bolt is not, so a
## telegraph keyed on the accent would disagree with the projectile and the
## floating number that follow it -- which is the one thing the icon exists to
## make agree. Tests/test_art.gd already asserts ActionIcons covers the
## registry; this asserts this view asks for it by the id a unit actually
## carries in current_action.
func test_the_telegraph_is_coloured_by_the_action_not_the_class_accent() -> void:
	var u := _make_unit(0, Vector2.ZERO)
	u.current_action = &"priest_smite"
	var view := UnitView.new()
	var smite := ActionLibrary.get_action(&"priest_smite")
	assert_not_null(smite, "sanity: the registry defines the action this test names")
	assert_eq(view._wind_up_damage_type(u), smite.damage_type)
	assert_true(ActionIcons.has_glyph(u.current_action), "no ability icon for %s" % u.current_action)
	view.free()

## The negative half: an action the registry does not know still draws
## something rather than crashing mid-fight. ActionIcons has its own unknown
## placeholder; this is the colour half of the same fallback.
func test_an_unknown_action_falls_back_to_the_class_accent() -> void:
	var u := _make_unit(0, Vector2.ZERO)
	u.current_action = &"no_such_action"
	var view := UnitView.new()
	assert_eq(view._wind_up_damage_type(u), CG.DamageType.PHYSICAL)
	view.free()


## Issue 378. `crowd_rank` used to count neighbours inside CROWD_RADIUS, a
## radius around a POINT, and what collides is a chip as wide as the name. It
## also measured the SIMULATED position while the plate hangs over the DRAWN
## one, which the scrum nudge moves by up to 1.5 radii. Rows are now taken by
## rectangle overlap of the real chips.

## Small bodies, so separation does not push them apart before their
## plates can collide. A goblin is radius 12; the default here is 22.
func _make_small(id: int, pos: Vector2, alive: bool = true) -> CombatUnit:
	var u := _make_unit(id, pos, alive)
	u.radius = 6.0
	u.display_name = "Goblin Archer"
	return u

func test_crowd_rank_is_zero_when_plates_do_not_overlap() -> void:
	var a := _make_small(0, Vector2.ZERO)
	var b := _make_small(1, Vector2(400.0, 0.0))
	assert_eq(UnitView.crowd_rank(a, [a, b]), 0)
	assert_eq(UnitView.crowd_rank(b, [a, b]), 0)

func test_crowd_rank_only_moves_the_higher_id() -> void:
	# Deterministic by id: two views of the same fight must agree on which
	# of two overlapping units' labels moves, not on whichever happened to
	# be iterated or drawn first.
	var a := _make_small(0, Vector2.ZERO)
	var b := _make_small(1, Vector2(20.0, 0.0))
	assert_eq(UnitView.crowd_rank(a, [a, b]), 0, "the lower id must not move")
	assert_eq(UnitView.crowd_rank(b, [a, b]), 1, "the higher id steps up once")

func test_crowd_rank_stacks_with_each_additional_overlapping_plate() -> void:
	var a := _make_small(0, Vector2.ZERO)
	var b := _make_small(1, Vector2(20.0, 0.0))
	var c := _make_small(2, Vector2(-20.0, 0.0))
	assert_eq(UnitView.crowd_rank(c, [a, b, c]), 2)

func test_crowd_rank_ignores_dead_units() -> void:
	var a := _make_small(0, Vector2.ZERO, false)
	var b := _make_small(1, Vector2(20.0, 0.0))
	assert_eq(UnitView.crowd_rank(b, [a, b]), 0, "a dead unit's old label is gone too, nothing to avoid")

## The defect in the playtester's own words: two Goblins whose CENTRES are 120
## apart -- outside the old 105-unit radius -- whose plates overlap by most of
## their width. The old rule scored both at row 0 and printed one through the
## other.
func test_two_plates_wider_than_the_old_radius_no_longer_share_a_row() -> void:
	var a := _make_small(0, Vector2.ZERO)
	var b := _make_small(1, Vector2(120.0, 0.0))
	assert_true(UnitView.plate_rect(a, [a, b], 0).intersects(UnitView.plate_rect(b, [a, b], 0)),
		"sanity: at row 0 these two chips do overlap, which a 105-unit radius could not see")
	assert_eq(UnitView.crowd_rank(b, [a, b]), 1)
	assert_false(UnitView.plate_rect(a, [a, b]).intersects(UnitView.plate_rect(b, [a, b])),
		"and once ranked they must not overlap at all")

# ---------------------------------------------------------------------------
# concentration_count (issue 15)
# ---------------------------------------------------------------------------

func test_concentration_count_is_zero_with_no_attackers() -> void:
	var target := _make_unit(0, Vector2.ZERO)
	var bystander := _make_unit(1, Vector2(50.0, 0.0))
	assert_eq(UnitView.concentration_count(target, [target, bystander]), 0)

func test_concentration_count_counts_focused_attackers_only() -> void:
	var target := _make_unit(0, Vector2.ZERO)
	var attacker_a := _make_unit(1, Vector2(50.0, 0.0))
	attacker_a.focus_id = 0
	var attacker_b := _make_unit(2, Vector2(-50.0, 0.0))
	attacker_b.focus_id = 0
	var elsewhere := _make_unit(3, Vector2(0.0, 50.0))
	elsewhere.focus_id = 3
	var units := [target, attacker_a, attacker_b, elsewhere]
	assert_eq(UnitView.concentration_count(target, units), 2)

func test_concentration_count_ignores_dead_attackers() -> void:
	var target := _make_unit(0, Vector2.ZERO)
	var dead_attacker := _make_unit(1, Vector2(50.0, 0.0), false)
	dead_attacker.focus_id = 0
	assert_eq(UnitView.concentration_count(target, [target, dead_attacker]), 0)

# ---------------------------------------------------------------------------
# should_show_label (issue 41: dense rooms piled enemy names on top of each other)
# ---------------------------------------------------------------------------

func test_should_show_label_is_always_true_for_the_party() -> void:
	var pawn := _make_unit(0, Vector2.ZERO)
	pawn.team = CG.Team.PLAYER
	assert_true(UnitView.should_show_label(pawn, [pawn]))

func test_should_show_label_is_false_for_an_untargeted_idle_enemy() -> void:
	var enemy := _make_unit(0, Vector2.ZERO)
	enemy.team = CG.Team.ENEMY
	assert_false(UnitView.should_show_label(enemy, [enemy]), "a standing, unengaged enemy doesn't need its name up permanently")

func test_should_show_label_is_true_for_an_enemy_under_focus() -> void:
	var enemy := _make_unit(0, Vector2.ZERO)
	enemy.team = CG.Team.ENEMY
	var attacker := _make_unit(1, Vector2(50.0, 0.0))
	attacker.focus_id = 0
	assert_true(UnitView.should_show_label(enemy, [enemy, attacker]))

func test_should_show_label_is_true_for_an_enemy_mid_wind_up() -> void:
	var enemy := _make_unit(0, Vector2.ZERO)
	enemy.team = CG.Team.ENEMY
	enemy.current_action = &"goblin_swing"
	enemy.action_ticks_left = 5
	assert_true(UnitView.should_show_label(enemy, [enemy]))

# ---------------------------------------------------------------------------
# wind_up_elapsed_ticks (PR #69/#71/#72: the wind-up ring becomes a real
# countdown, coloured by damage type, correct even under HASTE)
# ---------------------------------------------------------------------------

func test_wind_up_elapsed_ticks_is_total_minus_left() -> void:
	var u := _make_unit(0, Vector2.ZERO)
	u.action_ticks_total = 10
	u.action_ticks_left = 4
	assert_eq(UnitView.wind_up_elapsed_ticks(u), 6)

func test_wind_up_elapsed_ticks_is_zero_at_the_very_start() -> void:
	var u := _make_unit(0, Vector2.ZERO)
	u.action_ticks_total = 10
	u.action_ticks_left = 10
	assert_eq(UnitView.wind_up_elapsed_ticks(u), 0)

## The actual reason action_ticks_total exists rather than reading the
## action's own base wind_up_ticks: it is captured post-haste, so a hasted
## unit's shorter wind-up still reports 0 elapsed at its own start and full
## elapsed at its own end, not against the un-hasted length.
func test_wind_up_elapsed_ticks_is_correct_for_a_hasted_shorter_wind_up() -> void:
	var u := _make_unit(0, Vector2.ZERO)
	u.action_ticks_total = 7  # e.g. a base 10-tick wind-up scaled by HASTE
	u.action_ticks_left = 7
	assert_eq(UnitView.wind_up_elapsed_ticks(u), 0, "must read 0 elapsed at the start of the hasted wind-up, not against the un-hasted total")
	u.action_ticks_left = 0
	assert_eq(UnitView.wind_up_elapsed_ticks(u), 7, "must read fully elapsed at the hasted wind-up's own end")

func test_should_show_label_is_false_for_an_enemy_with_stale_action_but_no_ticks_left() -> void:
	var enemy := _make_unit(0, Vector2.ZERO)
	enemy.team = CG.Team.ENEMY
	enemy.current_action = &"goblin_swing"
	enemy.action_ticks_left = 0
	assert_false(UnitView.should_show_label(enemy, [enemy]))

# ---------------------------------------------------------------------------
# label hold (PLAYTEST-NOTES 20: the Goblin Archer's name flickered)
# ---------------------------------------------------------------------------

## should_show_label's own trigger is a per-tick on/off condition (focused,
## or mid wind-up); label_visible is the rendering decision layered on top
## that keeps a name up for a while after the trigger clears, so it does not
## blink out the instant an attacker refocuses or finishes winding up.
func test_label_stays_visible_for_a_hold_after_the_trigger_clears() -> void:
	var state := CombatState.new(0)
	var enemy := _make_unit(0, Vector2.ZERO)
	enemy.team = CG.Team.ENEMY
	enemy.current_action = &"goblin_swing"
	enemy.action_ticks_left = 5
	state.units.append(enemy)
	var view := UnitView.new()
	view.bind(state, 0)
	assert_true(UnitView.label_visible(enemy, state), "must be visible while the trigger holds")

	enemy.current_action = &""
	enemy.action_ticks_left = 0
	assert_true(UnitView.label_visible(enemy, state), "must not blink out the instant the trigger clears")
	view.free()

func test_label_hides_once_the_hold_expires() -> void:
	var state := CombatState.new(0)
	var enemy := _make_unit(0, Vector2.ZERO)
	enemy.team = CG.Team.ENEMY
	enemy.current_action = &"goblin_swing"
	enemy.action_ticks_left = 5
	state.units.append(enemy)
	var view := UnitView.new()
	view.bind(state, 0)
	UnitView.label_visible(enemy, state)

	enemy.current_action = &""
	enemy.action_ticks_left = 0
	state.tick = UnitView.LABEL_HOLD_TICKS + 1
	assert_false(UnitView.label_visible(enemy, state), "the hold must actually expire, not hold forever")
	view.free()

## PLAYTEST-NOTES 20's other half: "some enemies never get names" — a fodder
## unit standing in melee range, hit by a plan-driven pawn's default
## behaviour, is neither focusing anyone nor mid wind-up itself. Taking
## damage (or losing resource) is read off the unit's own state each sync,
## the same boundary should_show_label already respects (CombatUnit only,
## no CombatEvent).
func test_taking_damage_holds_the_label_even_with_no_other_trigger() -> void:
	var state := CombatState.new(0)
	var enemy := _make_unit(0, Vector2.ZERO)
	enemy.team = CG.Team.ENEMY
	enemy.hp = 10
	state.units.append(enemy)
	var view := UnitView.new()
	view.bind(state, 0)
	assert_false(UnitView.should_show_label(enemy, [enemy]), "sanity: this enemy has no other trigger")

	enemy.hp = 6
	view.sync(state)
	assert_true(UnitView.label_visible(enemy, state), "getting hit must surface the name even with nothing else triggering it")
	view.free()

# ---------------------------------------------------------------------------
# targeting line vs. real projectiles (PLAYTEST-NOTES 2: "still seeing beams")
# ---------------------------------------------------------------------------

func test_has_active_projectile_is_false_with_none_in_flight() -> void:
	var state := CombatState.new(0)
	var u := _make_unit(0, Vector2.ZERO)
	state.units.append(u)
	var view := UnitView.new()
	view.bind(state, 0)
	assert_false(view._has_active_projectile(u))
	view.free()

func test_has_active_projectile_is_true_for_this_units_own_unresolved_shot() -> void:
	var state := CombatState.new(0)
	var u := _make_unit(0, Vector2.ZERO)
	state.units.append(u)
	var p := Projectile.new()
	p.source_id = 0
	p.resolved = false
	state.projectiles.append(p)
	var view := UnitView.new()
	view.bind(state, 0)
	assert_true(view._has_active_projectile(u))
	view.free()

func test_has_active_projectile_ignores_a_resolved_shot() -> void:
	var state := CombatState.new(0)
	var u := _make_unit(0, Vector2.ZERO)
	state.units.append(u)
	var p := Projectile.new()
	p.source_id = 0
	p.resolved = true
	state.projectiles.append(p)
	var view := UnitView.new()
	view.bind(state, 0)
	assert_false(view._has_active_projectile(u), "a landed shot no longer represents anything in flight")
	view.free()

func test_has_active_projectile_ignores_another_units_shot() -> void:
	var state := CombatState.new(0)
	var u := _make_unit(0, Vector2.ZERO)
	var other := _make_unit(1, Vector2(50.0, 0.0))
	state.units.append(u)
	state.units.append(other)
	var p := Projectile.new()
	p.source_id = 1
	p.resolved = false
	state.projectiles.append(p)
	var view := UnitView.new()
	view.bind(state, 0)
	assert_false(view._has_active_projectile(u))
	view.free()

# ---------------------------------------------------------------------------
# Issue 82: the bars have to answer "am I ahead".

func _unit_at(team: CG.Team, fraction: float) -> CombatUnit:
	var u := CombatUnit.new()
	u.team = team
	u.hp_max = 100
	u.hp = int(round(fraction * 100.0))
	return u

static func _distance(a: Color, b: Color) -> float:
	return Vector3(a.r, a.g, a.b).distance_to(Vector3(b.r, b.g, b.b))

## At the same health, the two sides must not draw the same colour. This is the
## whole complaint, so it is asserted at several healths rather than one -- a
## ramp that happens to diverge at full and converge at 20% would pass a single
## check while failing the player exactly when the fight is decided.
func test_the_two_sides_bars_are_never_the_same_colour() -> void:
	for fraction in [1.0, 0.75, 0.5, 0.25, 0.05]:
		var mine := UnitView.hp_fill_color(_unit_at(CG.Team.PLAYER, fraction))
		var theirs := UnitView.hp_fill_color(_unit_at(CG.Team.ENEMY, fraction))
		assert_true(_distance(mine, theirs) > 0.15,
			"at %.0f%% health both sides draw nearly the same colour (%s vs %s)" % [fraction * 100.0, mine, theirs])

## `Palette.HP_LOW` and `Palette.TEAM_ENEMY` are both `e0705f` -- the same value.
func test_a_badly_hurt_party_pawn_is_not_drawn_in_the_enemys_colour() -> void:
	var hurt := UnitView.hp_fill_color(_unit_at(CG.Team.PLAYER, 0.1))
	assert_true(_distance(hurt, Palette.TEAM_PLAYER) < _distance(hurt, Palette.TEAM_ENEMY),
		"a party pawn at 10%% reads as the enemy colour (%s)" % hurt)
	var hurt_enemy := UnitView.hp_fill_color(_unit_at(CG.Team.ENEMY, 0.1))
	assert_true(_distance(hurt_enemy, Palette.TEAM_ENEMY) < _distance(hurt_enemy, Palette.TEAM_PLAYER),
		"an enemy at 10%% reads as the party colour (%s)" % hurt_enemy)

## Damage still has to be visible in the fill itself, not only in the length --
## a colour that never changes would pass both tests above while losing the
## "this one is nearly dead" read the old ramp did give.
func test_damage_still_darkens_the_fill() -> void:
	var full := UnitView.hp_fill_color(_unit_at(CG.Team.PLAYER, 1.0))
	var nearly_dead := UnitView.hp_fill_color(_unit_at(CG.Team.PLAYER, 0.05))
	assert_true(_distance(full, nearly_dead) > 0.1,
		"a full and a nearly-dead bar look the same (%s vs %s)" % [full, nearly_dead])
	assert_true(_distance(nearly_dead, Palette.HP_BACK) < _distance(full, Palette.HP_BACK),
		"damage must move the fill toward the trough, not away from it")


# ---------------------------------------------------------------------------
# Issue 208: every ordinary enemy's badge was 8.7 px, and nothing was watching.
# ---------------------------------------------------------------------------

## THE GUARD, and it is the point of #208 rather than the constant.
const _LEGIBLE_BADGE_PX := 16.0

func _every_drawable_shape() -> Array:
	var out: Array = []
	var pawn_radius: float = CombatUnit.new().radius
	for id in ClassLibrary.all_ids():
		out.append([id, pawn_radius, CG.Team.PLAYER])
	for id in EnemyLibrary.all_ids():
		var e = EnemyLibrary.get_enemy(id)
		out.append([id, e.radius if e != null else pawn_radius, CG.Team.ENEMY])
	return out

func test_no_units_status_badge_is_drawn_below_the_legible_size() -> void:
	var scale: float = BattleViewScript.compute_layout(Vector2(1280.0, 720.0))["scale"].x
	var shapes := _every_drawable_shape()
	assert_true(shapes.size() > 8, "the walk must cover the real roster, got %d" % shapes.size())
	for row in shapes:
		var radius: float = float(row[1]) * UnitView.DISPLAY_SCALE
		var px: float = UnitView.status_badge_size(row[0], row[2], radius) * scale
		assert_true(px >= _LEGIBLE_BADGE_PX - 0.2,
			"%s draws its status badges at %.1f px on a 1280x720 screen. The glyph set does not read below %.0f px (sable, Screenshots/badge_legibility.png)." % [row[0], px, _LEGIBLE_BADGE_PX])

## The negative half: prove the assertion above can fail, rather than trusting a
## green run on a walk that might be measuring nothing. The old floor is the
## known-bad input, and it must be rejected by the same arithmetic.
func test_the_old_floor_would_be_caught_by_that_guard() -> void:
	var scale: float = BattleViewScript.compute_layout(Vector2(1280.0, 720.0))["scale"].x
	var old_floor := 7.0 * UnitView.DISPLAY_SCALE
	assert_true(old_floor * scale < _LEGIBLE_BADGE_PX,
		"the floor #208 replaced measured %.1f px, and a guard that would have passed it is not a guard" % (old_floor * scale))
	assert_true(UnitView.STATUS_BADGE_MIN * scale >= _LEGIBLE_BADGE_PX - 0.2,
		"the new floor must clear the bar it was chosen for")

## The cap, with the reason attached to the number. sable measured 2,201,587
## unit-ticks: three or more statuses at once happens on 2.5% of them, and no
## enemy in the sample ever carried five. A cap of one would have hidden
## something on 8.2%, which is an overflow chip a player learns to distrust.
func test_the_badge_cap_is_two_and_a_third_status_is_counted_not_dropped() -> void:
	assert_eq(UnitView.MAX_STATUS_BADGES, 2)
	var u := _make_unit(0, Vector2.ZERO)
	u.statuses[CG.Status.BURN] = 100
	u.statuses[CG.Status.BLEED] = 100
	assert_eq(UnitView.status_badges(u).size(), 2, "two fit, so two are drawn and no chip appears")
	assert_eq(UnitView.hidden_status_count(u), 0)

	u.statuses[CG.Status.POISON] = 100
	assert_eq(UnitView.status_badges(u).size(), 1, "a third status gives its slot up to the chip")
	assert_eq(UnitView.hidden_status_count(u), 2, "and the chip must count both, not just the third")

# ---------------------------------------------------------------------------
# Issue 256: the body is drawn facing where the unit is looking
# ---------------------------------------------------------------------------

## `UnitView` drew `facing_left = (team == ENEMY)`, so every enemy was
## permanently mirrored and no unit was ever drawn facing where it was looking.
func test_the_body_is_drawn_from_the_facing_the_simulation_uses() -> void:
	var enemy := CombatUnit.new()
	enemy.team = CG.Team.ENEMY
	enemy.facing = Vector2(1.0, 0.0)
	assert_false(UnitView.facing_left(enemy),
		"an enemy that turned to look right is still drawn mirrored")

	var pawn := CombatUnit.new()
	pawn.team = CG.Team.PLAYER
	pawn.facing = Vector2(-1.0, 0.0)
	assert_true(UnitView.facing_left(pawn),
		"a pawn that turned to look left is still drawn facing right")

	# Diagonals are the ordinary case: nothing in this game moves on an axis.
	pawn.facing = Vector2(-0.6, 0.8)
	assert_true(UnitView.facing_left(pawn))
	pawn.facing = Vector2(0.6, -0.8)
	assert_false(UnitView.facing_left(pawn))

## `Vector2.ZERO` is "no facing yet" per the field's own doc comment, and it is
## every unit on the first tick of every fight -- `Tools/FacingLoad.gd` counts
## 4,350 such unit-ticks in ten fights on `floor1_room1` alone. The team pose is
## kept for exactly that case, where it is a fair starting pose rather than a
## lie: the party deploys on the left looking right, the room is on the right
## looking back.
func test_a_unit_that_has_not_looked_anywhere_yet_keeps_its_starting_pose() -> void:
	var enemy := CombatUnit.new()
	enemy.team = CG.Team.ENEMY
	assert_eq(enemy.facing, Vector2.ZERO, "the fixture is wrong, not the rule")
	assert_true(UnitView.facing_left(enemy))
	var pawn := CombatUnit.new()
	pawn.team = CG.Team.PLAYER
	assert_false(UnitView.facing_left(pawn))

## A real fight, because the assertions above are about a function and this is
## about whether the fight ever disagrees with the old rule at all. If it never
## did, the change would be untestable churn and worth saying so.
func test_a_real_fight_turns_units_the_old_rule_would_have_drawn_backwards() -> void:
	var CombatSim := load("res://Scripts/Combat/CombatSim.gd")
	var PawnFactory := load("res://Scripts/Content/PawnFactory.gd")
	var party: Array[PawnDataScript] = []
	for id in [&"geysermancer", &"priest", &"siege_master", &"warrior"]:
		party.append(PawnFactory.make_starter_pawn(id, id, ClassLibrary.get_class_def(id).display_name))
	var state = CombatSim.build(party, RoomLibrary.get_room(&"floor1_rat_king"), 3)
	var disagreed := 0
	var looked := 0
	while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < 600:
		CombatSim.step(state)
		for u in state.units:
			if not u.alive or u.facing == Vector2.ZERO:
				continue
			looked += 1
			if UnitView.facing_left(u) != (u.team == CG.Team.ENEMY):
				disagreed += 1
	assert_true(looked > 0, "no unit in the whole fight ever acquired a facing, so this saw nothing")
	assert_true(disagreed > 0,
		("in %d unit-ticks with a real facing, none disagreed with the team rule -- " +
		"either the fight stopped turning units or this is measuring the wrong thing") % looked)
