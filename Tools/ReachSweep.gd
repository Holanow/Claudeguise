extends SceneTree

## Issue 719: which abilities can `DefaultPlan` (the live fallback,
## `SimDeps.default_decide`) never select? It now has one row and one action,
## `DefaultPlan.weapon_attack(unit)`, chosen with no cost search -- so the only
## thing left to check is whether that one action resolves, for every kit.

func _check(label: String, unit: CombatUnit) -> void:
	var a := DefaultPlan.weapon_attack(unit)
	if a == null:
		print("  GAP  %-22s has no weapon-granted basic attack: the fallback can never act" % label)
		return
	if PlanInterpreter.attacks([a]).is_empty():
		print("  GAP  %-22s %-16s resolved but is not attack-shaped" % [label, a.id])

func _init() -> void:
	print("== pawn classes (weapon-granted basic attack) ==")
	for class_id in ClassLibrary.all_ids():
		var pawn: PawnData = PawnFactory.make_preset_pawn(class_id, StringName("%s_probe" % class_id), String(class_id))
		var unit := CombatUnit.new()
		unit.pawn = pawn
		unit.actions = ActionLibrary.actions_for_pawn(pawn)
		_check(String(class_id), unit)

	print("== enemies (first attack-shaped action) ==")
	for enemy_id in EnemyLibrary.all_ids():
		var e: EnemyDef = EnemyLibrary.get_enemy(enemy_id)
		var unit := CombatUnit.new()
		unit.actions = e.actions
		_check(String(enemy_id), unit)

	print("done")
	quit(0)
