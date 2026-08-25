extends "res://Tests/TestCase.gd"

const BattleScene := preload("res://Scenes/Battle.tscn")

## Issue 151. The player asked for the stun interrupt twice over: "the stun icon
## should appear and the unit should flash white or something". The badge is
## already drawn from the STATUS_APPLIED on the same tick and says WHAT
## happened; the flash says it happened NOW, which is the half a badge cannot do
## for someone watching a fight without pausing.

func _view(state: CombatState) -> Node:
	var view = in_tree(BattleScene.instantiate())
	view.state = state
	view.event_cursor = 0
	return view

func _state_with_one_unit() -> CombatState:
	var state := CombatState.new(1)
	var caster := CombatUnit.new()
	caster.id = 0
	caster.display_name = "Geysermancer"
	caster.position = Vector2(40.0, 60.0)
	state.units.append(caster)
	return state

func _flashes(arena: Node) -> Array:
	var out: Array = []
	for child in arena.get_children():
		if child.get_script() == ImpactFlash:
			out.append(child)
	return out

func test_an_interrupt_flashes_the_pawn_that_lost_the_action() -> void:
	var state := _state_with_one_unit()
	var view := _view(state)
	var arena := view.get_node("Arena")
	assert_eq(_flashes(arena).size(), 0, "nothing has happened yet")

	var e := CombatEvent.make(CG.EventKind.INTERRUPTED, 5)
	# source_id, not target_id: INTERRUPTED names the unit that LOST the
	# action, and target_id is -1 on this kind. Reading target_id here is the
	# mistake this test exists to catch -- it would spawn nothing at all and
	# look exactly like a working feature.
	e.source_id = 0
	e.target_id = -1
	e.action_id = &"geyser_spout"
	e.amount = 15
	state.emit(e)
	view.consume_events()

	var flashes := _flashes(arena)
	assert_eq(flashes.size(), 1, "an INTERRUPTED event must flash the pawn")
	assert_eq(flashes[0].position, Vector2(40.0, 60.0), "the flash must land on the pawn that lost the action")

## The negative half. A detector that fires on everything is worse than one that
## fires on nothing: the player learns to ignore it in minutes. Nothing but an
## interrupt may spawn this flash from a non-damage event.
func test_ordinary_events_do_not_flash_the_pawn_white() -> void:
	var state := _state_with_one_unit()
	var view := _view(state)
	var arena := view.get_node("Arena")

	for kind in [CG.EventKind.ACTION_START, CG.EventKind.ACTION_FIRE,
			CG.EventKind.RESOURCE_SPENT, CG.EventKind.SUSTAIN_START,
			CG.EventKind.SUSTAIN_END, CG.EventKind.STATUS_APPLIED]:
		var e := CombatEvent.make(kind, 5)
		e.source_id = 0
		e.target_id = 0
		state.emit(e)
	view.consume_events()

	assert_eq(_flashes(arena).size(), 0,
		"only an interrupt flashes: %s" % str(_flashes(arena)))

func test_an_interrupt_naming_no_such_pawn_spawns_nothing() -> void:
	var state := _state_with_one_unit()
	var view := _view(state)
	var arena := view.get_node("Arena")

	var e := CombatEvent.make(CG.EventKind.INTERRUPTED, 5)
	e.source_id = 99
	state.emit(e)
	view.consume_events()

	assert_eq(_flashes(arena).size(), 0)

## The flash is white rather than a damage colour, because an interrupt is not
## damage and has no damage type. Borrowing one would put a lie into the
## vocabulary the floating numbers and the projectile marks share, and it would
## read as "something hit you" when nothing did.
func test_the_interrupt_flash_is_white_not_a_damage_colour() -> void:
	var flash := Node2D.new()
	flash.set_script(ImpactFlash)
	flash.flash_color(Palette.TEXT, 20.0)
	assert_eq(flash._color_override, Palette.TEXT)

	# And the damage path still leaves the override off, so a hit keeps its
	# damage-type colour. A node is reused between flashes nowhere today, but
	# the two entry points must not leak into each other if one ever is.
	flash.flash(CG.DamageType.FIRE, 20.0)
	assert_eq(flash._color_override.a, 0.0, "flash() must clear the override")
	flash.free()


## Moved here from `test_ui_impact_flash.gd`, which #573 deleted along with the
## damage ring. The node still exists and still runs on the wall clock; it is
## the interrupt cue that owns it now, so its lifetime is asserted here.

func test_flash_color_starts_the_clock() -> void:
	var flash := ImpactFlash.new()
	flash.flash_color(Palette.TEXT, 20.0)
	assert_true(flash.is_processing())
	flash.free()

func test_the_flash_frees_itself_after_its_lifetime() -> void:
	var flash := ImpactFlash.new()
	flash.flash_color(Palette.TEXT, 20.0)
	flash._process(ImpactFlash.LIFETIME_SECONDS + 0.01)
	assert_true(not is_instance_valid(flash) or flash.is_queued_for_deletion())
