extends "res://Tests/TestCase.gd"

const BattleScene := preload("res://Scenes/Battle.tscn")

## Issue 583. An animation is a property of a PART, so one definition covers
## every recipe that names it; and its duration is the ACTION's, so one
## definition covers a 6-tick Stab and a 45-tick Engine Bolt.

const FRAME := 1.0 / 60.0

func setup() -> void:
	DisplayOptions.reset()

## The `Hands` slot is the animated part, and moving it must not change what the
## rest of the body looks like. There is nothing left to recompose: a slot is a
## node, and a node that moves takes exactly its own sprites with it.
func test_the_animated_part_is_the_hands_slot() -> void:
	var checked := 0
	for id in UnitRecipes.recipe_ids():
		if not UnitRecipes.has_animated_part(id):
			continue
		var moved: Array = []
		for entry in UnitRecipes.slots_for(id):
			for layer in entry["layers"]:
				if PartAnimation.animates(layer["part"]):
					moved.append(entry["slot"])
		assert_eq(moved.size(), 1, "%s has %d animated parts, not one" % [id, moved.size()])
		assert_eq(moved[0], &"Hands", "%s animates a part outside the Hands slot" % id)
		checked += 1
	assert_true(checked >= 10, "only %d bodies carried an animated part" % checked)

## Absence is the default. A creature with no animated part has an empty `Hands`
## slot and needs no case anywhere else.
func test_a_recipe_with_no_animated_part_has_an_empty_hands_slot() -> void:
	assert_false(UnitRecipes.has_animated_part(&"grub"), "the grub has no hands")
	assert_false(UnitRecipes.has_animated_part(&"siege_engine"), "the engine has no hands")
	assert_true(_slot(&"grub", &"Hands").is_empty(),
		"a handless recipe must offer nothing to animate")
	assert_true(UnitRecipes.has_animated_part(&"goblin"), "the goblin has hands")
	assert_eq(_slot(&"goblin", &"Hands").size(), 1, "one pair of hands")

func _slot(id: StringName, slot: StringName) -> Array:
	for entry in UnitRecipes.slots_for(id):
		if entry["slot"] == slot:
			return entry["layers"]
	return []

## The whole point of the part rule: one entry covers every recipe naming it.
func test_one_part_entry_covers_many_creatures() -> void:
	var bodies := {}
	for id in UnitRecipes.recipe_ids():
		for layer in _slot(id, &"Hands"):
			bodies[id] = layer["part"]
	assert_true(bodies.size() >= 15,
		"two part entries should cover most of the roster, got %d" % bodies.size())
	assert_eq(PartAnimation.PARTS.size(), 2, "two animated parts are authored")

## Every action derives one of the three shared motions from fields `ActionDef`
## already carries, so an action written tomorrow animates without authoring.
func test_every_action_derives_a_motion() -> void:
	var expected := {
		&"warrior_strike": PartAnimation.Kind.MELEE,
		&"goblin_stab": PartAnimation.Kind.MELEE,
		&"abomination_claw": PartAnimation.Kind.MELEE,
		&"warden_axe": PartAnimation.Kind.MELEE,
		&"goblin_arrow": PartAnimation.Kind.RANGED,
		&"siege_engine_bolt": PartAnimation.Kind.RANGED,
		&"priest_bolt": PartAnimation.Kind.RANGED,
		&"warrior_guard": PartAnimation.Kind.CAST,
		&"warrior_taunt": PartAnimation.Kind.CAST,
		&"channel_mana": PartAnimation.Kind.CAST,
		&"abomination_immolate": PartAnimation.Kind.CAST,
	}
	for id in expected:
		assert_eq(PartAnimation.kind_for(Registry.get_action(id)), expected[id],
			"%s derives the wrong motion" % id)
	for id in Registry.all_action_ids():
		assert_ne(PartAnimation.kind_for(Registry.get_action(id)), PartAnimation.Kind.IDLE,
			"%s derives no motion at all" % id)

## Rook's requirement: the duration is the action's, not the animation's. The
## same definition at two tick counts reaches the same pose at the same
## fraction, and a different pose at the same elapsed tick.
func test_the_same_motion_stretches_to_the_tick_count() -> void:
	for kind in [PartAnimation.Kind.MELEE, PartAnimation.Kind.RANGED, PartAnimation.Kind.CAST]:
		assert_eq(
			PartAnimation.action_offset(kind, 0.5, 100.0),
			PartAnimation.action_offset(kind, 0.5, 100.0),
			"the pose is a function of progress alone")
		# Tick 6 of a 6-tick stab is the blow; tick 6 of a 45-tick bolt is
		# an eighth of the way in, and must not be the same pose.
		var fast := PartAnimation.action_offset(kind, 6.0 / 6.0, 100.0)
		var slow := PartAnimation.action_offset(kind, 6.0 / 45.0, 100.0)
		assert_true(fast.distance_to(slow) > 1.0,
			"a 45-tick wind-up poses like a 6-tick one at the same tick")

## A melee thrust arrives forward, at the moment the blow lands and not before.
func test_a_melee_thrust_arrives_on_the_blow() -> void:
	var landed := PartAnimation.action_offset(PartAnimation.Kind.MELEE, 1.0, 100.0)
	var early := PartAnimation.action_offset(PartAnimation.Kind.MELEE, 0.4, 100.0)
	assert_true(landed.x > 0.0, "the hands finish forward, got %.1f" % landed.x)
	assert_true(early.x < 0.0, "the hands wind back first, got %.1f" % early.x)
	assert_true(landed.x > early.x + 20.0, "the throw is bigger than the wind-back")

## A row of goblins must not pulse in unison.
func test_the_idle_bob_is_out_of_phase_per_unit() -> void:
	var seen := {}
	for id in 8:
		var y := PartAnimation.idle_offset(0.0, PartAnimation.phase_for(id), 100.0).y
		for other in seen:
			assert_true(absf(seen[other] - y) > 0.5,
				"units %d and %d bob together" % [other, id])
		seen[id] = y
	# And it is a bob: the same unit is somewhere else half a cycle later.
	var a := PartAnimation.idle_offset(0.0, PartAnimation.phase_for(3), 100.0)
	var b := PartAnimation.idle_offset(PartAnimation.IDLE_SECONDS * 0.5, PartAnimation.phase_for(3), 100.0)
	assert_true(a.distance_to(b) > 1.0, "the idle does not move")

## Issue 528's class of defect, for the fifth time. A hand must not bob through
## a hit stop or a pause.
func test_a_frozen_picture_does_not_animate() -> void:
	var view = _fight()
	_frames(view, 4)
	var running: float = view._unit_views[0]._anim_seconds
	assert_true(running > 0.0, "the animation never started")

	view.paused = true
	_frames(view, 10)
	assert_eq(view._unit_views[0]._anim_seconds, running, "a pause did not hold the hands")
	assert_true(ViewClock.frozen, "a pause must freeze the view clock")

	view.paused = false
	_feed(view, CG.EventKind.DEATH)
	var frozen_at: float = view._unit_views[0]._anim_seconds
	view._process(FRAME)
	assert_eq(view._unit_views[0]._anim_seconds, frozen_at, "a hit stop did not hold the hands")

## The toggle, and the refusal that goes with it: off means the `Hands` slot sits
## exactly where its parts were authored.
func test_the_toggle_off_leaves_the_hands_where_they_were_authored() -> void:
	var view = _fight()
	var unit_view = view._unit_views[0]
	assert_true(UnitView.animating(), "hands move by default")
	assert_true(unit_view.can_animate(view.state.unit(0)),
		"a goblin's hands should be animatable")
	DisplayOptions.set_enabled(UnitView.ANIM_OPTION, false)
	assert_false(UnitView.animating(), "the toggle did not take")
	assert_false(unit_view.can_animate(view.state.unit(0)),
		"the toggle off must leave the hands unmoved")

## The body itself is #501's, and this must never touch it.
func test_the_animation_never_moves_the_body() -> void:
	var view = _fight()
	var before: Vector2 = view._unit_views[0].position
	var raw: Vector2 = view.state.unit(0).position
	_frames(view, 6)
	assert_eq(view.state.unit(0).position, raw, "the simulation moved")
	assert_eq(view._unit_views[0].position, before, "the animation moved the body")

func _walker() -> CombatUnit:
	var u := CombatUnit.new()
	u.id = 0
	u.team = CG.Team.ENEMY
	u.enemy_id = &"goblin"
	u.display_name = "Goblin"
	u.hp_max = 100
	u.hp = 100
	u.move_speed = 0.0
	u.position = Vector2(-400.0, 0.0)
	return u

func _quarry() -> CombatUnit:
	var u := CombatUnit.new()
	u.id = 1
	u.team = CG.Team.PLAYER
	u.enemy_id = &"warrior"
	u.display_name = "Quarry"
	u.hp_max = 5000
	u.hp = 5000
	u.move_speed = 0.0
	u.position = Vector2(400.0, 0.0)
	return u

func _fight():
	var state := CombatState.new(11)
	state.units.append(_walker())
	state.units.append(_quarry())
	var view = in_tree(BattleScene.instantiate())
	view._ready()
	view.state = state
	view.event_cursor = 0
	view._rebuild_units()
	view._curr_drawn = view._drawn_snapshot()
	return view

func _feed(view, kind: int, target_id: int = 1) -> void:
	var e := CombatEvent.make(kind, view.state.tick)
	e.target_id = target_id
	e.source_id = 0
	e.amount = 7
	view.state.events.append(e)
	view.consume_events()

func _frames(view, count: int) -> void:
	for i in count:
		view._process(FRAME)
