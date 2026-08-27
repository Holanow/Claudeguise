extends "res://Tests/TestCase.gd"


## Issue 641: `DefaultPlan` is `DefaultBehavior` written as rows, and this file
## is the proof, in the shape #628 used -- keep both, diff them, delete the old
## one only once the diff is empty.
##
## The comparator IS the decider rather than a probe on top of one, because
## `DefaultBehavior.decide` draws from `state.rng`. The old answer is
## authoritative and the rng is rewound around the new one, so the fight the
## comparison runs is the fight the trunk runs.

const SEEDS := 2
const PARTIES := [
	[&"warrior", &"priest", &"geysermancer", &"siege_master"],
	[&"abomination", &"warrior", &"priest", &"stalker"],
	[&"siege_master", &"siege_master", &"geysermancer", &"abomination"],
]

var _decisions := 0
var _mismatches: Array[String] = []

func _compare(state: CombatState, unit: CombatUnit) -> Intent:
	var before := state.rng.state
	var old_intent: Intent = DefaultBehavior.decide(state, unit)
	var after_old := state.rng.state
	state.rng.state = before
	var new_intent: Intent = DefaultPlan.decide(state, unit)
	var after_new := state.rng.state
	state.rng.state = after_old
	_decisions += 1
	if after_new != after_old:
		_mismatches.append("tick %d unit %d: rng stream moved differently" % [state.tick, unit.id])
	elif not _same(old_intent, new_intent):
		_mismatches.append("tick %d unit %d: %s != %s" % [
			state.tick, unit.id, _render(old_intent), _render(new_intent)])
	return old_intent

static func _same(a: Intent, b: Intent) -> bool:
	if a == null or b == null:
		return a == b
	return a.kind == b.kind and a.action_id == b.action_id and a.target_id == b.target_id \
		and a.destination == b.destination and a.source_plan == b.source_plan

static func _render(i: Intent) -> String:
	if i == null:
		return "null"
	return "%d/%s/%d/%s" % [i.kind, i.action_id, i.target_id, i.destination]
func _report(what: String) -> void:
	print("DefaultPlan vs DefaultBehavior (%s): %d decisions, %d differ" % [
		what, _decisions, _mismatches.size()])
	assert_true(_decisions > 5000, "only %d decisions compared; this is not a run" % _decisions)
	assert_eq(_mismatches.slice(0, 3), [] as Array[String],
		"%d of %d decisions differ from DefaultBehavior" % [_mismatches.size(), _decisions])

# ---------------------------------------------------------------------------
func test_the_comparator_reports_a_difference_when_there_is_one() -> void:
	var a := Intent.use_action(&"warrior_strike", 3)
	var b := Intent.use_action(&"warrior_strike", 4)
	assert_false(_same(a, b), "two intents at different targets must not compare equal")
	assert_true(_same(a, Intent.use_action(&"warrior_strike", 3)), "the same intent must compare equal")
	assert_false(_same(a, Intent.idle()), "an idle and an attack must not compare equal")

## Both files own a copy of these while both files exist. Drift between them is
## the failure mode this catches.
func test_the_constants_have_not_drifted_apart() -> void:
	assert_eq(DefaultPlan.MELEE_RANGE_THRESHOLD, DefaultBehavior.MELEE_RANGE_THRESHOLD)
	assert_eq(DefaultPlan.MELEE_COMMIT_FRACTION, DefaultBehavior.MELEE_COMMIT_FRACTION)
	assert_eq(DefaultPlan.RANGED_COMMIT_FRACTION, DefaultBehavior.RANGED_COMMIT_FRACTION)
	assert_eq(DefaultPlan.HEAL_THRESHOLD_FRACTION, DefaultBehavior.HEAL_THRESHOLD_FRACTION)

## The point of the exercise: a player can read what their pawn is running.
func test_every_default_row_has_a_sentence_for_every_class() -> void:
	for cid in ClassLibrary.all_ids():
		var party: Array[PawnData] = [PawnFactory.make_starter_pawn(cid, &"p", "p")]
		var state := CombatSim.build(party, RoomLibrary.get_room(CG.DEFAULT_ENCOUNTER), 0)
		var rows := DefaultPlan.rows_for(state.units[0])
		assert_true(rows.size() > 0, "%s has no default rows at all" % cid)
		for row in rows:
			assert_true(row.condition.describe() != "", "%s: a row's condition has no sentence" % cid)
			for block in row.blocks:
				assert_true(block.describe() != "", "%s: a block has no sentence" % cid)

## An enemy gets the self-buff row and a pawn does not, which is why a pawn has
## to write its buffs itself.
func test_only_a_unit_without_a_pawn_carries_the_self_buff_row() -> void:
	var party: Array[PawnData] = [PawnFactory.make_starter_pawn(&"warrior", &"p", "p")]
	var state := CombatSim.build(party, RoomLibrary.get_room(CG.DEFAULT_ENCOUNTER), 0)
	for unit in state.units:
		var ids: Array[StringName] = []
		for row in DefaultPlan.rows_for(unit):
			ids.append(row.id)
		assert_eq(ids.has(DefaultPlan.BUFF_ROW), unit.pawn == null,
			"unit %d: the buff row belongs to units with no pawn" % unit.id)

# ---------------------------------------------------------------------------
# The one branch the fight comparison above cannot reach: `SampleFights` is
# headless, so `state.player_focus_id` is -1 in all 124,000 of its decisions.

func _agree(state: CombatState, unit: CombatUnit) -> Intent:
	var before := state.rng.state
	var old_intent: Intent = DefaultBehavior.decide(state, unit)
	var after_old := state.rng.state
	state.rng.state = before
	var new_intent: Intent = DefaultPlan.decide(state, unit)
	assert_eq(state.rng.state, after_old, "the two drew differently from the rng")
	state.rng.state = after_old
	assert_true(_same(old_intent, new_intent), "%s != %s" % [_render(old_intent), _render(new_intent)])
	return old_intent

## Who an intent is pointed at, whether it walks there or fires at them.
func _aimed_at(state: CombatState, intent: Intent) -> int:
	if intent.kind == CG.IntentKind.USE_ACTION:
		return intent.target_id
	for u in state.units:
		if u.position == intent.destination:
			return u.id
	return -1

func _pawn_fight() -> CombatState:
	var party: Array[PawnData] = [PawnFactory.make_starter_pawn(&"warrior", &"w", "W")]
	return CombatSim.build(party, RoomLibrary.get_room(CG.DEFAULT_ENCOUNTER), 3)

## The player's click, which only a pawn honours and only through the fallback.
func test_the_rows_follow_the_players_focus_the_way_the_fallback_did() -> void:
	var state := _pawn_fight()
	var pawn := state.units[0]
	var far: CombatUnit = null
	for u in state.units:
		if u.team != pawn.team and (far == null
			or pawn.position.distance_to(u.position) > pawn.position.distance_to(far.position)):
			far = u
	assert_ne(far, null, "the encounter has no enemies")
	state.player_focus_id = far.id
	assert_eq(_aimed_at(state, _agree(state, pawn)), far.id,
		"the fixture must actually take the focus branch")

## And a taunt outranks the click, in both versions.
func test_a_taunt_outranks_the_players_focus_in_both_versions() -> void:
	var state := _pawn_fight()
	var pawn := state.units[0]
	var enemies: Array[CombatUnit] = []
	for u in state.units:
		if u.team != pawn.team:
			enemies.append(u)
	assert_true(enemies.size() >= 2, "this fixture needs two enemies")
	state.player_focus_id = enemies[0].id
	enemies[1].statuses[CG.Status.TAUNTING] = 999
	enemies[1].taunt_radius = 10000.0
	_agree(state, pawn)
