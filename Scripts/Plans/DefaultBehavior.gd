extends RefCounted

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")
const Intent := preload("res://Scripts/Core/Intent.gd")
const ActionDef := preload("res://Scripts/Core/ActionDef.gd")
const EnemyDef := preload("res://Scripts/Core/EnemyDef.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const Terrain := preload("res://Scripts/Core/Terrain.gd")

## What a unit does when no plan fires. Every unit has this, including enemies,
## which have no plans at all in this slice.
##
## OWNER: teal.
##
## This is more load-bearing than it looks. A player is not expected to touch
## the plan system until late in the game per README.md, so the default
## behaviour is what most fights actually look like, and it is the thing being
## judged when the question is whether the combat is fun.
##
## Deliberately generic over pawns and enemies: it reads `unit.actions` and
## `unit.team` and nothing else class-specific, so the same logic drives a
## Warrior and a Grunt. "Ranged" is inferred from an action's own range rather
## than from ClassDef.style, because enemies have no ClassDef at all.

## An action with more range than this is treated as ranged: kept at, rather
## than closed to melee distance. Every melee action in this slice sits at
## 40-45 world units; every ranged one sits at 200+.
const MELEE_RANGE_THRESHOLD := 60.0

## A ranged unit closer than this fraction of its own range backs off instead
## of firing, so "ranged classes keep their distance" is an observable choice
## rather than an accident of where the fight started.
const KITE_RANGE_FRACTION := 0.6

## Range is checked when a hit lands, not when it commits (CombatSim's own
## rule), so firing right at the edge of range is a guaranteed whiff against
## anything that flees during the wind-up: it walks the small remaining
## distance to safety for free while the attacker stands there committed.
## Both branches below fire with a safety margin instead of at the literal
## boundary, which is what actually lets a faster melee unit run a kiter down
## instead of forever narrowly missing it.
const MELEE_COMMIT_FRACTION := 0.5
const RANGED_COMMIT_FRACTION := 0.85

## An ally at or below this fraction of max hp counts as needing a heal.
const HEAL_THRESHOLD_FRACTION := 0.5

const RETREAT_STEP := 200.0

static func decide(state: CombatState, unit: CombatUnit) -> Intent:
	var enemy_team := CG.Team.ENEMY if unit.team == CG.Team.PLAYER else CG.Team.PLAYER
	var enemies := state.living(enemy_team)
	if enemies.is_empty():
		return Intent.idle()

	var candidates := _usable_actions(unit)
	if candidates.is_empty():
		return Intent.idle()

	var heal_action := _first_heal(candidates)
	if heal_action != null:
		var neediest := _lowest_hp_fraction(state.living(unit.team))
		if neediest != null and neediest.hp_fraction() <= HEAL_THRESHOLD_FRACTION:
			var dist_to_ally := unit.position.distance_to(neediest.position)
			if dist_to_ally <= heal_action.range_units:
				return Intent.use_action(heal_action.id, neediest.id)
			return Intent.move_to(neediest.position)

	var target := _choose_target(state, unit, enemies)
	if target == null:
		return Intent.idle()

	# Issue 62: picks a melee-vs-ranged action by the current target's actual
	# distance, rather than always the first non-heal entry in unit.actions.
	# Found while re-tuning after free basic attacks moved the floor-clear
	# table: The Warden carries both warden_axe (melee) and warden_chain_toss
	# (ranged, "chain for whoever does not [close]" per its own content
	# comment) specifically so a party that kites its slow move_speed still
	# has to answer something -- but axe being first in EnemyDef.actions
	# meant chain_toss never fired even once in a real fight, because the
	# old _first_non_heal always returned axe regardless of range. A unit
	# with only one non-heal action (every player, every other enemy in the
	# bestiary today) sees no behaviour change: _choose_attack_action
	# returns that single action exactly like _first_non_heal did.
	var attack_action := _choose_attack_action(candidates, unit, target)
	if attack_action == null:
		return Intent.idle()

	var dist := unit.position.distance_to(target.position)
	var is_ranged := attack_action.range_units > MELEE_RANGE_THRESHOLD

	if is_ranged:
		# Issue 34: a flagged action whose line to the target is blocked has
		# nothing to gain from firing -- the resolve-time check would just
		# report the MISS this avoids committing to. Approaching is the same
		# fallback an out-of-range shot already gets; only actions that opted
		# into requires_line_of_sight are affected, so nothing unflagged
		# changes.
		if attack_action.requires_line_of_sight and Terrain.line_is_blocked(state.terrain, unit.position, target.position):
			return Intent.move_to(target.position)
		# PLAYTEST-NOTES-2.md note 11: "the Abomination runs away a lot...
		# tanks should move toward enemies." Root cause traced directly: with
		# no plan firing, `_choose_attack_action` picks `abomination_hook`
		# (range 140, so `is_ranged` here) the moment a target sits beyond
		# `abomination_grapple`'s own melee commit range -- and this branch
		# then treated a 140-range gap-closer exactly like a 200+-range
		# standoff weapon, backing off if the target ever closed inside 84
		# units (0.6 * 140) instead of letting it hold ground or finish
		# closing. Every real ranged action in the bestiary is a stay-at-
		# range weapon (bolts, arrows, blasts); a pull is the opposite by
		# construction -- it exists to drag a target closer, so a unit
		# firing one has nothing to protect by keeping its own distance.
		# `pull_distance > 0.0` is the same generic, action-level signal
		# `heals`/`requires_line_of_sight` already are: it needs no
		# ClassDef or role awareness, and no other action in the game sets
		# it today, so nothing else changes behaviour.
		var wants_to_close := attack_action.pull_distance > 0.0
		var kite_min := attack_action.range_units * KITE_RANGE_FRACTION
		var commit_max := attack_action.range_units * RANGED_COMMIT_FRACTION
		if dist < kite_min and not wants_to_close:
			return Intent.move_to(_retreat_point(unit, target))
		if dist > commit_max:
			return Intent.move_to(target.position)
		return Intent.use_action(attack_action.id, target.id)

	var commit_max_melee := attack_action.range_units * MELEE_COMMIT_FRACTION
	if dist > commit_max_melee:
		return Intent.move_to(target.position)
	return Intent.use_action(attack_action.id, target.id)

# ---------------------------------------------------------------------------

static func _usable_actions(unit: CombatUnit) -> Array[ActionDef]:
	var out: Array[ActionDef] = []
	for id in unit.actions:
		var a: ActionDef = Registry.get_action(id)
		if a != null:
			out.append(a)
	return out

## Issue 87: `power_scale > 0.0` as well as `heals`, because this function
## answers "do I have a way to put health back into a hurt ally" and an action
## that restores nothing is not one. `geyser_cleanse` is the first action in the
## game with `heals = true` and no healing in it -- the flag is what routes it
## through `_apply_action_effect`'s heal branch, so it emits no DAMAGE event at
## an ally, not a claim that it heals.
##
## Without this the Geysermancer answers every ally below
## HEAL_THRESHOLD_FRACTION by casting a 0-power heal, or by walking toward that
## ally to get in range to cast one, instead of attacking -- a real behaviour
## change for a class that had no heal at all, arriving from a support action
## that has nothing to do with hp. Nothing else in the game changes: priest_heal
## is the only other action with `heals` set and its power_scale is well above 0.
static func _first_heal(actions: Array[ActionDef]) -> ActionDef:
	for a in actions:
		if a.heals and a.power_scale > 0.0:
			return a
	return null

static func _first_non_heal(actions: Array[ActionDef]) -> ActionDef:
	for a in actions:
		if not a.heals:
			return a
	return null

## Issue 62: among a unit's non-heal actions, prefers whichever one's own
## melee-vs-ranged shape matches the target's current distance -- melee if
## already (or almost) in a melee action's own commit range, ranged
## otherwise. Falls back to `_first_non_heal`'s exact behaviour (the first
## non-heal action, in list order) whenever there is nothing to choose
## between: no candidates, only one, or every candidate on the same side of
## MELEE_RANGE_THRESHOLD. That covers every unit in the game today except
## The Warden, the only one carrying both a melee and a ranged action.
static func _choose_attack_action(actions: Array[ActionDef], unit: CombatUnit, target: CombatUnit) -> ActionDef:
	var melee: ActionDef = null
	var ranged: ActionDef = null
	for a in actions:
		if a.heals:
			continue
		if a.range_units > MELEE_RANGE_THRESHOLD:
			if ranged == null:
				ranged = a
		elif melee == null:
			melee = a
	if melee == null or ranged == null:
		return _first_non_heal(actions)
	var dist := unit.position.distance_to(target.position)
	if dist <= melee.range_units * MELEE_COMMIT_FRACTION:
		return melee
	return ranged

## TAUNTING forces target *selection*, not what a unit does after choosing --
## a taunted unit still uses its own approach/kite/commit logic against the
## taunter, it just picks the taunter as its candidate up front, the same way
## it would pick anyone else. Checked before the focus_bias logic below, and
## unconditionally (both pawns and enemies can be taunted).
##
## This lives here rather than in CombatSim on purpose: CombatSim's
## _decide_phase only calls DefaultBehavior.decide() once PlanInterpreter has
## already had its turn and produced nothing, so a real Plan's explicit
## targeting is never touched by this -- not because of a check, but because
## this function simply never runs when a plan fired. Per rook's ruling: taunt
## overrides the *default* fallback, never a stated plan.
##
## Issue 7's concentration finding: numbers and a stat spread raise total
## damage but not concentrated damage, because every enemy independently
## picked its own nearest pawn. `EnemyDef.focus_bias` (0.0-1.0, pawns do not
## have one) is this unit's chance of joining whichever living enemy its own
## allies are already committed to, rather than defaulting to nearest. Rolled
## from state.rng, never a fresh generator, so a seed still reproduces a
## fight exactly.
static func _choose_target(state: CombatState, unit: CombatUnit, enemies: Array[CombatUnit]) -> CombatUnit:
	var taunter := _nearest_taunter(unit, enemies)
	if taunter != null:
		return taunter
	var nearest := _nearest(unit, enemies)
	if unit.pawn != null:
		return nearest
	var enemy_def: EnemyDef = Registry.get_enemy(unit.enemy_id)
	if enemy_def == null or enemy_def.focus_bias <= 0.0:
		return nearest
	var focused := _most_focused(state, unit, enemies)
	if focused == null:
		return nearest
	return focused if state.rng.randf() < enemy_def.focus_bias else nearest

## The nearest living, opposing candidate carrying TAUNTING whose own
## taunt_radius reaches `unit` -- null when nobody taunting is in range,
## the natural "taunt does not apply" case. Deterministic: iterates the same
## `enemies` array `_nearest` already does, first strictly-closer candidate
## wins, no tie-break needed beyond iteration order.
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

static func _retreat_point(unit: CombatUnit, threat: CombatUnit) -> Vector2:
	var away := unit.position - threat.position
	if away.length() < 0.0001:
		away = Vector2(1.0, 0.0)
	return unit.position + away.normalized() * RETREAT_STEP
