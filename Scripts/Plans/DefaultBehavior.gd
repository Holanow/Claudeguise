extends RefCounted
class_name DefaultBehavior


## What a unit does when no plan fires. Every unit has this, including enemies,
## which have no plans at all in this slice.

## An action with more range than this is treated as ranged: kept at, rather
## than closed to melee distance. Every melee action in this slice sits at
## 40-45 world units; every ranged one sits at 200+.
const MELEE_RANGE_THRESHOLD := 60.0

## Range is checked when a hit lands, not when it commits (CombatSim's own
## rule), so firing right at the edge of range is a guaranteed whiff against
## anything that flees during the wind-up: it walks the small remaining
## distance to safety for free while the attacker stands there committed.
const MELEE_COMMIT_FRACTION := 0.5
const RANGED_COMMIT_FRACTION := 0.85

## An ally at or below this fraction of max hp counts as needing a heal.
const HEAL_THRESHOLD_FRACTION := 0.5

static func decide(state: CombatState, unit: CombatUnit) -> Intent:
	var enemy_team := CG.Team.ENEMY if unit.team == CG.Team.PLAYER else CG.Team.PLAYER
	var enemies := state.living(enemy_team)
	if enemies.is_empty():
		return Intent.idle()

	var candidates := _actions_that_can_fire_now(state, unit)
	## Issue 166: widened from `candidates.is_empty()`. The Channel is free, so a
	## dry caster can now pay for something that neither attacks nor heals, and
	## the old test read that as "I have options" and stood still.
	if _first_heal(candidates) == null and _attack_candidates(candidates).is_empty():
		candidates = _all_actions(unit)
	if candidates.is_empty():
		return Intent.idle()

	if _all_attacks_require_a_mark(candidates):
		enemies = _only_marked(enemies)
		if enemies.is_empty():
			# Hold fire. Not `move_to`: the engine cannot move (move_speed 0.0)
			return Intent.idle()

	var heal_action := _first_heal(candidates)
	if heal_action != null:
		var neediest := _lowest_hp_fraction(_heal_candidates(state, unit, heal_action))
		if neediest != null and neediest.hp_fraction() <= HEAL_THRESHOLD_FRACTION:
			var dist_to_ally := unit.position.distance_to(neediest.position)
			if dist_to_ally <= heal_action.range_units:
				return Intent.use_action(heal_action.id, neediest.id)
			return Intent.move_to(neediest.position)

	if unit.pawn == null:
		var self_action := _self_targeted_to_cast(state, unit, enemies)
		if self_action != null:
			return Intent.use_action(self_action.id, unit.id)

	var target := _choose_target(state, unit, enemies)
	if target == null:
		return Intent.idle()

	var attack_action := _choose_attack_action(candidates, unit, target)
	if attack_action == null:
		return Intent.idle()

	var dist := unit.position.distance_to(target.position)

	if unit.move_speed <= 0.0:
		if dist > attack_action.range_units:
			return Intent.idle()
		if attack_action.requires_line_of_sight and state.grid.sight_blocked(unit.position, target.position):
			return Intent.idle()
		return Intent.use_action(attack_action.id, target.id)

	var is_ranged := attack_action.range_units > MELEE_RANGE_THRESHOLD

	if is_ranged:
		if attack_action.requires_line_of_sight and state.grid.sight_blocked(unit.position, target.position):
			return Intent.move_to(target.position)
		## Issue 544: no automatic retreat. A ranged unit that is in range fires;
		## holding distance is `keep_distance`, which the player writes and can see.
		var commit_max := attack_action.range_units * RANGED_COMMIT_FRACTION
		if dist > commit_max:
			return Intent.move_to(target.position)
		return Intent.use_action(attack_action.id, target.id)

	var commit_max_melee := attack_action.range_units * MELEE_COMMIT_FRACTION
	if dist > commit_max_melee:
		return Intent.move_to(target.position)
	return Intent.use_action(attack_action.id, target.id)

# ---------------------------------------------------------------------------

## Issue 93: true only when the unit has at least one attack and *every* one of
## them requires a marked target. "Every", not "any", on purpose -- a unit that
## also carries an ordinary weapon should use that weapon on unmarked enemies
## rather than standing idle, and only a unit whose whole arsenal is
## marked-only has a reason to hold fire. The Siege Engine is the one unit in
## the game with a single action, and that action is marked-only.
static func _all_attacks_require_a_mark(actions: Array[ActionDef]) -> bool:
	var found := false
	for a in _attack_candidates(actions):
		if not a.requires_marked_target:
			return false
		found = true
	return found

static func _only_marked(enemies: Array[CombatUnit]) -> Array[CombatUnit]:
	var out: Array[CombatUnit] = []
	for e in enemies:
		if e.has_status(CG.Status.MARKED):
			out.append(e)
	return out

## Every action the unit carries. **This used to be called `_usable_actions` and
## the name was a claim it did not make**, which is heron's finding in #214 and
## it cost content real work: they wrote `stalker_dart` as the Stalker's
## off-cooldown filler, relied on the word *usable*, and the dart fired zero
## times in 480 fights.
static func _all_actions(unit: CombatUnit) -> Array[ActionDef]:
	var out: Array[ActionDef] = []
	for id in unit.actions:
		var a: ActionDef = Registry.get_action(id)
		if a != null:
			out.append(a)
	return out

## The actions `CombatSim._resolve_use_action` would actually let this unit
## start on this tick: affordable, and off cooldown.
static func _actions_that_can_fire_now(state: CombatState, unit: CombatUnit) -> Array[ActionDef]:
	var out: Array[ActionDef] = []
	for a in _all_actions(unit):
		if PlanInterpreter.can_afford(state, unit, a):
			out.append(a)
	return out

## Issue 87: `power_scale > 0.0` as well as `heals`, because this function
## answers "do I have a way to put health back into a hurt ally" and an action
## that restores nothing is not one. `geyser_cleanse` is the first action in the
## game with `heals = true` and no healing in it -- the flag is what routes it
## through `_apply_action_effect`'s heal branch, so it emits no DAMAGE event at
## an ally, not a claim that it heals.
static func _first_heal(actions: Array[ActionDef]) -> ActionDef:
	for a in actions:
		if a.heals and a.power_scale > 0.0:
			return a
	return null

## Issue 99: a heal with no reach is a heal a unit casts on itself, so the
## neediest-ally search is restricted to the caster.
static func _heal_candidates(state: CombatState, unit: CombatUnit, heal_action: ActionDef) -> Array[CombatUnit]:
	if heal_action.range_units > 0.0:
		return state.living(unit.team)
	var out: Array[CombatUnit] = []
	if unit.alive:
		out.append(unit)
	return out

## Issue 150: the first self-targeted action this unit could usefully cast right
## now, or null.
static func _self_targeted_to_cast(state: CombatState, unit: CombatUnit, enemies: Array[CombatUnit]) -> ActionDef:
	for a in _all_actions(unit):
		if not a.targets_self:
			continue
		if a.heals or a.sustain_cost_per_tick > 0 or a.summons_unit_id != &"":
			continue
		if not PlanInterpreter.can_afford(state, unit, a):
			continue
		if _nearest_distance(unit, enemies) > _self_targeted_reach(unit, a):
			continue
		return a
	return null

## How close the fight has to be before a self-buff is worth spending a cast on.
static func _self_targeted_reach(unit: CombatUnit, action: ActionDef) -> float:
	if action.taunt_radius > 0.0:
		return action.taunt_radius
	var longest := -1.0
	for a in _attack_candidates(_all_actions(unit)):
		longest = maxf(longest, a.range_units)
	return longest if longest >= 0.0 else INF

static func _nearest_distance(unit: CombatUnit, enemies: Array[CombatUnit]) -> float:
	var best := INF
	for e in enemies:
		best = minf(best, unit.position.distance_to(e.position))
	return best

## Issue 129: an action a unit attacks *with*. Not a heal, and able to do damage
## at all.
static func _attack_candidates(actions: Array[ActionDef]) -> Array[ActionDef]:
	var out: Array[ActionDef] = []
	for a in actions:
		if a.heals or a.power_scale <= 0.0 or a.sustain_cost_per_tick > 0:
			continue
		out.append(a)
	return out

## The cheapest of `actions`, ties broken by list order. Null on an empty array.
static func _cheapest(actions: Array[ActionDef]) -> ActionDef:
	var best: ActionDef = null
	for a in actions:
		if best == null or a.resource_cost < best.resource_cost:
			best = a
	return best

## The attack this fallback would reach for on one side of
## `MELEE_RANGE_THRESHOLD`, or null when it owns none on that side.
static func default_attack_action(actions: Array[ActionDef], want_ranged: bool) -> ActionDef:
	var side: Array[ActionDef] = []
	for a in _attack_candidates(actions):
		if (a.range_units > MELEE_RANGE_THRESHOLD) == want_ranged:
			side.append(a)
	return _cheapest(side)

## Issue 62: among a unit's attacks, prefers whichever one's own melee-vs-ranged
## shape matches the target's current distance -- melee if already (or almost)
## in a melee action's own commit range, ranged otherwise. With only one side
## present it uses that side. The Warden is still the only unit in the game
## carrying both a melee and a ranged attack.
static func _choose_attack_action(actions: Array[ActionDef], unit: CombatUnit, target: CombatUnit) -> ActionDef:
	var melee := default_attack_action(actions, false)
	var ranged := default_attack_action(actions, true)
	if melee == null:
		return ranged
	if ranged == null:
		return melee
	var dist := unit.position.distance_to(target.position)
	if dist <= melee.range_units * MELEE_COMMIT_FRACTION:
		return melee
	return ranged

## TAUNTING forces target *selection*, not what a unit does after choosing --
## a taunted unit still uses its own approach/kite/commit logic against the
## taunter, it just picks the taunter as its candidate up front, the same way
## it would pick anyone else. Checked before the focus_bias logic below, and
## unconditionally (both pawns and enemies can be taunted).
static func _choose_target(state: CombatState, unit: CombatUnit, enemies: Array[CombatUnit]) -> CombatUnit:
	var taunter := _nearest_taunter(unit, enemies)
	if taunter != null:
		return taunter
	var nearest := _nearest(unit, enemies)
	if unit.pawn != null:
		## Issue 588: the enemy the player clicked, and only for a party pawn.
		## Searched inside `enemies` so it cannot outrank the mark filter above.
		var picked := player_focus(state, enemies)
		return picked if picked != null else nearest
	var enemy_def: EnemyDef = Registry.get_enemy(unit.enemy_id)
	if enemy_def == null or enemy_def.focus_bias <= 0.0:
		return nearest
	var focused := _most_focused(state, unit, enemies)
	if focused == null:
		return nearest
	return focused if state.rng.randf() < enemy_def.focus_bias else nearest

## Issue 588: the player's focused enemy if it is among `candidates`, else null.
## Shared with `PlanInterpreter` so the two layers cannot answer differently.
static func player_focus(state: CombatState, candidates: Array[CombatUnit]) -> CombatUnit:
	if state.player_focus_id < 0:
		return null
	for c in candidates:
		if c.id == state.player_focus_id and c.alive:
			return c
	return null

## The nearest living, opposing candidate carrying TAUNTING whose own
## `taunt_radius` reaches `unit`, or null.
static func _nearest_taunter(unit: CombatUnit, enemies: Array[CombatUnit]) -> CombatUnit:
	var best: CombatUnit = null
	var best_dist := INF
	for e in enemies:
		if not e.has_status(CG.Status.TAUNTING):
			continue
		var d := unit.position.distance_to(e.position)
		if d > e.taunt_radius:
			continue
		if d < best_dist:
			best_dist = d
			best = e
	return best

## The living enemy candidate that the most of `unit`'s own living allies
## currently have as their focus_id -- "already being attacked", read from the
## same field CombatSim sets whenever an ally's action resolves. Null when
## nobody has focused on any candidate yet, which is the natural "no pile
## exists to join" case.
static func _most_focused(state: CombatState, unit: CombatUnit, candidates: Array[CombatUnit]) -> CombatUnit:
	var counts := {}
	for ally in state.living(unit.team):
		if ally.focus_id != -1:
			counts[ally.focus_id] = int(counts.get(ally.focus_id, 0)) + 1
	var best: CombatUnit = null
	var best_count := 0
	for c in candidates:
		var n := int(counts.get(c.id, 0))
		if n > best_count:
			best_count = n
			best = c
	return best

static func _nearest(unit: CombatUnit, others: Array[CombatUnit]) -> CombatUnit:
	var best: CombatUnit = null
	var best_dist := INF
	for o in others:
		var d := unit.position.distance_to(o.position)
		if d < best_dist:
			best_dist = d
			best = o
	return best

static func _lowest_hp_fraction(units: Array[CombatUnit]) -> CombatUnit:
	var best: CombatUnit = null
	var best_fraction := INF
	for u in units:
		var f := u.hp_fraction()
		if f < best_fraction:
			best_fraction = f
			best = u
	return best
