extends "res://Tests/TestCase.gd"


## Issue 830. The Warden's chain was named for a pull it did not have, and its
## one plan row was named "Axe up close, chain toss at range" while aiming
## every action at whoever stood nearest.

const _SEED := 8300

func _warden(id: int, pos: Vector2) -> CombatUnit:
	return CombatSim._build_enemy_unit(id, EnemyLibrary.get_enemy(&"the_warden"), &"the_warden", pos)

func _victim(id: int, pos: Vector2) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = CG.Team.PLAYER
	u.hp_max = 5000
	u.hp = 5000
	u.position = pos
	u.radius = 12.0
	u.move_speed = 0.0
	return u

## Three victims strung out in front of the Warden. Nobody but the Warden
## decides: the pawns stand still so the only movement in the fixture is the
## chain's.
func _arena() -> CombatState:
	var state := CombatState.new(_SEED)
	state.units.append(_victim(0, Vector2(60.0, 0.0)))
	state.units.append(_victim(1, Vector2(150.0, 0.0)))
	state.units.append(_victim(2, Vector2(250.0, 0.0)))
	state.units.append(_warden(3, Vector2.ZERO))
	return state

func _deps() -> SimDeps:
	var deps := SimDeps.new()
	deps.plan_decide = func(s: CombatState, u: CombatUnit) -> Intent:
		return PlanInterpreter.decide(s, u)
	deps.default_decide = func(_s: CombatState, u: CombatUnit) -> Intent:
		return Intent.idle() if u.team == CG.Team.PLAYER else DefaultBehavior.decide(_s, u)
	return deps

func _run(state: CombatState, deps: SimDeps, ticks: int) -> void:
	for _i in ticks:
		CombatSim.step(state, deps)

# ---------------------------------------------------------------------------
# the action itself
# ---------------------------------------------------------------------------

## The bug this issue exists to fix. Asserting the effect is merely present is
## what let a chain named "Chain Toss" ship for weeks hitting and never hauling,
## so this also asserts the distance is a real one.
func test_the_chain_carries_a_pull() -> void:
	var chain := ActionLibrary.get_action(&"warden_chain_toss")
	assert_ne(chain, null, "the Warden has a chain")
	var pull := chain.pull_effect()
	assert_ne(pull, null, "and it pulls, which is the whole of its name")
	assert_true(pull.distance > 0.0, "a pull of zero units is not a pull")

## Without a cooldown the chain row outcompetes the axe row on every free tick
## and the Warden never swings. This is the gate that makes two rows behave
## like two rows.
func test_the_chain_is_on_a_cooldown() -> void:
	assert_true(ActionLibrary.get_action(&"warden_chain_toss").cooldown_ticks > 0,
		"a chain with no cooldown is a permanent lock and the axe never fires")

# ---------------------------------------------------------------------------
# the plan
# ---------------------------------------------------------------------------

func test_the_warden_has_a_row_aimed_at_the_farthest_enemy() -> void:
	var rows := EnemyLibrary.get_enemy(&"the_warden").plans
	assert_true(rows.size() >= 2, "the chain and the axe are two different rows")
	var farthest_rows := 0
	for row in rows:
		for b in row.blocks:
			if b is TargetFarthestEnemyBlock:
				farthest_rows += 1
	assert_eq(farthest_rows, 1, "exactly one row reaches past the front line")

## Every row must be named for what it does. The row this replaced was called
## "Axe up close, chain toss at range" and did neither half.
func test_every_warden_row_names_the_action_it_fires() -> void:
	for row in EnemyLibrary.get_enemy(&"the_warden").plans:
		var used: Array[StringName] = []
		for b in row.blocks:
			if b is UseActionBlock and (b as UseActionBlock).action != null:
				used.append((b as UseActionBlock).action.id)
		assert_eq(used.size(), 1, "row '%s' fires exactly one named action" % row.id)

# ---------------------------------------------------------------------------
# and it pulls the FARTHEST one, in a stepped fight
# ---------------------------------------------------------------------------

## The load-bearing test. A chain that pulls the nearest pawn changes nothing
## about the fight; pulling the back line is the whole point.
func test_the_chain_hauls_the_farthest_pawn_and_leaves_the_nearest_where_it_stood() -> void:
	var state := _arena()
	var near := state.unit(0)
	var mid := state.unit(1)
	var far := state.unit(2)
	var near_at := near.position
	var mid_at := mid.position
	var far_at := far.position

	_run(state, _deps(), 60)

	## The pawns' own `move_speed` is 0, so the only ways any of them travels
	## are the chain and being shouldered aside by the Warden walking in. The
	## haul is an order of magnitude bigger than the shove, which is what
	## separates "the chain moved this one" from "the boss bumped it".
	var hauled := far_at.x - far.position.x
	assert_true(hauled > 100.0,
		"the farthest pawn was hauled %.1f units toward the Warden" % hauled)
	assert_true(absf(near.position.x - near_at.x) < 20.0,
		"the nearest pawn was shoved, not chained: %s -> %s" % [near_at, near.position])
	assert_eq(mid.position, mid_at, "and the one in the middle did not move at all")

## The pull is authorised by the stun, per `_tick_pull`. A haul that does not
## stun is one the victim walks straight back out of.
func test_the_chained_pawn_is_stunned_for_the_haul() -> void:
	var state := _arena()
	var far := state.unit(2)
	var stunned_at := -1
	for i in 60:
		CombatSim.step(state, _deps())
		if far.has_status(CG.Status.STUN) and stunned_at == -1:
			stunned_at = i
	assert_true(stunned_at >= 0, "the farthest pawn was stunned by the chain")
	assert_false(state.unit(0).has_status(CG.Status.STUN), "and the nearest was not")

## The event stream says so too, so a player watching the log sees the chain
## land on the back rank rather than on whoever they were already watching.
func test_the_chain_event_names_the_farthest_pawn_as_its_target() -> void:
	var state := _arena()
	_run(state, _deps(), 60)
	var landed := 0
	for e in state.events:
		if e.action_id != &"warden_chain_toss":
			continue
		if e.kind != CG.EventKind.DAMAGE:
			continue
		landed += 1
		assert_eq(e.target_id, 2, "the chain landed on the farthest pawn")
	assert_true(landed > 0, "the chain landed at all")

## And the axe still happens. Two rows that both fire is the difference between
## a second row and a row that eats the first one's ticks.
func test_the_axe_still_swings_once_the_chain_is_on_cooldown() -> void:
	var state := _arena()
	_run(state, _deps(), 400)
	var axed := false
	for e in state.events:
		if e.action_id == &"warden_axe" and e.kind == CG.EventKind.DAMAGE:
			axed = true
	assert_true(axed, "the Warden closes and swings between chains")
