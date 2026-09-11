extends "res://Tests/TestCase.gd"


## Issue 919: the chest a cleared room leaves behind. The same gesture #805's
## doors use, in the same place, so the floor has one interaction vocabulary.
## Every test here resolves the fight by hand; none runs one.

const BattleScene := preload("res://Scenes/Battle.tscn")
const FLOOR_SEED := 3

func _party() -> Array[PawnData]:
	var out: Array[PawnData] = []
	for cid in ClassLibrary.all_ids():
		out.append(PawnFactory.make_preset_pawn(cid, cid, String(cid)))
	return out

func _floor() -> Node:
	var battle := in_tree(BattleScene.instantiate())
	var cfg := RunConfig.new()
	cfg.seed = FLOOR_SEED
	cfg.party = _party()
	battle.begin_floor(cfg, FloorGenerator.generate(FLOOR_SEED))
	return battle

func _resolve(battle: Node) -> void:
	battle.state.outcome = CombatState.Outcome.PLAYER_WIN
	battle._handle_fight_end()

# ---------------------------------------------------------------------------

func test_no_chest_while_the_fight_is_unresolved() -> void:
	var battle := _floor()
	assert_false(battle.chest_open(), "a room that is still a fight has no chest")
	assert_false(battle.chest_at(Vector2.ZERO), "no click lands on a chest mid-fight")

func test_a_cleared_room_leaves_a_chest_in_the_middle_of_it() -> void:
	var battle := _floor()
	_resolve(battle)
	assert_true(battle.chest_open(), "a cleared room leaves nothing to open")
	assert_true(battle.chest_at(Vector2.ZERO), "the chest is not where a click would land")
	assert_false(battle.chest_at(FloorDoors.rect_for(Vector2i(0, -1)).get_center()),
		"the chest must not sit on top of a door")

## The gesture itself, through the control a player uses rather than through
## the function under it.
func test_clicking_the_chest_hands_the_party_its_loot() -> void:
	var battle := _floor()
	_resolve(battle)
	var run: FloorRun = battle._floor_run
	assert_eq(run.loot.size(), 0, "the chest is not the party's until it is clicked")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	battle._on_arena_button(press, Vector2.ZERO)
	assert_true(run.loot.size() >= 1, "clicking the chest handed over nothing")
	assert_false(battle.chest_open(), "the chest is clickable once")

## The manager's second sub-decision: unclicked loot is lost when the party
## leaves. A chest that follows them is a bag, and there is no inventory.
func test_walking_out_leaves_the_chest_behind() -> void:
	var battle := _floor()
	_resolve(battle)
	var run: FloorRun = battle._floor_run
	var exits: Array = battle.open_exits()
	assert_true(exits.size() > 0, "the entrance must have somewhere to go")
	battle.take_door(int(exits[0]["room_id"]))
	assert_eq(run.loot.size(), 0, "the chest followed the party out of the room")
	assert_false(battle.chest_open())

## The third: a cleared room re-entered shows no chest, the same guard #805 put
## on the arrival heal.
func test_a_re_entered_room_has_no_second_chest() -> void:
	var battle := _floor()
	_resolve(battle)
	var first: int = battle._floor_walk.current_id
	var exits: Array = battle.open_exits()
	battle.take_door(int(exits[0]["room_id"]))
	_resolve(battle)
	var back: Array = battle.open_exits()
	var home := -1
	for e in back:
		if int(e["room_id"]) == first:
			home = first
	assert_eq(home, first, "the room walked out of must be walkable back into")
	battle.open_chest()
	battle.take_door(first)
	_resolve(battle)
	assert_false(battle.chest_open(), "a cleared room paid out a second chest")

## And the pieces nobody could put on are still reachable: they land in the
## run's bag, which the equip screen offers beside the registry.
func test_what_nobody_can_wear_reaches_the_equip_screen() -> void:
	var party := _party()
	var run := FloorRun.new()
	var swords: Array[EquipmentDef] = [ItemLibrary.get_equipment(&"sword")]
	FloorRun.take_chest(run, party, swords)
	assert_eq(run.bag.size(), 1, "every main hand is full, so the sword has nowhere to go")
	var panel := EquipPanel.create()
	panel._ready()
	panel.bag = run.bag
	var warrior: PawnData = null
	for p in party:
		if p.pawn_class.id == &"warrior":
			warrior = p
	var offered := panel.offered_items(warrior, EquipmentDef.Slot.OFF_HAND)
	var count := 0
	for item in offered:
		if item == swords[0]:
			count += 1
	assert_eq(count, 1, "the bag's sword is not a row on the equip screen")
	panel.free()

## Issue 935: the boss room has no door to walk out of, so the floor waits on
## its chest instead of ending over the top of it. `boss_id` is moved onto the
## room being fought, as a fixture.
func _boss_here(battle: Node) -> void:
	battle._floor_walk.plan.boss_id = battle._floor_walk.current_id

func test_the_cleared_boss_room_offers_its_chest_before_the_floor_ends() -> void:
	var battle := _floor()
	var ended := [0]
	battle.floor_ended.connect(func(_victory: bool): ended[0] += 1)
	_boss_here(battle)
	_resolve(battle)
	assert_true(battle.chest_open(), "the cleared boss room drew no chest")
	assert_true(battle.chest_at(Vector2.ZERO), "no click lands on the boss chest")
	assert_false(battle.doors_open(), "the boss room must not open a door back out")
	assert_eq(ended[0], 0, "the floor ended over the top of the chest")
	assert_false(battle._end_banner.visible, "the end card stands on the held chest")

## The held room is re-entered every frame, the same way #805's open doors are.
func test_the_held_boss_room_pays_out_once_however_long_it_is_held() -> void:
	var battle := _floor()
	var ended := [0]
	battle.floor_ended.connect(func(_victory: bool): ended[0] += 1)
	_boss_here(battle)
	_resolve(battle)
	for i in 5:
		battle._handle_fight_end()
	assert_eq(battle._floor_run.loot.size(), 0, "the held chest paid out by itself")
	assert_eq(ended[0], 0, "holding the floor ended it")
	assert_true(battle.chest_open(), "the held chest closed on its own")

func test_clicking_the_boss_chest_hands_over_the_loot_and_ends_the_floor() -> void:
	var battle := _floor()
	var ended := [0]
	battle.floor_ended.connect(func(_victory: bool): ended[0] += 1)
	_boss_here(battle)
	_resolve(battle)
	var run: FloorRun = battle._floor_run
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	battle._on_arena_button(press, Vector2.ZERO)
	assert_true(run.loot.size() >= 1, "clicking the boss chest handed over nothing")
	assert_eq(ended[0], 1, "the floor did not end when the chest was clicked")
	assert_false(battle.chest_open(), "the boss chest is clickable once")
