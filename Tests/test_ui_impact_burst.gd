extends "res://Tests/TestCase.gd"

const BattleScene := preload("res://Scenes/Battle.tscn")
const ImpactBurstScript := preload("res://Scripts/UI/ImpactBurst.gd")
const DamageFloaterScript := preload("res://Scripts/UI/DamageFloater.gd")
const ImpactFlashScript := preload("res://Scripts/UI/ImpactFlash.gd")

## Issues 517 and 528: the debris a hit throws, and everything near the impact
## holding still while the hit stop holds.

func _reset() -> void:
	DisplayOptions.reset()
	ViewClock.reset()

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
	e.enemy_spawns = [{"enemy_id": &"test_dummy", "position": Vector2(80.0, 0.0)}]
	e.party_spawns = [Vector2(-80.0, 0.0)]
	return e

func _view():
	var view = in_tree(BattleScene.instantiate())
	view._ready()
	var config := RunConfig.new()
	config.seed = 1
	config.party = _make_party()
	view.config = config
	view.state = CombatSim.build(config.party, _make_encounter(), config.seed)
	view.event_cursor = 0
	view._rebuild_units()
	return view

## Through `consume_events`, the real path. A test that calls `_spawn_impact_burst`
## proves only that the private function works.
func _feed(view, event: CombatEvent) -> void:
	view.state.events.append(event)
	view.consume_events()

func _damage_event(view, damage_type: CG.DamageType = CG.DamageType.PHYSICAL) -> CombatEvent:
	var e := CombatEvent.make(CG.EventKind.DAMAGE, 0)
	e.source_id = view.state.units[1].id
	e.target_id = view.state.units[0].id
	e.amount = 12
	e.damage_type = damage_type
	e.action_id = &"test_action"
	return e

func _burst_node(view):
	return view._bursts

# ---------------------------------------------------------------------------
# The toggle, both directions
# ---------------------------------------------------------------------------

func test_the_option_exists_and_ships_on() -> void:
	_reset()
	assert_true(DisplayOptions.enabled(&"impact_particles"),
		"debris ships on; the epic wants the player to A/B it, not to hunt for it")

## Both directions: "nothing emitted" also passes when the emitter is broken.
func test_a_damage_event_throws_debris_only_while_the_option_is_on() -> void:
	_reset()
	var view = _view()
	DisplayOptions.set_enabled(&"impact_particles", false)
	_feed(view, _damage_event(view))
	assert_eq(_burst_node(view).live_bursts(), 0, "debris was thrown with the option off")

	DisplayOptions.set_enabled(&"impact_particles", true)
	_feed(view, _damage_event(view))
	assert_eq(_burst_node(view).live_bursts(), 1, "turning it on must throw debris")
	_reset()

## Poison, burn, bleed and hazard damage carry no `action_id` and have no point
## of impact. The same gate #516's squash uses, and for the same reason.
func test_a_ticking_status_throws_no_debris() -> void:
	_reset()
	var view = _view()
	var tick := _damage_event(view)
	tick.action_id = &""
	_feed(view, tick)
	assert_eq(_burst_node(view).live_bursts(), 0, "a poison tick threw debris")

	_feed(view, _damage_event(view))
	assert_eq(_burst_node(view).live_bursts(), 1, "but a real blow still must")
	_reset()

## A heal is not an impact and carries no damage type to colour debris by.
func test_a_heal_throws_no_debris() -> void:
	_reset()
	var view = _view()
	var heal := CombatEvent.make(CG.EventKind.HEAL, 0)
	heal.source_id = view.state.units[1].id
	heal.target_id = view.state.units[0].id
	heal.amount = 5
	_feed(view, heal)
	assert_eq(_burst_node(view).live_bursts(), 0, "a heal threw debris")
	_reset()

# ---------------------------------------------------------------------------
# Varying by damage type, which is the same colour the numbers use
# ---------------------------------------------------------------------------

func test_every_damage_type_colours_its_own_debris() -> void:
	_reset()
	var view = _view()
	for type in [CG.DamageType.PHYSICAL, CG.DamageType.FIRE, CG.DamageType.WATER,
			CG.DamageType.AIR, CG.DamageType.EARTH, CG.DamageType.DIVINE,
			CG.DamageType.PROFANE, CG.DamageType.RAW]:
		var before = _burst_node(view)._next
		_feed(view, _damage_event(view, type))
		var emitter: GPUParticles2D = _burst_node(view)._emitters[before]
		assert_eq(emitter.modulate, Palette.damage_color(type),
			"debris must use the colour the floating number uses")
	_reset()

# ---------------------------------------------------------------------------
# The count, which is the risk
# ---------------------------------------------------------------------------

## The pool is the cap. More hits than emitters must recycle rather than grow.
func test_more_hits_than_the_pool_recycles_instead_of_growing() -> void:
	_reset()
	var view = _view()
	for i in ImpactBurstScript.POOL * 3:
		_feed(view, _damage_event(view))
	assert_eq(_burst_node(view).live_bursts(), ImpactBurstScript.POOL,
		"the pool must cap the live count")
	assert_eq(_burst_node(view)._emitters.size(), ImpactBurstScript.POOL,
		"no emitter may be created after _ready")
	_reset()

# ---------------------------------------------------------------------------
# Issue 528: a hit stop is a COMPLETE stop
# ---------------------------------------------------------------------------

func test_a_frozen_floater_does_not_rise() -> void:
	_reset()
	var floater = in_tree(Node2D.new())
	floater.set_script(DamageFloaterScript)
	floater.position = Vector2(10.0, 20.0)
	floater.show_amount(7, Palette.TEXT)
	ViewClock.frozen = true
	floater._process(0.1)
	assert_eq(floater.position, Vector2(10.0, 20.0), "a frozen number moved")

	ViewClock.frozen = false
	floater._process(0.1)
	assert_ne(floater.position, Vector2(10.0, 20.0),
		"and it must move again once the freeze lifts")
	_reset()

func test_a_frozen_ring_does_not_expand() -> void:
	_reset()
	var flash = in_tree(Node2D.new())
	flash.set_script(ImpactFlashScript)
	flash.flash(CG.DamageType.PHYSICAL, 20.0)
	ViewClock.frozen = true
	flash._process(0.1)
	assert_eq(flash._age, 0.0, "a frozen ring aged")

	ViewClock.frozen = false
	flash._process(0.1)
	assert_true(flash._age > 0.0, "and it must age again once the freeze lifts")
	_reset()

## The death marker is a `DamageFloater` with a plate, so the fix covers it --
## asserted rather than assumed, because the issue asks for it by name.
func test_a_frozen_death_marker_does_not_rise() -> void:
	_reset()
	var marker = in_tree(Node2D.new())
	marker.set_script(DamageFloaterScript)
	marker.position = Vector2(0.0, 0.0)
	marker.show_death("Test dies", Palette.TEXT, 16)
	ViewClock.frozen = true
	marker._process(0.1)
	assert_eq(marker.position, Vector2(0.0, 0.0), "a frozen death marker moved")
	_reset()

func test_debris_holds_through_the_freeze_and_runs_again_after_it() -> void:
	_reset()
	var view = _view()
	_feed(view, _damage_event(view))
	var emitter: GPUParticles2D = _burst_node(view)._emitters[0]
	var running := emitter.speed_scale
	assert_true(running > 0.0, "debris must be running before the freeze")

	ViewClock.frozen = true
	_burst_node(view)._process(0.1)
	assert_eq(emitter.speed_scale, 0.0, "debris kept moving through the freeze")

	ViewClock.frozen = false
	_burst_node(view)._process(0.1)
	assert_eq(emitter.speed_scale, running, "debris must run at its own speed again")
	_reset()

## The hold starts on the frame AFTER the death, not on the frame of it. That
## frame still renders, and an overlay frozen inside it would keep the position
## it had before the render while its body moved -- which is issue 276 coming
## back. `test_ui_impact_flash` caught exactly that and it was right.
func test_the_hold_starts_on_the_frame_after_the_death() -> void:
	_reset()
	var view = _view()
	var death := CombatEvent.make(CG.EventKind.DEATH, 0)
	death.target_id = view.state.units[0].id
	_feed(view, death)
	assert_false(ViewClock.frozen, "the death froze the overlays inside its own frame")
	assert_true(view._freeze_left > 0.0, "but the freeze itself must be armed")

	view._process(0.001)
	assert_true(ViewClock.frozen, "and the next frame must hold")
	_reset()

## The negative: with the freeze turned off there is nothing to honour, and the
## overlays must be left alone. A check that cannot stay quiet is furniture.
func test_nothing_freezes_when_the_hit_stop_option_is_off() -> void:
	_reset()
	DisplayOptions.set_enabled(&"hit_stop", false)
	var view = _view()
	var death := CombatEvent.make(CG.EventKind.DEATH, 0)
	death.target_id = view.state.units[0].id
	_feed(view, death)
	assert_false(ViewClock.frozen, "the view clock froze with hit stop off")
	_reset()

# ---------------------------------------------------------------------------
# Issue 535: pause is the other trigger, and pause is what the player uses to
# look at a hit. An overlay that ages through it takes away the thing pause is
# for -- the ring is gone in 0.8s and the death plate in 2.4s.
# ---------------------------------------------------------------------------

func test_pausing_freezes_the_overlays() -> void:
	_reset()
	var view = _view()
	_feed(view, _damage_event(view))
	view.set_paused(true)
	view._process(0.1)
	assert_true(ViewClock.frozen, "a paused fight kept animating its overlays")
	_reset()

## The negative. A freeze that never lifts is the same defect wearing the other
## sign, and it is invisible: the picture simply stops.
func test_resuming_releases_the_overlays() -> void:
	_reset()
	var view = _view()
	_feed(view, _damage_event(view))
	view.set_paused(true)
	view._process(0.1)
	view.set_paused(false)
	view._process(0.1)
	assert_false(ViewClock.frozen, "the overlays stayed frozen after the resume")
	_reset()

## Pause HOLDS a hit stop rather than spending it. The pause return sits above
## the `_freeze_left` decrement for this reason, and the ordering is easy to
## tidy away.
func test_a_pause_holds_a_hit_stop_rather_than_spending_it() -> void:
	_reset()
	var view = _view()
	var death := CombatEvent.make(CG.EventKind.DEATH, 0)
	death.target_id = view.state.units[0].id
	_feed(view, death)
	var armed: float = view._freeze_left
	assert_true(armed > 0.0, "the death must arm a freeze")

	view.set_paused(true)
	for i in 5:
		view._process(0.1)
	assert_eq(view._freeze_left, armed, "the pause spent the hit stop it was holding")
	assert_true(ViewClock.frozen, "and it must still read as frozen")

	view.set_paused(false)
	view._process(0.1)
	assert_true(view._freeze_left < armed, "the freeze must run again once the pause lifts")
	_reset()
