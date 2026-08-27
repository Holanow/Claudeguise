extends SceneTree

## Prints a whole fight the way a player would experience it: only what the
## screen shows, tick by tick, with nothing a viewer could not see.


const SEED := 0x2A
const ScreenSweepScript := preload("res://Tools/ScreenSweep.gd")

func _init() -> void:
	var class_ids := Registry.all_class_ids()
	var encounter_ids := Registry.all_encounter_ids()
	if class_ids.is_empty() or encounter_ids.is_empty():
		printerr("no content")
		quit(1)
		return

	## One fight per covering party, so no class is missing from the read -- an
	## alphabetical prefix of the roster never reached the Warrior (#350).
	for party_ids in ScreenSweepScript.sweep_parties(class_ids):
		_log_one_fight(party_ids)
	quit(0)

func _log_one_fight(party_ids: Array) -> void:
	var party: Array[PawnData] = []
	for cid in party_ids:
		## `make_preset_pawn`, not `make_starter_pawn`: since #399 a starter pawn
		## has no plan rows, so every player pawn in this log did nothing but
		## walk and swing and the read was of unauthored behaviour (#417).
		party.append(PawnFactory.make_preset_pawn(cid, StringName("%s" % cid), ClassLibrary.get_class_def(cid).display_name))

	var state := CombatSim.build(party, Registry.get_encounter(CG.DEFAULT_ENCOUNTER), SEED)
	CombatSim.run(state)

	print("=== fight, party %s, seed %08X, %d ticks (%.1fs) ===" % [
		", ".join(PackedStringArray(party_ids)), SEED, state.tick,
		float(state.tick) / float(CG.TICKS_PER_SECOND)
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
	print("")

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
			## A buff, a summon or a taunt raises a DAMAGE event carrying
			## nothing, and this rendered it as "Warrior hits Warrior for 0"
			## (#374). `CombatLogView` drops exactly this event; a log that
			## claims to print only what the screen shows has to as well.
			if e.amount == 0 and e.amount_before_mitigation == 0:
				return ""
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
