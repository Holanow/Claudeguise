extends SceneTree

## Compares every preset plan's firing condition against the range of the action
## that plan fires, and prints the ones that disagree.
##
##   godot --headless --path . --script res://Tools/PlanRangeAudit.gd
##
## MANAGER-OWNED. Not part of the gate: the permanent version of this check
## belongs in teal's tests, per issue 14a. This is the one-off that produces the
## list, so they get all of them rather than the two I happened to notice while
## reading one fight.
##
## The mismatch is invisible by construction. A plan's `enemy_in_range`
## condition and its action's `range_units` are two numbers in two files owned by
## one session, and neither is wrong on its own. The simulation turns the
## disagreement into a silent miss, and on screen that reads as a broken caster.


func _init() -> void:
	var problems := 0
	var checked := 0

	for class_id in Registry.all_class_ids():
		print("")
		print("== ", class_id)
		for plan in PresetPlans.for_class(class_id):
			var action_id := _action_of(plan)
			if action_id == &"":
				print("   %-32s (no action block)" % plan.id)
				continue
			var action = Registry.get_action(action_id)
			if action == null:
				print("   %-32s -> UNKNOWN ACTION '%s'" % [plan.id, action_id])
				problems += 1
				continue

			checked += 1
			var cond_range := _condition_range(plan)
			var targeting := _targeting_of(plan)

			# A self-targeted action is always in range of itself, whatever its
			# range_units says. The first version of this tool flagged
			# warrior_guard (target_self, range 0) as a defect, which would have
			# handed teal a list with a wrong entry in it — the exact thing I
			# keep telling everyone not to do. Checked before reporting.
			if targeting == &"target_self":
				print("   %-32s action %-18s self-targeted, always in range" % [plan.id, action_id])
				continue

			var note := ""
			if cond_range < 0.0:
				# No range condition at all: the plan can fire from anywhere.
				note = "NO RANGE CONDITION - can fire from any distance"
				problems += 1
			elif cond_range > action.range_units:
				note = "CONDITION %.0f > ACTION RANGE %.0f - misses beyond %.0f" % [
					cond_range, action.range_units, action.range_units
				]
				problems += 1

			# A plan that fires at the nearest enemy is at least aiming at the
			# closest thing. One that picks by hp is aiming at whoever is
			# weakest, who may be across the room, and a range condition
			# measured against the *nearest* enemy says nothing about them.
			if targeting != &"target_nearest_enemy" and cond_range >= 0.0:
				if note != "":
					note += " | "
				note += "condition measures nearest enemy but targets '%s'" % targeting
				problems += 1

			print("   %-32s action %-18s range %6.0f  cond %6s  %s" % [
				plan.id, action_id, action.range_units,
				"none" if cond_range < 0.0 else "%.0f" % cond_range,
				note,
			])

	print("")
	print("checked %d plans, %d problems" % [checked, problems])
	quit(0)

func _action_of(plan) -> StringName:
	for b in plan.blocks:
		if b.kind == PlanBlock.Kind.ACTION:
			return b.args.get("action_id", &"")
	return &""

func _targeting_of(plan) -> StringName:
	for b in plan.blocks:
		if b.kind == PlanBlock.Kind.TARGETING:
			return b.op
	return &""

## Returns the condition's range, or -1.0 when the condition does not constrain
## distance at all.
func _condition_range(plan) -> float:
	if plan.condition == null:
		return -1.0
	if plan.condition.op != &"enemy_in_range":
		return -1.0
	return float(plan.condition.args.get("range", 0.0))
