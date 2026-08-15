extends SceneTree

## Issue 113. Is a cooldown a thing worth drawing?
##
##   godot --headless --path . --script res://Tools/CooldownLoad.gd
##
## OWNER: wren. Not part of the game and not part of the gate.
##
## The issue calls cooldowns "the most valuable quarter" of the request, on the
## grounds that they are shown nowhere at all. That is true and it is not the
## same claim as "a player would see one". **A panel showing a cooldown that is
## never on, or always on, is furniture in one session** -- the same failure the
## board's rule about detectors records.
##
## So, before drawing anything: how many of a pawn's actions even HAVE a
## cooldown, what fraction of a pawn's living ticks is spent with at least one
## action unavailable for that reason, and how long a real cooldown lasts in
## seconds a player could read off a bar.

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const PartySelect := preload("res://Scripts/UI/PartySelect.gd")

const SEEDS := 10

func _init() -> void:
	print("=== issue 113: is a cooldown worth drawing? ===")
	print("")
	print("-- every registered action that has one --")
	var with_cd := 0
	var total := 0
	for id in Registry.all_action_ids():
		var a = Registry.get_action(id)
		total += 1
		if a == null or a.cooldown_ticks <= 0:
			continue
		with_cd += 1
		print("  %-28s %4d ticks (%.1fs)" % [id, a.cooldown_ticks, float(a.cooldown_ticks) / float(CG.TICKS_PER_SECOND)])
	print("  %d of %d actions carry a cooldown" % [with_cd, total])
	print("")

	## Two parties, so **every** class is sampled. The first cut took
	## `class_ids.slice(0, 4)` and silently left out the Warrior -- which owns
	## five of the eight cooldowns in the game, so the one pawn the feature is
	## most about was the one pawn not measured. Same trap `SampleFights.gd`
	## records hitting with `encounter_ids[0]`.
	var class_ids := Registry.all_class_ids()
	var parties: Array = []
	parties.append(class_ids.slice(0, mini(4, class_ids.size())))
	if class_ids.size() > 4:
		parties.append(class_ids.slice(class_ids.size() - 4))

	## Per pawn: ticks alive, ticks with at least one own action on cooldown,
	## and the most it ever had on cooldown at once. Sampled every tick of a real
	## fight by stepping the sim by hand -- `CombatSim.run` would only leave the
	## final state, and a cooldown is by definition not there at the end.
	var alive_ticks := {}
	var blocked_ticks := {}
	var worst := {}
	for room_id in PartySelect.ROOM_ORDER:
		var encounter := Registry.get_encounter(room_id)
		if encounter == null:
			continue
		for s in SEEDS:
			for party_ids in parties:
				_sample(encounter, party_ids, s, alive_ticks, blocked_ticks, worst)

	print("-- per pawn, %d rooms x %d seeds, sampled every tick --" % [PartySelect.ROOM_ORDER.size(), SEEDS])
	var names := alive_ticks.keys()
	names.sort()
	for n in names:
		var alive := int(alive_ticks[n])
		var blocked := int(blocked_ticks.get(n, 0))
		print("  %-14s %7d alive ticks, %6.2f%% with something on cooldown, most at once %d" % [
			n, alive, 100.0 * float(blocked) / maxf(1.0, float(alive)), int(worst.get(n, 0))])
	quit(0)

## One fight, sampled every tick. Stepped by hand rather than through
## `CombatSim.run`: a cooldown is by definition not present in the final state,
## so the finished fight cannot answer this question at all.
func _sample(encounter, party_ids: Array, seed_value: int,
		alive_ticks: Dictionary, blocked_ticks: Dictionary, worst: Dictionary) -> void:
	var party: Array[PawnData] = []
	for cid in party_ids:
		party.append(PawnFactory.make_starter_pawn(
			cid, StringName("%s" % cid), Registry.get_class_def(cid).display_name))
	var state := CombatSim.build(party, encounter, seed_value)
	while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
		CombatSim.step(state)
		for u in state.units:
			if not u.alive or u.pawn == null:
				continue
			var who: String = u.display_name
			alive_ticks[who] = int(alive_ticks.get(who, 0)) + 1
			var on_cd := 0
			for action_id in u.actions:
				var a = Registry.get_action(action_id)
				if a == null or a.cooldown_ticks <= 0:
					continue
				if u.cooldowns.has(action_id) and state.tick < int(u.cooldowns[action_id]):
					on_cd += 1
			if on_cd > 0:
				blocked_ticks[who] = int(blocked_ticks.get(who, 0)) + 1
			worst[who] = maxi(int(worst.get(who, 0)), on_cd)
