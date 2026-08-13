extends RefCounted

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")
const Intent := preload("res://Scripts/Core/Intent.gd")
const ActionDef := preload("res://Scripts/Core/ActionDef.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")

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

	var attack_action := _first_non_heal(candidates)
	if attack_action == null:
		return Intent.idle()

	var target := _nearest(unit, enemies)
	if target == null:
		return Intent.idle()

	var dist := unit.position.distance_to(target.position)
	var is_ranged := attack_action.range_units > MELEE_RANGE_THRESHOLD

	if is_ranged:
		var kite_min := attack_action.range_units * KITE_RANGE_FRACTION
		var commit_max := attack_action.range_units * RANGED_COMMIT_FRACTION
		if dist < kite_min:
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

static func _first_heal(actions: Array[ActionDef]) -> ActionDef:
	for a in actions:
		if a.heals:
			return a
	return null

static func _first_non_heal(actions: Array[ActionDef]) -> ActionDef:
	for a in actions:
		if not a.heals:
			return a
	return null

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
