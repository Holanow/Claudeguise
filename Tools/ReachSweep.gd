extends SceneTree

## Issue 699 widened: which actions can `DefaultPlan` (the live fallback,
## `SimDeps.default_decide`) never select, for any pawn or enemy, in any
## reachable cooldown/resource state?
##
## Calls `DefaultPlan`'s own row-selection functions -- `first_heal`,
## `attacks`, `side_attack` -- against every realizable subset of "which
## cooldown-bearing actions are currently down" crossed with every resource
## threshold a kit's own costs define. That is the same filtering `candidates()`
## does; this tool only supplies the combinatorics of which state is reachable.

class KitAction:
	var id: StringName
	var action: ActionDef
	var eligible_heal: bool
	var eligible_attack: bool
	var eligible_buff: bool

func _classify(a: ActionDef) -> KitAction:
	var k := KitAction.new()
	k.id = a.id
	k.action = a
	k.eligible_heal = a.heals and a.power_scale > 0.0
	k.eligible_attack = not a.heals and a.power_scale > 0.0 and a.sustain_cost_per_tick <= 0
	k.eligible_buff = a.targets_self and not a.heals and a.sustain_cost_per_tick <= 0 and a.summons_unit_id == &""
	return k

## Every subset of the cooldown-bearing actions, as a Dictionary id->bool "down".
func _cooldown_subsets(actions: Array[ActionDef]) -> Array[Dictionary]:
	var cd_ids: Array[StringName] = []
	for a in actions:
		if a.cooldown_ticks > 0:
			cd_ids.append(a.id)
	var out: Array[Dictionary] = [{}]
	for id in cd_ids:
		var next: Array[Dictionary] = []
		for combo in out:
			var off := combo.duplicate()
			var on := combo.duplicate()
			on[id] = true
			next.append(off)
			next.append(on)
		out = next
	return out

func _thresholds(actions: Array[ActionDef]) -> Array[int]:
	var costs := {}
	for a in actions:
		costs[a.resource_cost] = true
	var out: Array[int] = []
	out.assign(costs.keys())
	out.sort()
	return out

## What `DefaultPlan.candidates()` would hand each row this tick, given which
## actions are down and how much resource is on hand.
func _affordable_now(actions: Array[ActionDef], down: Dictionary, resource: int) -> Array[ActionDef]:
	var out: Array[ActionDef] = []
	for a in actions:
		if a.resource_cost <= resource and not down.get(a.id, false):
			out.append(a)
	return out

func _reachable(actions: Array[ActionDef]) -> Dictionary:
	var reached := {}
	for down in _cooldown_subsets(actions):
		for resource in _thresholds(actions):
			var affordable := _affordable_now(actions, down, resource)
			if DefaultPlan.first_heal(affordable) == null and DefaultPlan.attacks(affordable).is_empty():
				affordable = actions
			var heal := DefaultPlan.first_heal(affordable)
			if heal != null:
				reached[heal.id] = true
			var melee := DefaultPlan.side_attack(affordable, false)
			if melee != null:
				reached[melee.id] = true
			var ranged := DefaultPlan.side_attack(affordable, true)
			if ranged != null:
				reached[ranged.id] = true
			var buff: Variant = _self_buff_pick(actions, down, resource)
			if buff != null:
				reached[buff] = true
	return reached

## Same order and same exclusions as `DefaultPlan.self_buff`, minus the
## proximity check (a positional fact, not a vocabulary one).
func _self_buff_pick(actions: Array[ActionDef], down: Dictionary, resource: int) -> Variant:
	for a in actions:
		if not a.targets_self or a.heals or a.sustain_cost_per_tick > 0 or a.summons_unit_id != &"":
			continue
		if a.resource_cost > resource or down.get(a.id, false):
			continue
		return a.id
	return null

func _kit_report(label: String, ids: Array[StringName]) -> void:
	var actions: Array[ActionDef] = []
	for id in ids:
		var a: ActionDef = ActionLibrary.get_action(id)
		if a != null and not actions.any(func(x): return x.id == a.id):
			actions.append(a)
	if actions.is_empty():
		return
	var reached := _reachable(actions)
	for a in actions:
		var k := _classify(a)
		if not (k.eligible_heal or k.eligible_attack or k.eligible_buff):
			print("  GAP       %-22s %-16s never a candidate for any row (heals=%s power_scale=%s sustain=%s summons=%s targets_self=%s)"
				% [label, a.id, a.heals, a.power_scale, a.sustain_cost_per_tick, a.summons_unit_id != &"", a.targets_self])
			continue
		if not reached.has(a.id):
			print("  SHADOWED  %-22s %-16s cost=%d cooldown=%d" % [label, a.id, a.resource_cost, a.cooldown_ticks])

func _init() -> void:
	print("== pawn classes (real kit incl. weapon-granted action) ==")
	for class_id in ClassLibrary.all_ids():
		var pawn: PawnData = PawnFactory.make_preset_pawn(class_id, StringName("%s_probe" % class_id), String(class_id))
		_kit_report(String(class_id), ActionLibrary.actions_for_pawn(pawn))

	print("== enemies ==")
	for enemy_id in EnemyLibrary.all_ids():
		var e: EnemyDef = EnemyLibrary.get_enemy(enemy_id)
		_kit_report(String(enemy_id), e.actions)

	print("done")
	quit(0)
