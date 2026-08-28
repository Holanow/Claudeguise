extends SceneTree

## Issue 737. Headless second caller of `DamageLedger` -- one full floor run,
## planned pawns, printed to the console. The primary caller is the in-game
## end screen, `Scripts/UI/EndScreen.gd`; this exists for a sweep nobody
## wants to click through by hand. Touches nothing under `Scripts/`.

const SEED := 0

func _init() -> void:
	var class_ids := ClassLibrary.all_ids()
	if class_ids.is_empty():
		printerr("no classes registered")
		quit(1)
		return
	var party: Array[PawnData] = []
	for cid in class_ids:
		var c := StringName(cid)
		var display := ClassLibrary.get_class_def(c).display_name
		party.append(PawnFactory.make_preset_pawn(c, c, display))

	var room_ids := FloorSequence.build(SEED)
	var run := FloorRun.new()
	var ledgers: Array = []
	print("Damage ledger, issue 737: one full floor run, planned pawns, seed %d.\n" % SEED)
	for i in room_ids.size():
		var room_id: StringName = room_ids[i]
		var state := CombatSim.build(party, RoomLibrary.get_room(room_id), hash([SEED, room_id, i]))
		FloorRun.carry_into(run, state, party)
		CombatSim.run(state)
		for j in party.size():
			var unit := state.unit(j)
			run.record_result(party[j].id, unit.hp, unit.resource, unit.alive)
		print("-- room %d/%d: %s --" % [i + 1, room_ids.size(), String(room_id)])
		ledgers.append(DamageLedger.build(state))
		if state.outcome != CombatState.Outcome.PLAYER_WIN:
			print("(party wiped here; floor run stops)\n")
			break

	_print(DamageLedger.merge(ledgers))
	quit(0)

func _print(l: DamageLedger.Ledger) -> void:
	for team in [CG.Team.PLAYER, CG.Team.ENEMY]:
		var total_dealt := 0
		for dt in l.by_type.get(team, {}):
			total_dealt += l.by_type[team][dt].dealt
		print("== %s: %d total damage dealt ==" % [DamageLedger.team_name(team).to_upper(), total_dealt])
		_print_abilities(l, team, total_dealt)
		_print_dot(l, team)
		_print_types(l, team)
		print("")
	_print_mitigation(l, CG.Team.PLAYER, "YOUR")
	_print_mitigation(l, CG.Team.ENEMY, "ENEMY")

func _print_abilities(l: DamageLedger.Ledger, team: int, total_dealt: int) -> void:
	print("  by ability:")
	var ids: Array = l.by_ability.get(team, {}).keys()
	ids.sort_custom(func(a, b): return l.by_ability[team][a].total > l.by_ability[team][b].total)
	for id in ids:
		var row: Dictionary = l.by_ability[team][id]
		var per_cast: float = float(row.total) / row.casts if row.casts > 0 else 0.0
		var share: float = 100.0 * row.total / total_dealt if total_dealt > 0 else 0.0
		print("    %-28s total %6d  casts %3d  dmg/cast %6.1f  share %5.1f%%" % \
			[DamageLedger.ability_name(id), row.total, row.casts, per_cast, share])
	for zero in DamageLedger.zero_damage_fires(l, team):
		print("    STARTLING: %-24s fired %d times, 0 damage" % [zero.name, zero.fires])

func _print_dot(l: DamageLedger.Ledger, team: int) -> void:
	var ids: Array = l.by_dot.get(team, {}).keys()
	if ids.is_empty():
		return
	print("  by status (damage over time):")
	ids.sort_custom(func(a, b): return l.by_dot[team][a].total > l.by_dot[team][b].total)
	for status in ids:
		var row: Dictionary = l.by_dot[team][status]
		print("    %-28s total %6d  ticks %3d" % [CG.Status.keys()[status], row.total, row.ticks])

func _print_types(l: DamageLedger.Ledger, team: int) -> void:
	print("  by damage type (dealt / taken):")
	var ids: Array = l.by_type.get(team, {}).keys()
	ids.sort_custom(func(a, b): return String(CG.damage_type_name(a)) < String(CG.damage_type_name(b)))
	for dtype in ids:
		var row: Dictionary = l.by_type[team][dtype]
		print("    %-10s dealt %6d  taken %6d" % [CG.damage_type_name(dtype), row.dealt, row.taken])

func _print_mitigation(l: DamageLedger.Ledger, team: int, label: String) -> void:
	var m := DamageLedger.mitigation_summary(l, team)
	if m.is_empty() or m.before <= 0:
		print("== %s ARMOR: no direct hits landed on this side ==" % label)
		return
	print("== %s ARMOR (damage taken, direct hits only) ==" % label)
	print("  before mitigation: %d" % m.before)
	print("  after mitigation:  %d (removed %d, %.1f%%)" % \
		[m.after, m.before - m.after, 100.0 * (m.before - m.after) / m.before])
	print("  absorbed by raised block: %d" % m.absorbed)
	print("  applied to health (after overkill clamp): %d" % m.dealt)
	if not m.cause.is_empty():
		print("  reduction by cause:")
		for c in m.cause:
			print("    %-14s %d" % [CG.MitigationCause.keys()[c], m.cause[c]])
