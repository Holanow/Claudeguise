extends "res://Tests/TestCase.gd"

## Issue 390: forty live numbers at one tick, and past about a dozen no stagger
## can separate them -- twenty text extents need more area than the 250x200
## patch the fight occupies. Dropping the oldest loses information; adding them
## up does not.

const BattleScene := preload("res://Scenes/Battle.tscn")
const DamageFloaterScript := preload("res://Scripts/UI/DamageFloater.gd")

func _party() -> Array[PawnData]:
	var cls := ClassDef.new()
	cls.id = &"test_class"
	cls.display_name = "Test Class"
	var pawn := PawnData.new()
	pawn.id = &"test_pawn"
	pawn.display_name = "Test Pawn"
	pawn.pawn_class = cls
	var out: Array[PawnData] = [pawn]
	return out

func _encounter() -> Encounter:
	var e := Encounter.new()
	e.enemy_spawns = [
		{"enemy_id": &"test_dummy", "position": Vector2(80.0, 0.0)},
		{"enemy_id": &"test_dummy", "position": Vector2(120.0, 0.0)},
	]
	e.party_spawns = [Vector2(-80.0, 0.0)]
	return e

func _view():
	DisplayOptions.reset()
	DisplayOptions.set_enabled(&"damage_numbers", true)
	var view = BattleScene.instantiate()
	view._ready()
	var config := RunConfig.new()
	config.seed = 1
	config.party = _party()
	view.config = config
	view.state = CombatSim.build(config.party, _encounter(), config.seed)
	view.event_cursor = 0
	view._rebuild_units()
	return view

## Through `consume_events`, the path the game takes, not `_spawn_floater`.
func _hit(view, target_id: int, amount: int, damage_type: int = CG.DamageType.FIRE) -> void:
	var e := CombatEvent.make(CG.EventKind.DAMAGE, view.state.tick)
	e.target_id = target_id
	e.amount = amount
	e.damage_type = damage_type
	view.state.events.append(e)
	view.consume_events()

func _floaters(view) -> Array:
	var out: Array = []
	for child in view._arena.get_children():
		if child.get_script() == DamageFloaterScript and not child.death_marker:
			out.append(child)
	return out

func _age(view, seconds: float) -> void:
	for f in _floaters(view):
		f._process(seconds)

func test_six_ticks_on_one_pawn_are_one_running_total() -> void:
	var view = _view()
	for i in 6:
		_hit(view, view.state.units[1].id, 3)
	var live := _floaters(view)
	assert_eq(live.size(), 1, "six ticks of burn drew %d numbers" % live.size())
	assert_eq(live[0].amount, 18, "the total must be the sum, not the last tick")
	assert_eq(live[0]._text, "18")
	DisplayOptions.reset()
	view.free()

## The merge must not join two facts. A Fire tick and a Physical hit are
## different colours and different things, and one number cannot say both.
func test_two_damage_types_stay_two_numbers() -> void:
	var view = _view()
	var id: int = view.state.units[1].id
	_hit(view, id, 4, CG.DamageType.FIRE)
	_hit(view, id, 5, CG.DamageType.PHYSICAL)
	assert_eq(_floaters(view).size(), 2, "two damage types merged into one number")
	DisplayOptions.reset()
	view.free()

func test_two_pawns_keep_their_own_numbers() -> void:
	var view = _view()
	_hit(view, view.state.units[1].id, 4)
	_hit(view, view.state.units[2].id, 4)
	assert_eq(_floaters(view).size(), 2, "one pawn's number counted another pawn's damage")
	DisplayOptions.reset()
	view.free()

## The window is what keeps the number about what is happening now: past it the
## next hit is its own number again.
func test_a_hit_after_the_window_starts_a_new_number() -> void:
	var view = _view()
	var id: int = view.state.units[1].id
	_hit(view, id, 4)
	_age(view, BattleView.FLOATER_MERGE_WINDOW + 0.05)
	_hit(view, id, 5)
	assert_eq(_floaters(view).size(), 2, "the running total never expires")
	DisplayOptions.reset()
	view.free()

## Adding to a number puts it back at full opacity for its whole life again,
## or a total counting up would fade while it is still counting.
func test_adding_to_a_number_restarts_its_life() -> void:
	var view = _view()
	var id: int = view.state.units[1].id
	_hit(view, id, 4)
	_age(view, 0.5)
	var faded: float = _floaters(view)[0].modulate.a
	assert_true(faded < 1.0, "the fixture must actually have faded, it is at %f" % faded)
	_hit(view, id, 5)
	assert_eq(_floaters(view)[0].modulate.a, 1.0, "a counting total must not stay faded")
	DisplayOptions.reset()
	view.free()
