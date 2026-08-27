extends "res://Tests/TestCase.gd"

const BattleScene := preload("res://Scenes/Battle.tscn")
const DamageFloaterScript := preload("res://Scripts/UI/DamageFloater.gd")

## Issue 537. A damage number, a death plate and a burst of debris mark WHERE
## THE EVENT HAPPENED and are then left alone -- issue 511's decision, and it
## stands. This is about which point that is. Since issue 501 a body is drawn
## between its last tick and this one, so on a stepped frame the raw
## `unit.position` is up to a tick ahead of the body the player can see.

## Half a tick of a walking pawn, which is the size of the gap this is about.
const _AHEAD := Vector2(6.0, 0.0)

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

func _make_encounter() -> RoomData:
	var e := RoomData.new()
	e.enemy_spawns = [{"enemy_id": &"test_dummy", "position": Vector2(120.0, 0.0)}]
	e.party_spawns = [Vector2(-120.0, 0.0)]
	return e

## A view mid-frame: the body has stepped to `unit.position` and the render is
## part way through sliding it there from a tick behind. `alpha` 0 puts the
## drawn body at the start of that slide, which is the largest the gap gets.
func _view_mid_step():
	DisplayOptions.reset()
	ViewClock.reset()
	var view = in_tree(BattleScene.instantiate())
	view._ready()
	var config := RunConfig.new()
	config.seed = 1
	config.party = _make_party()
	view.config = config
	view.state = CombatSim.build(config.party, _make_encounter(), config.seed)
	view.event_cursor = 0
	view._rebuild_units()
	view._curr_drawn = view._drawn_snapshot()
	view._prev_drawn = {}
	for id in view._curr_drawn:
		view._prev_drawn[id] = view._curr_drawn[id] - _AHEAD
	view._tick_accumulator = 0.0
	return view

func _target(view):
	return view.state.units[0]

## Where the body is on screen right now, taken from the same snapshot the
## renderer places it from rather than recomputed here.
func _drawn(view) -> Vector2:
	return view._prev_drawn[_target(view).id]

func _damage_event(view) -> CombatEvent:
	var e := CombatEvent.make(CG.EventKind.DAMAGE, 0)
	e.source_id = view.state.units[1].id
	e.target_id = _target(view).id
	e.amount = 12
	e.amount_before_mitigation = 12
	e.damage_type = CG.DamageType.PHYSICAL
	e.action_id = &"test_action"
	return e

func _feed(view, event: CombatEvent) -> void:
	view.state.events.append(event)
	view.consume_events()

func _floaters(view) -> Array:
	var out := []
	for child in view._arena.get_children():
		if child.get_script() == DamageFloaterScript:
			out.append(child)
	return out

# ---------------------------------------------------------------------------
# The gap itself, before anything is asserted about the marks
# ---------------------------------------------------------------------------

## The premise. If the drawn and the raw position ever stop differing here, the
## three tests below pass for a reason that has nothing to do with the fix.
func test_the_drawn_body_really_is_a_tick_behind_the_raw_position() -> void:
	var view = _view_mid_step()
	assert_ne(_drawn(view), _target(view).position,
		"this fixture no longer separates the drawn body from the raw one")
	assert_eq(_target(view).position - _drawn(view), _AHEAD,
		"and the gap must be the one the fixture set")

# ---------------------------------------------------------------------------
# Issue 537: planted at the drawn position, not the raw one
# ---------------------------------------------------------------------------

func test_a_damage_number_lands_on_the_body_the_player_can_see() -> void:
	var view = _view_mid_step()
	DisplayOptions.set_enabled(&"damage_numbers", true)
	_feed(view, _damage_event(view))
	var live := _floaters(view)
	assert_eq(live.size(), 1, "one hit must make one number")
	# Nothing else is on screen, so the stagger offset is zero and the number
	# sits exactly on its anchor -- test_ui_battle_floater_stagger pins that.
	assert_eq(live[0].position, _drawn(view),
		"the damage number was planted a tick ahead of the body it belongs to")
	DisplayOptions.reset()

func test_debris_is_thrown_from_the_body_the_player_can_see() -> void:
	var view = _view_mid_step()
	DisplayOptions.set_enabled(&"impact_particles", true)
	var next: int = view._bursts._next
	_feed(view, _damage_event(view))
	var emitter: GPUParticles2D = view._bursts._emitters[next]
	assert_eq(emitter.position, _drawn(view),
		"the debris was thrown from where the body will be, not where it is")
	DisplayOptions.reset()

func test_a_death_plate_is_raised_over_the_body_the_player_can_see() -> void:
	var view = _view_mid_step()
	var planted := _drawn(view)
	var death := CombatEvent.make(CG.EventKind.DEATH, 0)
	death.target_id = _target(view).id
	_feed(view, death)
	var live := _floaters(view)
	assert_eq(live.size(), 1, "one death must make one plate")
	assert_eq(live[0].position.x, planted.x,
		"the death plate was raised a tick ahead of the body that fell")

## The death case takes the other branch: a dead unit leaves `_curr_drawn`,
## which holds only the living, so the anchor comes from the last tick boundary
## the body reached. Asserted rather than assumed, because it is the branch the
## three tests above never enter.
func test_a_plate_for_a_body_already_gone_falls_back_to_its_last_drawn_place() -> void:
	var view = _view_mid_step()
	var target = _target(view)
	var planted: Vector2 = _drawn(view)
	view._curr_drawn.erase(target.id)
	assert_eq(view._drawn_event_position(target), planted,
		"a body out of the live snapshot must fall back to where it last stood")

# ---------------------------------------------------------------------------
# The negative: #511 is not being reversed
# ---------------------------------------------------------------------------

## A mark is planted once and never moves again. Without this, "follow the
## body" would pass every test above and drift the number away from the hit it
## describes, which is the defect #511 exists to prevent.
func test_a_planted_mark_does_not_follow_the_body_afterwards() -> void:
	var view = _view_mid_step()
	DisplayOptions.set_enabled(&"damage_numbers", true)
	_feed(view, _damage_event(view))
	var floater = _floaters(view)[0]
	var planted: Vector2 = floater.position
	var target = _target(view)
	target.position += Vector2(40.0, 0.0)
	view._curr_drawn = view._drawn_snapshot()
	view._render(1.0, true, 0.0)
	assert_eq(floater.position.x, planted.x,
		"the mark chased the body instead of marking where the hit landed")
	DisplayOptions.reset()
