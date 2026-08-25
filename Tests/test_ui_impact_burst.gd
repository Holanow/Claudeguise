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

const DAMAGE_TYPES := [CG.DamageType.PHYSICAL, CG.DamageType.FIRE, CG.DamageType.WATER,
	CG.DamageType.AIR, CG.DamageType.EARTH, CG.DamageType.DIVINE,
	CG.DamageType.PROFANE, CG.DamageType.RAW]

## Issue 539, same family as 280. The pixel a hit throws is the sprite TIMES
## the tint, and `modulate` is only one half of that multiply: with the file
## gone the black-square fallback ships, black times any tint is black, and
## every damage type throws identical debris while a `modulate` assertion goes
## on passing. Sampled off the emitter's own texture, so it is the picture that
## ships rather than the property that feeds it.
func _debris_pixels(emitter: GPUParticles2D, grid: int) -> PackedColorArray:
	var out := PackedColorArray()
	if emitter.texture == null:
		return out
	var image := emitter.texture.get_image()
	for gy in grid:
		for gx in grid:
			var x := mini(int((float(gx) + 0.5) / float(grid) * float(image.get_width())), image.get_width() - 1)
			var y := mini(int((float(gy) + 0.5) / float(grid) * float(image.get_height())), image.get_height() - 1)
			out.append(image.get_pixel(x, y) * emitter.modulate)
	return out

## The fraction of sampled pixels two bursts disagree on, the same shape and the
## same tolerance `test_art.gd` uses on the badges.
func _pixel_difference(a: PackedColorArray, b: PackedColorArray) -> float:
	if a.is_empty() or a.size() != b.size():
		return 0.0
	var differing := 0
	for i in a.size():
		var d := absf(a[i].r - b[i].r) + absf(a[i].g - b[i].g) + absf(a[i].b - b[i].b) + absf(a[i].a - b[i].a)
		if d > 0.12:
			differing += 1
	return float(differing) / float(a.size())

func _debris_for_each_type(view, grid: int) -> Dictionary:
	var out := {}
	for type in DAMAGE_TYPES:
		var before = _burst_node(view)._next
		_feed(view, _damage_event(view, type))
		out[type] = _debris_pixels(_burst_node(view)._emitters[before], grid)
	return out

func test_every_damage_type_colours_its_own_debris() -> void:
	_reset()
	var view = _view()
	var grid := 8
	var pixels := _debris_for_each_type(view, grid)
	for type in DAMAGE_TYPES:
		assert_false(pixels[type].is_empty(),
			"the debris for %s rasterised to nothing at all" % CG.DamageType.keys()[type])

	var worst := 1.0
	var worst_pair := ""
	for a in DAMAGE_TYPES:
		for b in DAMAGE_TYPES:
			if a >= b:
				continue
			var d := _pixel_difference(pixels[a], pixels[b])
			if d < worst:
				worst = d
				worst_pair = "%s/%s" % [CG.DamageType.keys()[a], CG.DamageType.keys()[b]]
	assert_true(worst > 0.5,
		("%s debris render the same picture on %.0f%% of their pixels. Scalding "
		+ "water and a sword must not throw the same debris -- if the sprite is "
		+ "missing, every type is throwing black squares.") % [worst_pair, (1.0 - worst) * 100.0])
	_reset()

## The other half: distinct is not enough, they have to be the colours the
## floating numbers use. Also in pixels, off the same rasterisation.
func test_debris_pixels_carry_the_colour_the_floating_number_uses() -> void:
	_reset()
	var view = _view()
	var grid := 8
	var pixels := _debris_for_each_type(view, grid)
	var reference: GPUParticles2D = _burst_node(view)._emitters[0]
	for type in DAMAGE_TYPES:
		reference.modulate = Palette.damage_color(type)
		var want := _debris_pixels(reference, grid)
		assert_false(want.is_empty(), "there is no debris sprite to rasterise")
		assert_eq(_pixel_difference(pixels[type], want), 0.0,
			"%s debris are not drawn in that type's own colour" % CG.DamageType.keys()[type])
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
	# #573 deleted the damage ring; `flash_color` is the interrupt cue and the
	# only entry point left. The freeze behaviour under test is the same.
	flash.flash_color(Palette.TEXT, 20.0)
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
