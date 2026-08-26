extends "res://Tests/TestCase.gd"

const BattleScene := preload("res://Scenes/Battle.tscn")

## Issue 553: the struck body goes white for a moment. View only, its own
## toggle, and it must decay under a hit stop rather than through one.

func _unit(id: int, team: CG.Team, at: Vector2) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.display_name = "u%d" % id
	u.position = at
	u.hp = 10
	u.hp_max = 10
	return u

func _view_with_pair(apart: float = 20.0) -> Node2D:
	var state := CombatState.new(1)
	state.units.append(_unit(0, CG.Team.PLAYER, Vector2.ZERO))
	state.units.append(_unit(1, CG.Team.ENEMY, Vector2(apart, 0.0)))
	var view = in_tree(BattleScene.instantiate())
	view.state = state
	view.event_cursor = 0
	view._rebuild_units()
	return view

func _damage(source: int, target: int, action: StringName,
		damage_type: CG.DamageType = CG.DamageType.PHYSICAL) -> CombatEvent:
	var e := CombatEvent.make(CG.EventKind.DAMAGE, 1)
	e.source_id = source
	e.target_id = target
	e.action_id = action
	e.amount = 3
	e.damage_type = damage_type
	return e

func _flash_on() -> Node2D:
	DisplayOptions.set_enabled(&"hit_flash", true)
	DisplayOptions.set_enabled(&"impact_squash", false)
	return _view_with_pair()

func _clear() -> void:
	DisplayOptions.reset()
	UnitView.reset_flash_tint()

# --- the shape of the decay ------------------------------------------------

func test_the_flash_is_brightest_at_the_moment_of_the_blow() -> void:
	assert_almost_eq(UnitView.flash_strength(0.0), UnitView.FLASH_STRENGTH)

## Short of opaque: a body washed fully white stops being that body, and the
## point of putting the mark on the silhouette is that you can still read it.
func test_the_flash_never_covers_the_body_completely() -> void:
	assert_true(UnitView.FLASH_STRENGTH < 1.0,
		"a fully opaque flash is a white plate, not a lit body")

func test_the_flash_is_gone_by_the_end_of_its_span() -> void:
	assert_eq(UnitView.flash_strength(UnitView.FLASH_SECONDS), 0.0)
	assert_eq(UnitView.flash_strength(99.0), 0.0)
	assert_eq(UnitView.flash_strength(INF), 0.0)

## Faster than the squash. A colour change that outlasts the shape change reads
## as a status the unit is carrying rather than as the blow landing.
func test_the_flash_is_shorter_than_the_squash() -> void:
	assert_true(UnitView.FLASH_SECONDS < UnitView.SQUASH_SECONDS,
		"%.3f is not shorter than %.3f" % [UnitView.FLASH_SECONDS, UnitView.SQUASH_SECONDS])

# --- white, and what it would take to tint ----------------------------------

func test_what_ships_is_white_whatever_the_damage_type() -> void:
	for d in CG.DamageType.values():
		assert_eq(UnitView.flash_color(d), Color.WHITE,
			"the shipped flash is typeless: the floater, the ring and the debris carry the type")

func test_the_tint_knob_leans_the_flash_toward_the_damage_colour() -> void:
	UnitView.flash_tint = 1.0
	assert_true(UnitView.flash_color(CG.DamageType.FIRE).is_equal_approx(
		Palette.damage_color(CG.DamageType.FIRE)))
	UnitView.flash_tint = 0.5
	var half := UnitView.flash_color(CG.DamageType.FIRE)
	assert_true(half != Color.WHITE and half != Palette.damage_color(CG.DamageType.FIRE))
	_clear()

## `-1` is what a caller with no type to give passes. Even fully tinted it must
## stay white rather than picking a colour out of the air.
func test_a_hit_with_no_damage_type_stays_white_even_tinted() -> void:
	UnitView.flash_tint = 1.0
	assert_eq(UnitView.flash_color(-1), Color.WHITE)
	_clear()

# --- what a damage event does ----------------------------------------------

func test_a_hit_lights_the_target_and_not_the_attacker() -> void:
	var view := _flash_on()
	view.state.emit(_damage(1, 0, &"basic_attack"))
	view.consume_events()

	assert_true(view._unit_views[0].impact_active(), "the struck body should be lit")
	assert_true(UnitView.flash_strength(view._unit_views[0]._flash_age) > 0.0)
	assert_false(view._unit_views[1].impact_active(), "nothing hit the attacker")
	_clear()

## `_apply_impact` gates on `action_id`, and the flash rides that same gate.
## Poison, burn, bleed and hazard damage emit one DAMAGE per afflicted unit per
## TICK, so ungated a poisoned pawn strobes fifteen times a second.
func test_damage_over_time_lights_nothing() -> void:
	var view := _flash_on()
	view.state.emit(_damage(1, 0, &""))
	view.consume_events()

	assert_false(view._unit_views[0].impact_active(), "a poison tick is not a blow")
	_clear()

## The event's type reaches the view even though nothing shipped leans on it.
func test_the_damage_type_reaches_the_body() -> void:
	var view := _flash_on()
	view.state.emit(_damage(1, 0, &"fire_bolt", CG.DamageType.FIRE))
	view.consume_events()
	assert_eq(view._unit_views[0]._flash_type, int(CG.DamageType.FIRE))
	_clear()

# --- the negative cases ----------------------------------------------------

func test_the_toggle_off_never_lights_anything() -> void:
	DisplayOptions.set_enabled(&"hit_flash", false)
	DisplayOptions.set_enabled(&"impact_squash", false)
	var view := _view_with_pair()
	view.state.emit(_damage(1, 0, &"basic_attack"))
	view.consume_events()

	var struck: Node2D = view._unit_views[0]
	assert_false(struck.impact_active())
	for i in 12:
		struck.advance_impact(1.0 / 60.0)
		assert_eq(UnitView.flash_strength(struck._flash_age), 0.0,
			"a body lit while the option is off")
	_clear()

## The two options are independent: one is a shape and one is a colour, and the
## panel offers them as two rows.
func test_the_squash_toggle_does_not_gate_the_flash() -> void:
	DisplayOptions.set_enabled(&"hit_flash", true)
	DisplayOptions.set_enabled(&"impact_squash", false)
	var view := _view_with_pair()
	view.state.emit(_damage(1, 0, &"basic_attack"))
	view.consume_events()

	var struck: Node2D = view._unit_views[0]
	assert_true(UnitView.flash_strength(struck._flash_age) > 0.0, "the flash needs no squash")
	assert_eq(UnitView.squash_scale(struck._squash_age), Vector2.ONE, "the squash is off")
	_clear()

func test_the_flash_ends_and_gives_the_frame_back() -> void:
	var view := _flash_on()
	view.state.emit(_damage(1, 0, &"basic_attack"))
	view.consume_events()

	var struck: Node2D = view._unit_views[0]
	assert_true(struck.impact_active())
	for i in 60:
		struck.advance_impact(1.0 / 60.0)
	assert_false(struck.impact_active(), "one second is eight spans")
	assert_eq(UnitView.flash_strength(struck._flash_age), 0.0)
	assert_eq(struck._flash_type, -1, "the type must be dropped with the flash")
	_clear()

## The trap #515 and #516 fell into together, one span shorter. `_render` only
## spends a delta on a view `impact_active` says is busy, so a flash left out of
## that check would freeze part-lit the moment the squash expired.
func test_the_flash_alone_keeps_the_body_active_until_it_is_done() -> void:
	var view := _flash_on()
	view.state.emit(_damage(1, 0, &"basic_attack"))
	view.consume_events()

	var struck: Node2D = view._unit_views[0]
	var steps := 0
	while struck.impact_active() and steps < 600:
		struck.advance_impact(1.0 / 240.0)
		steps += 1
	assert_eq(UnitView.flash_strength(struck._flash_age), 0.0,
		"the body stopped being advanced while it was still lit")

	_clear()

## Issue 515 freezes the picture by returning out of `_process` before
## `_render`. A flash driven by a `_process` of this view's own would keep
## fading through that hold, which is motion in a picture that has stopped.
func test_a_hit_stop_holds_the_flash_with_everything_else() -> void:
	DisplayOptions.set_enabled(&"hit_flash", true)
	DisplayOptions.set_enabled(&"hit_stop", true)
	var view := _view_with_pair()
	view.state.emit(_damage(1, 0, &"basic_attack"))
	view.consume_events()
	view._hit_stop()

	var struck: Node2D = view._unit_views[0]
	var held := UnitView.flash_strength(struck._flash_age)
	assert_true(held > 0.0, "nothing was lit, so the test would pass vacuously")
	for i in 6:
		view._process(1.0 / 60.0)
	assert_eq(UnitView.flash_strength(struck._flash_age), held,
		"the body faded during a freeze frame")
	_clear()

# --- the line that must not be crossed --------------------------------------

func test_the_flash_never_reaches_the_simulation() -> void:
	var view := _flash_on()
	var before: Array = []
	for u in view.state.units:
		before.append([u.position, u.hp, u.radius])
	view.state.emit(_damage(1, 0, &"basic_attack"))
	view.consume_events()
	var struck: Node2D = view._unit_views[0]
	for i in 4:
		struck.advance_impact(1.0 / 60.0)

	for i in view.state.units.size():
		var u: CombatUnit = view.state.units[i]
		assert_eq(u.position, before[i][0], "a flash moved a simulated position")
		assert_eq(u.hp, before[i][1])
		assert_eq(u.radius, before[i][2])
	_clear()

## The flash is a tint on the part sprites rather than a white copy drawn over
## them. The parts are binary-alpha masks, so tinting one toward white by `a` and
## drawing white over it at alpha `a` put the same colour on the screen -- and the
## white copy that used to slide out from under a thrust hand cannot exist.
func test_the_flash_tints_every_part_toward_white() -> void:
	var visual := in_tree(UnitVisual.new())
	visual.build(&"warrior", CG.Team.PLAYER, 40.0)
	var own := UnitArt.sprites_for(&"warrior", CG.Team.PLAYER)
	assert_false(own.is_empty(), "the warrior has no parts; this test measures nothing")

	visual.flash(Color.WHITE, 0.0)
	var rested := _modulates(visual)
	assert_eq(rested.size(), own.size(), "a sprite per part")
	for i in own.size():
		assert_eq(rested[i], own[i]["color"], "an unstruck part is not its own colour")

	visual.flash(Color.WHITE, 1.0)
	for c: Color in _modulates(visual):
		assert_eq(c, Color.WHITE, "a fully lit part is not white")

	visual.flash(Color.WHITE, 0.5)
	var half := _modulates(visual)
	for i in own.size():
		assert_eq(half[i], (own[i]["color"] as Color).lerp(Color.WHITE, 0.5),
			"a half-lit part is not halfway to white")

func _modulates(visual: UnitVisual) -> Array:
	var out: Array = []
	for slot in visual._body.get_children():
		for sprite in slot.get_children():
			out.append(sprite.modulate)
	return out

## The player's ruling, and the arena is where it stopped being true. `draw_unit`
## drew a black square for a shape with no art; a sprite tree of six empty slots
## draws NOTHING, and an invisible unit is issue #75 -- a defect that reads as the
## unit not existing rather than as art being missing.
func test_a_shape_with_no_recipe_is_a_visible_black_square() -> void:
	assert_false(UnitRecipes.has_recipe(&"not_a_real_shape"),
		"this test needs a shape nothing draws")
	var visual := in_tree(UnitVisual.new())
	visual.build(&"not_a_real_shape", CG.Team.ENEMY, 40.0)
	var drawn: Array = []
	for slot in visual._body.get_children():
		for sprite in slot.get_children():
			drawn.append(sprite)
	assert_eq(drawn.size(), 1, "a shape with no recipe must draw exactly one mark")
	assert_not_null(drawn[0].texture, "the mark has no texture")
	assert_eq(drawn[0].modulate, Color.BLACK, "the mark is not black")
	assert_eq(drawn[0].scale, Vector2(80.0, 80.0),
		"the square must fill the footprint, or it is a speck rather than a defect")

	# The negative half: a real shape must NOT get the square.
	var goblin := in_tree(UnitVisual.new())
	goblin.build(&"goblin", CG.Team.ENEMY, 40.0)
	var parts := 0
	for slot in goblin._body.get_children():
		parts += slot.get_child_count()
	assert_eq(parts, UnitArt.sprites_for(&"goblin", CG.Team.ENEMY).size(),
		"a goblin must draw its own parts and nothing else")
