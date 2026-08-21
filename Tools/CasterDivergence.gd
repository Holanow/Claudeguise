extends SceneTree

## Issue 406: how far apart an unedited Priest and an unedited Geysermancer
## actually are. Samples the finished event stream, never live unit state.

const SEEDS := 40

func _init() -> void:
	var encounter := Registry.get_encounter(CG.DEFAULT_ENCOUNTER)
	for cid in [&"priest", &"geysermancer"]:
		_kit(cid)
	for cid in [&"priest", &"geysermancer"]:
		_sample(cid, encounter, false)
	print("")
	print("-- with every library row added (what the player can reach) --")
	for cid in [&"priest", &"geysermancer"]:
		_sample(cid, encounter, true)
	print("")
	print("-- the swap a player can actually make, unedited --")
	_party(["warrior", "abomination", "siege_master", "priest"], encounter)
	_party(["warrior", "abomination", "siege_master", "geysermancer"], encounter)
	quit(0)

## What the fallback would reach for, decided from content alone.
func _kit(class_id: StringName) -> void:
	var pawn := PawnFactory.make_starter_pawn(class_id, &"k", "k")
	var defs: Array[ActionDef] = []
	for id in CombatSim._collect_player_actions(pawn):
		var a: ActionDef = Registry.get_action(id)
		if a != null:
			defs.append(a)
	print("")
	print("%s kit:" % class_id)
	for a in defs:
		print("   %-22s cost %-3d range %-6.0f power %.2f  heals=%s wind=%d cd=%d" % [
			a.id, a.resource_cost, a.range_units, a.power_scale, a.heals,
			a.wind_up_ticks, a.cooldown_ticks,
		])
	var melee: ActionDef = DefaultBehavior.default_attack_action(defs, false)
	var ranged: ActionDef = DefaultBehavior.default_attack_action(defs, true)
	print("   fallback attack: melee=%s ranged=%s" % [
		melee.id if melee != null else "none", ranged.id if ranged != null else "none",
	])

func _party(class_ids: Array, encounter) -> void:
	var wins := 0
	var ticks: Array[int] = []
	var fired := {}
	for s in SEEDS:
		var party: Array[PawnData] = []
		for cid in class_ids:
			party.append(PawnFactory.make_starter_pawn(StringName(cid), StringName("%s" % cid), cid))
		var state := CombatSim.build(party, encounter, s)
		if CombatSim.run(state) == CombatState.Outcome.PLAYER_WIN:
			wins += 1
		ticks.append(state.tick)
		for e in state.events:
			var u := state.unit(e.source_id)
			if e.kind == CG.EventKind.ACTION_FIRE and u != null and u.pawn != null:
				fired[e.action_id] = int(fired.get(e.action_id, 0)) + 1
	ticks.sort()
	var keys := fired.keys()
	keys.sort()
	print("")
	print("%s: win %d/%d  ticks median %d" % [", ".join(class_ids), wins, SEEDS, ticks[ticks.size() / 2]])
	for k in keys:
		print("   %-22s %d" % [k, fired[k]])

func _sample(class_id: StringName, encounter, presets: bool) -> void:
	var wins := 0
	var ticks: Array[int] = []
	var fired := {}
	var damage := 0
	var healed := 0
	for s in SEEDS:
		var party: Array[PawnData] = []
		for i in 4:
			var id := StringName("%s_%d" % [class_id, i])
			party.append(
				PawnFactory.make_preset_pawn(class_id, id, String(class_id)) if presets
				else PawnFactory.make_starter_pawn(class_id, id, String(class_id))
			)
		var state := CombatSim.build(party, encounter, s)
		var outcome := CombatSim.run(state)
		if outcome == CombatState.Outcome.PLAYER_WIN:
			wins += 1
		ticks.append(state.tick)
		for e in state.events:
			var u := state.unit(e.source_id)
			if u == null or u.pawn == null:
				continue
			if e.kind == CG.EventKind.ACTION_FIRE:
				fired[e.action_id] = int(fired.get(e.action_id, 0)) + 1
			elif e.kind == CG.EventKind.DAMAGE:
				damage += e.amount
			elif e.kind == CG.EventKind.HEAL:
				healed += e.amount
	ticks.sort()
	print("")
	print("%s x4%s: win %d/%d  ticks median %d  pawn damage %d  pawn healing %d" % [
		class_id, "  (presets)" if presets else "", wins, SEEDS,
		ticks[ticks.size() / 2], damage, healed,
	])
	var keys := fired.keys()
	keys.sort()
	for k in keys:
		print("   %-22s %d" % [k, fired[k]])
