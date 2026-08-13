extends SceneTree

## Prints a whole fight the way a player would experience it: only what the
## screen shows, tick by tick, with nothing a viewer could not see.
##
##   godot --headless --path . --script res://Tools/PlaytestLog.gd
##
## MANAGER-OWNED. Not part of the game and not part of the gate.
##
## This is my substitute for sitting and watching, and I want to be honest about
## what it is and is not. It reads the same `CombatEvent` stream the battle view
## reads and nothing else — no peeking at intents, no reading a unit's internal
## state — so what it prints is what a player could in principle follow. What it
## cannot tell me is whether watching it in real time is any good, which is why
## issue 11 exists and why a person is doing that part.
##
## The distinction matters because "I read the whole fight and understood it" is
## a different claim from "the fight is readable", and only one of them is
## evidence about the game.

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")

const SEED := 0x2A

func _init() -> void:
	var class_ids := Registry.all_class_ids()
	var encounter_ids := Registry.all_encounter_ids()
	if class_ids.is_empty() or encounter_ids.is_empty():
		printerr("no content")
		quit(1)
		return

	var party_ids := class_ids.slice(0, mini(4, class_ids.size()))
	var party: Array[PawnData] = []
	for cid in party_ids:
		party.append(PawnFactory.make_starter_pawn(cid, StringName("%s" % cid), String(cid)))

	var state := CombatSim.build(party, Registry.get_encounter(encounter_ids[0]), SEED)
	CombatSim.run(state)

	print("=== fight, seed %08X, %d ticks (%.1fs) ===" % [
		SEED, state.tick, float(state.tick) / float(CG.TICKS_PER_SECOND)
	])
	print("")
	_print_roster(state)
	print("")

	var last_tick := -1
	for e in state.events:
		var line := _describe(state, e)
		if line == "":
			continue
		if e.tick != last_tick:
			print("")
			print("-- tick %d (%.1fs)" % [e.tick, float(e.tick) / float(CG.TICKS_PER_SECOND)])
			last_tick = e.tick
		print("   ", line)

	print("")
	print("=== end: outcome %s ===" % _outcome_name(state.outcome))
	_print_roster(state)
	quit(0)

func _print_roster(state: CombatState) -> void:
	for u in state.units:
		print("  %-16s %-6s %4d/%-4d hp  %s" % [
			u.display_name,
			"player" if u.team == CG.Team.PLAYER else "enemy",
			u.hp, u.hp_max,
			"" if u.alive else "DEAD",
		])

func _name(state: CombatState, id: int) -> String:
	var u := state.unit(id)
	return u.display_name if u != null else "?"

func _describe(state: CombatState, e) -> String:
	match e.kind:
		CG.EventKind.FIGHT_START:
			return "the fight begins"
		CG.EventKind.FIGHT_END:
			return "the fight ends"
		CG.EventKind.ACTION_START:
			return "%s begins %s on %s" % [_name(state, e.source_id), e.action_id, _name(state, e.target_id)]
		CG.EventKind.ACTION_FIRE:
			return "%s's %s fires" % [_name(state, e.source_id), e.action_id]
		CG.EventKind.DAMAGE:
			var mit := ""
			if e.amount_before_mitigation > e.amount:
				mit = " (%d before mitigation)" % e.amount_before_mitigation
			return "%s hits %s for %d %s%s" % [
				_name(state, e.source_id), _name(state, e.target_id),
				e.amount, CG.damage_type_name(e.damage_type), mit
			]
		CG.EventKind.HEAL:
			return "%s heals %s for %d" % [_name(state, e.source_id), _name(state, e.target_id), e.amount]
		CG.EventKind.DEATH:
			return "*** %s dies ***" % _name(state, e.target_id)
		CG.EventKind.STATUS_APPLIED:
			return "%s is afflicted (%d)" % [_name(state, e.target_id), e.status]
		CG.EventKind.STATUS_EXPIRED:
			return "%s recovers (%d)" % [_name(state, e.target_id), e.status]
		CG.EventKind.RESOURCE_SPENT:
			return ""
	return ""

func _outcome_name(o: int) -> String:
	match o:
		CombatState.Outcome.PLAYER_WIN: return "PLAYER WIN"
		CombatState.Outcome.ENEMY_WIN: return "ENEMY WIN"
		CombatState.Outcome.DRAW: return "DRAW"
	return "UNRESOLVED"
