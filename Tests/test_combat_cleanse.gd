extends "res://Tests/TestCase.gd"

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")
const CombatEvent := preload("res://Scripts/Core/CombatEvent.gd")
const Intent := preload("res://Scripts/Core/Intent.gd")
const ActionDef := preload("res://Scripts/Core/ActionDef.gd")
const SimDeps := preload("res://Scripts/Combat/SimDeps.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")

## Issue 87, the simulation half: `ActionDef.cleanses_harmful` strips every
## harmful status from an action's targets and emits one STATUS_EXPIRED per
## removal. The field and its doc comment were on `ActionDef` for weeks with
## nothing under either -- `grep cleanses_harmful Scripts/` returned exactly
## the declaration -- which is why the reachability suite (PR #80) counted it
## as a mechanism that no fight could reach.
##
## Every test here drives `CombatSim.step()` with the action injected through
## `SimDeps.action_lookup`, the same seam `test_combat_pull_and_slow.gd` uses:
## the cleanse has to survive the real commit/wind-up/fire path rather than a
## direct call to the effect function, because "the effect works when called"
## was never the thing in doubt.
##
## The content half -- a Geysermancer action that sets the field, and a plan
## that picks it -- is finch's, in `Scripts/Content/**`.

func _unit(id: int, team: CG.Team, hp: int, pos: Vector2, actions: Array[StringName]) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.hp_max = hp
	u.hp = hp
	u.position = pos
	u.move_speed = 8.0
	u.actions = actions
	return u

## A fight with only one team ends after tick one and every later step()
## no-ops, which looks exactly like a frozen simulation and is not one. Same
## device, and same reason, as test_combat_statuses.gd.
func _dummy_enemy(id: int) -> CombatUnit:
	return _unit(id, CG.Team.ENEMY, 10, Vector2(100000, 100000), [])

## wind_up_ticks == 2 per this suite's convention: the action fires on exactly
## the Nth step() for a wind-up of N, so every call site below steps twice.
func _cleanse_action(id: StringName, cleanses: bool) -> ActionDef:
	var a := ActionDef.new()
	a.id = id
	a.wind_up_ticks = 2
	a.recover_ticks = 1
	a.range_units = 999.0
	a.heals = true
	a.cleanses_harmful = cleanses
	a.damage_type = CG.DamageType.PHYSICAL
	return a

func _deps_with_action(action: ActionDef) -> SimDeps:
	var actions_by_id := {action.id: action}
	var deps := SimDeps.new()
	deps.action_lookup = func(id: StringName): return actions_by_id.get(id)
	deps.attack_power = func(_u: CombatUnit, _a: ActionDef, _r = null) -> float: return 0.0
	deps.damage_reduction = func(_u: CombatUnit) -> float: return 0.0
	deps.status_damage_per_tick = func(_u: CombatUnit, _s: CG.Status) -> float: return 0.0
	deps.wind_up_ticks = func(_u: CombatUnit, a: ActionDef) -> int: return a.wind_up_ticks
	deps.recover_ticks = func(_u: CombatUnit, a: ActionDef) -> int: return a.recover_ticks
	deps.default_decide = func(_s: CombatState, _u: CombatUnit) -> Intent: return Intent.idle()
	return deps

## Far enough out that nothing expires on its own inside a two-tick test. An
## expiry and a cleanse both erase the status, so a short duration would let
## `_tick_statuses` pass a test the cleanse never ran in.
const _LONG := 9000

func _cleanse_events(state: CombatState) -> Array:
	var out: Array = []
	for e in state.events:
		if e.kind == CG.EventKind.STATUS_EXPIRED:
			out.append(e)
	return out

# ---------------------------------------------------------------------------
# the mechanism: harmful statuses come off, and say so
# ---------------------------------------------------------------------------

func test_a_cleanse_strips_every_harmful_status_from_its_target() -> void:
	var cleanse := _cleanse_action(&"cleanse", true)
	var deps := _deps_with_action(cleanse)

	var state := CombatState.new(870)
	var caster := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [cleanse.id])
	var ally := _unit(1, CG.Team.PLAYER, 30, Vector2(40, 0), [])
	ally.statuses[CG.Status.POISON] = _LONG
	ally.statuses[CG.Status.BURN] = _LONG
	ally.statuses[CG.Status.SLOWED] = _LONG
	state.units.append(caster)
	state.units.append(ally)
	state.units.append(_dummy_enemy(2))

	caster.intent = Intent.use_action(cleanse.id, ally.id)
	CombatSim.step(state, deps) # commits
	CombatSim.step(state, deps) # fires and cleanses

	assert_false(ally.has_status(CG.Status.POISON), "POISON must be gone")
	assert_false(ally.has_status(CG.Status.BURN), "BURN must be gone")
	assert_false(ally.has_status(CG.Status.SLOWED), "SLOWED must be gone")
	assert_true(ally.statuses.is_empty(), "nothing harmful may survive a cleanse")

func test_a_cleanse_emits_one_status_expired_per_status_it_removes() -> void:
	# Without an event the log and the status badges cannot follow, and a
	# status vanishing off a unit with nothing said about it is the exact
	# "no event, no visible cause" failure CombatEvent exists to prevent.
	var cleanse := _cleanse_action(&"cleanse", true)
	var deps := _deps_with_action(cleanse)

	var state := CombatState.new(871)
	var caster := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [cleanse.id])
	var ally := _unit(1, CG.Team.PLAYER, 30, Vector2(40, 0), [])
	ally.statuses[CG.Status.POISON] = _LONG
	ally.statuses[CG.Status.MARKED] = _LONG
	state.units.append(caster)
	state.units.append(ally)
	state.units.append(_dummy_enemy(2))

	caster.intent = Intent.use_action(cleanse.id, ally.id)
	CombatSim.step(state, deps)
	CombatSim.step(state, deps)

	var expired := _cleanse_events(state)
	assert_eq(expired.size(), 2, "one STATUS_EXPIRED per status removed")
	var seen := {}
	for e in expired:
		seen[e.status] = true
		assert_eq(e.target_id, ally.id, "the expiry names the unit it came off")
		assert_eq(e.source_id, caster.id, "a cleansed status names the caster, unlike a natural expiry")
		assert_eq(e.action_id, cleanse.id, "and the action that did it")
	assert_true(seen.has(CG.Status.POISON) and seen.has(CG.Status.MARKED),
		"both removed statuses must be named by their own event")

func test_a_cleanse_removes_statuses_in_a_deterministic_order() -> void:
	# Dictionary key order is insertion order, so the same seed would
	# otherwise emit removals in an order set by which enemy afflicted the
	# unit first. Two states, identical except for the order the statuses
	# were applied in, must produce the same event sequence.
	var cleanse := _cleanse_action(&"cleanse", true)

	var forwards := _order_of_removals(cleanse, [CG.Status.BURN, CG.Status.POISON, CG.Status.STUN])
	var backwards := _order_of_removals(cleanse, [CG.Status.STUN, CG.Status.POISON, CG.Status.BURN])

	assert_eq(forwards.size(), 3, "all three come off")
	assert_eq(forwards, backwards, "removal order must not depend on affliction order")

func _order_of_removals(cleanse: ActionDef, statuses: Array) -> Array:
	var deps := _deps_with_action(cleanse)
	var state := CombatState.new(872)
	var caster := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [cleanse.id])
	var ally := _unit(1, CG.Team.PLAYER, 30, Vector2(40, 0), [])
	for s in statuses:
		ally.statuses[s] = _LONG
	state.units.append(caster)
	state.units.append(ally)
	state.units.append(_dummy_enemy(2))

	caster.intent = Intent.use_action(cleanse.id, ally.id)
	CombatSim.step(state, deps)
	CombatSim.step(state, deps)

	var out: Array = []
	for e in _cleanse_events(state):
		out.append(e.status)
	return out

func test_a_cleanse_actually_undoes_what_the_status_was_doing() -> void:
	# The status leaving the dictionary is not the claim worth making. SLOWED
	# is read every tick out of `_effective_move_speed`, so a unit that was
	# crawling has to move at full speed again on the ticks after the cleanse.
	var cleanse := _cleanse_action(&"cleanse", true)
	var deps := _deps_with_action(cleanse)
	deps.slowed_speed_scale = func(_u: CombatUnit) -> float: return 0.0

	var state := CombatState.new(873)
	var caster := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [cleanse.id])
	var ally := _unit(1, CG.Team.PLAYER, 30, Vector2(40, 0), [])
	ally.statuses[CG.Status.SLOWED] = _LONG
	state.units.append(caster)
	state.units.append(ally)
	state.units.append(_dummy_enemy(2))

	ally.intent = Intent.move_to(Vector2(400, 0))
	CombatSim.step(state, deps)
	assert_almost_eq(ally.position.x, 40.0, 0.01, "SLOWED at scale 0 pins the ally in place")

	caster.intent = Intent.use_action(cleanse.id, ally.id)
	CombatSim.step(state, deps) # commits
	ally.intent = Intent.move_to(Vector2(400, 0))
	CombatSim.step(state, deps) # cleanse fires this tick
	ally.intent = Intent.move_to(Vector2(400, 0))
	var before := ally.position.x
	CombatSim.step(state, deps)

	assert_true(ally.position.x > before + 0.01,
		"a cleansed unit moves again -- SLOWED must be genuinely gone, not just absent from a badge")

# ---------------------------------------------------------------------------
# the negative half: what a cleanse must not touch
# ---------------------------------------------------------------------------

func test_a_cleanse_leaves_beneficial_statuses_alone() -> void:
	# CG.is_harmful is the single source for the split. A cleanse that took
	# SHIELD or HASTE off the ally it targeted would be hostile to it, which
	# is that function's own stated reason for existing.
	var cleanse := _cleanse_action(&"cleanse", true)
	var deps := _deps_with_action(cleanse)

	var state := CombatState.new(874)
	var caster := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [cleanse.id])
	var ally := _unit(1, CG.Team.PLAYER, 30, Vector2(40, 0), [])
	ally.statuses[CG.Status.SHIELD] = _LONG
	ally.statuses[CG.Status.HASTE] = _LONG
	ally.statuses[CG.Status.POISON] = _LONG
	state.units.append(caster)
	state.units.append(ally)
	state.units.append(_dummy_enemy(2))

	caster.intent = Intent.use_action(cleanse.id, ally.id)
	CombatSim.step(state, deps)
	CombatSim.step(state, deps)

	assert_true(ally.has_status(CG.Status.SHIELD), "SHIELD is not harmful and must survive")
	assert_true(ally.has_status(CG.Status.HASTE), "HASTE is not harmful and must survive")
	assert_false(ally.has_status(CG.Status.POISON), "the harmful one still comes off")
	assert_eq(_cleanse_events(state).size(), 1, "no event for a status that was never removed")

func test_an_action_that_does_not_cleanse_removes_nothing() -> void:
	# Every action in the game today has cleanses_harmful == false, and this
	# is the half that says they all still behave exactly as they did. A
	# mechanism that fires on actions that never opted in is a regression
	# dressed as a feature.
	var plain := _cleanse_action(&"plain", false)
	var deps := _deps_with_action(plain)

	var state := CombatState.new(875)
	var caster := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [plain.id])
	var ally := _unit(1, CG.Team.PLAYER, 30, Vector2(40, 0), [])
	ally.statuses[CG.Status.POISON] = _LONG
	ally.statuses[CG.Status.BURN] = _LONG
	state.units.append(caster)
	state.units.append(ally)
	state.units.append(_dummy_enemy(2))

	caster.intent = Intent.use_action(plain.id, ally.id)
	CombatSim.step(state, deps)
	CombatSim.step(state, deps)

	assert_true(ally.has_status(CG.Status.POISON), "POISON must survive an action that does not cleanse")
	assert_true(ally.has_status(CG.Status.BURN), "BURN must survive it too")
	assert_eq(_cleanse_events(state).size(), 0, "and nothing may be reported as expiring")

func test_a_cleanse_on_an_unafflicted_ally_is_silent() -> void:
	# The detector-that-always-fires failure, in event form: a cleanse that
	# emitted an expiry per known harmful status regardless of what the unit
	# was carrying would fill the log with statuses nobody ever had.
	var cleanse := _cleanse_action(&"cleanse", true)
	var deps := _deps_with_action(cleanse)

	var state := CombatState.new(876)
	var caster := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [cleanse.id])
	var ally := _unit(1, CG.Team.PLAYER, 30, Vector2(40, 0), [])
	state.units.append(caster)
	state.units.append(ally)
	state.units.append(_dummy_enemy(2))

	caster.intent = Intent.use_action(cleanse.id, ally.id)
	CombatSim.step(state, deps)
	CombatSim.step(state, deps)

	assert_true(ally.statuses.is_empty(), "nothing was there to remove")
	assert_eq(_cleanse_events(state).size(), 0, "a cleanse on a clean unit reports nothing")

func test_a_cleanse_does_not_fire_on_a_target_its_own_damage_killed() -> void:
	# `_apply_pull` is guarded on `target.alive` after this same effect's
	# death resolution for exactly this reason. A cleanse is placed beside it
	# and must behave the same: no scrubbing a corpse.
	var cleanse := _cleanse_action(&"cleanse", true)
	cleanse.heals = false
	var deps := _deps_with_action(cleanse)
	deps.attack_power = func(_u: CombatUnit, _a: ActionDef, _r = null) -> float: return 999.0

	var state := CombatState.new(877)
	var caster := _unit(0, CG.Team.PLAYER, 20, Vector2.ZERO, [cleanse.id])
	var victim := _unit(1, CG.Team.ENEMY, 10, Vector2(40, 0), [])
	victim.statuses[CG.Status.POISON] = _LONG
	state.units.append(caster)
	state.units.append(victim)

	caster.intent = Intent.use_action(cleanse.id, victim.id)
	CombatSim.step(state, deps)
	CombatSim.step(state, deps)

	assert_false(victim.alive, "the damage killed it")
	assert_true(victim.has_status(CG.Status.POISON), "a dead target is not cleansed")
	assert_eq(_cleanse_events(state).size(), 0, "and nothing is reported about it")
