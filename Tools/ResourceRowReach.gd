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
	_fight_arm()
	quit(0)

## What the row does in a real fight. `SampleFights` cannot see this change at
## all -- it builds starter pawns and a starter pawn carries no plan rows
## (issue 399) -- so both arms are run here, with the old absolute condition
## against the new fraction one, on the same rolled pawns and the same seeds.
const FIGHT_SEEDS := 40

func _fight_arm() -> void:
	print("")
	print("======== Execute in a real fight, rolled preset parties, %d seeds x every room ========" % FIGHT_SEEDS)
	var arms := {
		&"amount 40": _gated(&"self_resource_at_least", {"amount": 40}),
		&"fraction 1.0": _gated(&"self_resource_at_least_fraction", {"fraction": 1.0}),
	}
	for arm in arms:
		var casts := 0
		var wins := 0
		var fights := 0
		var warriors_that_ever_fired := 0
		for encounter_id in Registry.pickable_encounter_ids():
			var encounter := Registry.get_encounter(encounter_id)
			for s in FIGHT_SEEDS:
				var party: Array[PawnData] = []
				for cid in [&"warrior", &"priest", &"geysermancer", &"siege_master"]:
					var pawn := PawnFactory.make_rolled_pawn(cid, StringName("%s_0" % cid), String(cid), s)
					pawn.plans = PresetPlans.for_class(cid)
					for plan in pawn.plans:
						if plan.id == &"warrior_execute_finisher":
							plan.condition = arms[arm]
					party.append(pawn)
				var state := CombatSim.build(party, encounter, s)
				var outcome := CombatSim.run(state)
				fights += 1
				if outcome == CombatState.Outcome.PLAYER_WIN:
					wins += 1
				var fired := 0
				for e in state.events:
					if e.kind == CG.EventKind.ACTION_FIRE and e.action_id == &"warrior_execute":
						fired += 1
				casts += fired
				if fired > 0:
					warriors_that_ever_fired += 1
		print("  %-14s Execute cast %4d over %d fights   %d fights had at least one   wins %d/%d" % [
			arm, casts, fights, warriors_that_ever_fired, wins, fights])

func _gated(op: StringName, args: Dictionary) -> PlanBlock:
	var b := PlanBlock.new()
	b.kind = PlanBlock.Kind.CONDITION
	b.op = op
	b.args = args
	return b

## Every preset row of a class whose condition gates on resource, as
## [plan id, condition block].
func _gated_rows(class_id: StringName) -> Array:
	var out := []
	for p in PresetPlans.for_class(class_id):
		if p.condition != null and RESOURCE_OPS.has(p.condition.op):
			out.append([p.id, p.condition])
	return out

const RESOURCE_OPS := [&"self_resource_at_least", &"self_resource_at_least_fraction"]

## What a condition block demands of a pawn whose ceiling is `ceiling`. Mirrors
## `PlanInterpreter._eval_condition`, which is the source of truth.
static func requirement(block: PlanBlock, ceiling: int) -> int:
	if block.op == &"self_resource_at_least_fraction":
		return int(ceil(float(ceiling) * float(block.args.get("fraction", 1.0))))
	return int(block.args.get("amount", 0))

static func describe(block: PlanBlock) -> String:
	return PlanInterpreter.describe_op(block.op, block.args)

## The ceiling a pawn of this class has when every rolled attribute sits on its
## own floor. Nothing the roller can produce goes below this.
static func floor_ceiling(class_def: ClassDef) -> int:
	var pawn := PawnFactory.make_starter_pawn(class_def.id, &"p", "p")
	for a in PawnFactory.ROLLED_ATTRIBUTES:
		pawn.attribute_bonus[a] = PawnFactory.attribute_floor(class_def, a) - class_def.attribute(a)
	return Balance.max_resource(pawn)
