extends SceneTree

## Throwaway: how many preset plans each starter pawn can actually pay for.

func _init() -> void:
	for class_id in Registry.all_class_ids():
		var pawn := PawnFactory.make_starter_pawn(class_id, class_id, String(class_id))
		var blocks := 0
		for p in pawn.plans:
			blocks += p.block_count()
		print("%s: WIS budget %d, plans %d, blocks %d, active %d" % [
			class_id, Balance.plan_block_budget(pawn), pawn.plans.size(), blocks,
			PlanInterpreter.active_plan_count(pawn)])
	quit(0)
