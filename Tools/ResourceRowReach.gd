extends SceneTree

## Issue 488: whether a rolled pawn can ever pay for its own library rows.
##
## For every preset plan gated on a resource, this counts the rolled pawns
## whose `Balance.max_resource` sits BELOW what the row asks (the row can never
## fire) and the ones for whom the row asks for the whole pool. Seeds 0..499,
## matching `RollSpread`.

const SEEDS := 500

func _init() -> void:
	print("======== resource-gated library rows, over %d rolled seeds ========" % SEEDS)
	for cid in Registry.all_class_ids():
		var cls := Registry.get_class_def(cid)
		var rows := _gated_rows(cid)
		var fixed := PawnFactory.make_starter_pawn(cid, &"p", "p")
		var ceilings: Array[int] = []
		for s in SEEDS:
			ceilings.append(Balance.max_resource(PawnFactory.make_rolled_pawn(cid, &"p", "p", s)))
		var sorted := ceilings.duplicate()
		sorted.sort()
		print("")
		print("  %s  fixed ceiling %d   rolled ceiling min %d / median %d / max %d" % [
			String(cid), Balance.max_resource(fixed),
			sorted[0], sorted[sorted.size() / 2], sorted[sorted.size() - 1]])
		print("    worst case the floors allow: %d" % floor_ceiling(cls))
		var hist := {}
		for c in sorted:
			hist[c] = int(hist.get(c, 0)) + 1
		var keys := hist.keys()
		keys.sort()
		var parts := PackedStringArray()
		for k in keys:
			parts.append("%d:%d" % [k, hist[k]])
		print("    ceilings  %s" % " ".join(parts))
		if rows.is_empty():
			print("    no library row gated on resource")
			continue
		for row in rows:
			var unfireable := 0
			var whole_pool := 0
			for c in ceilings:
				var need := requirement(row[1], c)
				if need > c:
					unfireable += 1
				elif need == c:
					whole_pool += 1
			print("    %-32s %-16s unfireable %3d/%d   needs the whole pool %3d/%d" % [
				String(row[0]), describe(row[1]), unfireable, SEEDS, whole_pool, SEEDS])
	quit(0)

func _gated_rows(class_id: StringName) -> Array:
	var out := []
	for p in PresetPlans.for_class(class_id):
		if p.condition is SelfResourceAtLeastBlock or p.condition is SelfResourceAtLeastFractionBlock:
			out.append([p.id, p.condition])
	return out


## What a condition block demands of a pawn whose ceiling is `ceiling`. Mirrors
## `PlanInterpreter._eval_condition`, which is the source of truth.
static func requirement(block: PlanBlock, ceiling: int) -> int:
	if block is SelfResourceAtLeastFractionBlock:
		return int(ceil(float(ceiling) * (block as SelfResourceAtLeastFractionBlock).fraction))
	return (block as SelfResourceAtLeastBlock).amount

static func describe(block: PlanBlock) -> String:
	return block.describe()

## The ceiling a pawn of this class has when every rolled attribute sits on its
## own floor. Nothing the roller can produce goes below this.
static func floor_ceiling(class_def: ClassDef) -> int:
	var pawn := PawnFactory.make_starter_pawn(class_def.id, &"p", "p")
	for a in PawnFactory.ROLLED_ATTRIBUTES:
		pawn.attribute_bonus[a] = PawnFactory.attribute_floor(class_def, a) - class_def.attribute(a)
	return Balance.max_resource(pawn)
