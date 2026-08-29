extends RefCounted
class_name UnitGlobals


## Issue 755/756: standing preferences that steer `DefaultBehavior` and
## `CombatSim`'s movement when no plan row overrides them. One reader for both
## sources -- `PawnData` for a pawn, `EnemyDef` for an enemy -- so the two
## slices cannot answer the same question differently.

const POSTURE_SEEK_ENEMY := &"seek_enemy"
const POSTURE_STAND_NEAR_ALLY := &"stand_near_ally"

const TARGET_NEAREST := &""
const TARGET_FARTHEST := &"farthest"

static func avoid_hazards(unit: CombatUnit) -> bool:
	if unit.pawn != null:
		return unit.pawn.avoid_hazards
	var e := EnemyLibrary.get_enemy(unit.enemy_id)
	return e.avoid_hazards if e != null else true

static func target_preference(unit: CombatUnit) -> StringName:
	if unit.pawn != null:
		return unit.pawn.target_preference
	var e := EnemyLibrary.get_enemy(unit.enemy_id)
	return e.target_preference if e != null else TARGET_NEAREST

static func posture(unit: CombatUnit) -> StringName:
	if unit.pawn != null:
		return unit.pawn.posture
	var e := EnemyLibrary.get_enemy(unit.enemy_id)
	return e.posture if e != null else POSTURE_SEEK_ENEMY

static func stand_near_ally_id(unit: CombatUnit) -> StringName:
	if unit.pawn != null:
		return unit.pawn.stand_near_ally_id
	var e := EnemyLibrary.get_enemy(unit.enemy_id)
	return e.stand_near_ally_id if e != null else &""

## The base candidate `_choose_target` should prefer before the taunt/mark/
## focus rules above it run, honouring `target_preference`. Never called when
## there is a taunter -- that check outranks this one unconditionally.
static func preferred_target(state: CombatState, unit: CombatUnit, candidates: Array[CombatUnit]) -> CombatUnit:
	if target_preference(unit) == TARGET_FARTHEST:
		var f := PlanInterpreter.farthest(state, unit, PlanInterpreter.enemy_team(unit.team))
		if f != null:
			return f
	return _nearest_of(unit, candidates)

static func _nearest_of(unit: CombatUnit, others: Array[CombatUnit]) -> CombatUnit:
	var best: CombatUnit = null
	var best_dist := INF
	for o in others:
		var d := unit.position.distance_to(o.position)
		if d < best_dist:
			best_dist = d
			best = o
	return best

## Pawn side: the named ally by `PawnData.id`, or null when it is dead,
## dangling, self-named, or not a party pawn at all -- every one of those
## degrades to `seek_enemy`, per the player's own ruling on #755.
static func stand_near_ally_unit(state: CombatState, unit: CombatUnit) -> CombatUnit:
	if unit.pawn == null:
		return _stand_near_enemy_type(state, unit)
	var name := stand_near_ally_id(unit)
	if name == &"" or (unit.pawn != null and name == unit.pawn.id):
		return null
	for ally in state.living(unit.team):
		if ally.id != unit.id and ally.pawn != null and ally.pawn.id == name:
			return ally
	return null

## Enemy side: the nearest living instance of the named `EnemyDef.id` --
## `EnemyDef` has no per-instance identity to name, so this names a type.
static func _stand_near_enemy_type(state: CombatState, unit: CombatUnit) -> CombatUnit:
	var name := stand_near_ally_id(unit)
	if name == &"":
		return null
	var candidates: Array[CombatUnit] = []
	for ally in state.living(unit.team):
		if ally.id != unit.id and ally.enemy_id == name:
			candidates.append(ally)
	return _nearest_of(unit, candidates)
