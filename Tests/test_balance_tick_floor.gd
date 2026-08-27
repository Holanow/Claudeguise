extends "res://Tests/TestCase.gd"


## Issue 592: nothing that scales a tick count may reach zero. The player asked
## for a floor when the caps went to 0.9; all three paths already had one, so
## this file is the proof rather than the fix, and it is what makes the floor
## something sable's animations can rely on instead of defending against.

const ABSURD_AGI := 1000

func _pawn(class_id: StringName, agi: int) -> PawnData:
	var pawn := PawnFactory.make_starter_pawn(class_id, &"p", String(class_id))
	pawn.attribute_bonus[CG.Attribute.AGI] = agi - pawn.pawn_class.attribute(CG.Attribute.AGI)
	return pawn

# ---------------------------------------------------------------------------
# the positive half: an absurd input floors at 1, never at 0
# ---------------------------------------------------------------------------

## Every action in the registry, at an AGI no roller can produce, so the check
## cannot pass by happening to miss the one short action that would break.
func test_no_action_can_be_scaled_below_one_tick_by_agi() -> void:
	var pawn := _pawn(&"warrior", ABSURD_AGI)
	var checked := 0
	for id in Registry.all_action_ids():
		var a := ActionLibrary.get_action(id)
		if a == null:
			continue
		for label in ["wind-up", "recover"]:
			var base: int = a.wind_up_ticks if label == "wind-up" else a.recover_ticks
			if base <= 0:
				continue
			checked += 1
			var scaled := Balance.scale_action_ticks(base, pawn)
			assert_true(scaled >= 1,
				"%s's %s is %d ticks and AGI %d scaled it to %d" % [id, label, base, ABSURD_AGI, scaled])
	assert_true(checked > 0, "no action had a positive tick count, so this measured nothing")

## The floor is LOAD-BEARING at the shipped cap, and this is the assertion that
## says so rather than assuming it. At `MAX_AGI_TICK_SCALE` 0.5 nothing in the
## registry could reach zero and every check above would pass with no floor at
## all; at 0.9 the short actions do. If #592's cap is reverted this goes red,
## which is the correct answer -- it means the floor stopped being needed.
func test_the_floor_actually_fires_at_the_shipped_cap() -> void:
	var pawn := _pawn(&"warrior", ABSURD_AGI)
	var scale: float = Balance.MAX_AGI_TICK_SCALE
	var floored := []
	for id in Registry.all_action_ids():
		var a := ActionLibrary.get_action(id)
		if a == null:
			continue
		for base in [a.wind_up_ticks, a.recover_ticks]:
			if base <= 0:
				continue
			if int(round(float(base) * (1.0 - scale))) == 0:
				floored.append(id)
				assert_eq(Balance.scale_action_ticks(base, pawn), 1,
					"%s's %d ticks would compute to 0 at scale %f" % [id, base, scale])
	assert_true(floored.size() > 0,
		"no action reaches zero at MAX_AGI_TICK_SCALE %f, so the floor is inert and every check in this file passes without it" % scale)

## The enemy half of the same seam, and it has its own clamp and its own floor.
func test_no_enemy_action_can_be_scaled_below_one_tick() -> void:
	assert_eq(Balance.scale_enemy_action_ticks(1, 1000.0), 1,
		"a one-tick enemy action at an absurd action speed")
	assert_eq(Balance.scale_enemy_action_ticks(3, 1000.0), 2,
		"the enemy clamp is MIN_ENEMY_TICK_SCALE, so 3 ticks halves rather than vanishing")

## HASTE multiplies on top of AGI, and `CombatSim._apply_haste` floors it too.
func test_haste_cannot_take_an_action_to_zero_ticks() -> void:
	var unit := CombatUnit.new()
	unit.id = 1
	unit.statuses[CG.Status.HASTE] = 100
	var deps := SimDeps.new()
	deps.haste_tick_scale = func(_u): return 0.001
	assert_eq(CombatSim._apply_haste(unit, deps, 1), 1, "one tick, hasted into nothing")
	assert_eq(CombatSim._apply_haste(unit, deps, 45), 1, "a 45-tick wind-up, hasted into nothing")

# ---------------------------------------------------------------------------
# the negative half: the floor is not quietly rounding ordinary pawns up
# ---------------------------------------------------------------------------

## Without this the floor could be `return 1` and every test above would pass.
func test_an_ordinary_pawn_is_not_touched_by_the_floor() -> void:
	var moved := 0
	for cid in Registry.all_class_ids():
		var pawn := PawnFactory.make_starter_pawn(cid, &"p", String(cid))
		var scale: float = clampf(
			Balance.attribute(pawn, CG.Attribute.AGI) * Balance.AGI_TICK_SCALE_PER_POINT,
			0.0, Balance.MAX_AGI_TICK_SCALE)
		for base in [3, 8, 20, 45, 90]:
			var expected := int(round(float(base) * (1.0 - scale)))
			assert_eq(Balance.scale_action_ticks(base, pawn), expected,
				"%s scaled a %d-tick action to something other than its own arithmetic" % [cid, base])
			if expected > 1:
				moved += 1
	assert_true(moved > 0,
		"every starter pawn scaled every action to one tick, so the assertions above prove nothing")

## A zero or negative base is passed straight through rather than floored to 1:
## an action with no wind-up must not grow one.
func test_a_zero_tick_action_stays_zero() -> void:
	var pawn := PawnFactory.make_starter_pawn(&"warrior", &"p", "w")
	assert_eq(Balance.scale_action_ticks(0, pawn), 0, "a zero-tick action must not be given a tick")
	assert_eq(Balance.scale_enemy_action_ticks(0, 2.0), 0, "the enemy path, same rule")
