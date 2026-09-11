extends SceneTree

## Issue 764: where the Siege Engine's bolts go. `Tools/DamageLedgerReport.gd`'s
## floor run over four seeds, counting bolt casts, projectiles created,
## projectiles resolved, damage events and each miss's reason, beside the ticks
## an engine and a marked enemy existed at the same time. Reads `state.events`,
## unit and projectile fields only; it never calls `decide`.

const SEEDS := 4
const BOLT := &"siege_engine_bolt"
const SHOT := &"siege_master_shot"

func _init() -> void:
	var party: Array[PawnData] = []
	for cid in ClassLibrary.all_ids():
		var c := StringName(cid)
		party.append(PawnFactory.make_preset_pawn(c, c, ClassLibrary.get_class_def(c).display_name))

	var tally := {
		"fires": 0, "starts": 0, "created": 0, "resolved": 0,
		"damage_events": 0, "damage_total": 0, "blocked": 0,
		"miss_target_dead": 0, "miss_lead": 0, "miss_sight": 0, "miss_other": 0,
		"in_flight_at_end": 0, "flight_ticks": 0, "flight_units": 0.0,
		"lead_error": 0.0,
		"engines_built": 0, "engine_alive_ticks": 0, "marked_ticks": 0,
		"engine_and_marked_ticks": 0, "raw": 0, "mitigated": 0, "fire_misses": 0,
		"master_could_mark": 0,
	}
	var ledgers: Array = []
	for s in SEEDS:
		print("== seed %d ==" % s)
		ledgers.append_array(_floor_run(party, s, tally))
	_print(DamageLedger.merge(ledgers), tally)
	quit(0)

## One floor run, the same construction `Tools/DamageLedgerReport.gd` uses.
func _floor_run(party: Array[PawnData], seed_value: int, tally: Dictionary) -> Array:
	var room_ids := FloorWalk.default_order(FloorGenerator.generate(seed_value))
	var run := FloorRun.new()
	var ledgers: Array = []
	for i in room_ids.size():
		var room_id: StringName = room_ids[i]
		var state := CombatSim.build(party, RoomLibrary.get_room(room_id), hash([seed_value, room_id, i]))
		FloorRun.carry_into(run, state, party)
		print("-- room %d/%d: %s --" % [i + 1, room_ids.size(), String(room_id)])
		_run_and_count(state, tally)
		for j in party.size():
			var unit := state.unit(j)
			run.record_result(party[j].id, unit.hp, unit.resource, unit.alive)
		ledgers.append(DamageLedger.build(state))
		if state.outcome != CombatState.Outcome.PLAYER_WIN:
			break
	return ledgers

## One fight, stepped rather than `CombatSim.run`, so a projectile can be read
## on the tick it resolves.
func _run_and_count(state: CombatState, tally: Dictionary) -> void:
	var classified := {}
	var seen_events := 0
	var marks := PackedStringArray()
	var had_engine := false
	var had_mark := false
	while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
		## Sampled BEFORE the step: a unit that dies inside the tick reads as
		## gone once `step` has returned.
		var engines := 0
		for u in state.units:
			if u.alive and u.enemy_id == &"siege_engine":
				engines += 1
		var marked := 0
		for u in state.living(CG.Team.ENEMY):
			if u.has_status(CG.Status.MARKED):
				marked += 1
		if engines > 0:
			tally.engine_alive_ticks += 1
		if marked > 0:
			tally.marked_ticks += 1
		if engines > 0 and marked > 0:
			tally.engine_and_marked_ticks += 1
		if engines > 0 and _master_could_mark(state):
			tally.master_could_mark += 1
		if (engines > 0) != had_engine:
			had_engine = engines > 0
			marks.append("engine%s@%d" % ["+" if had_engine else "-", state.tick])
		if (marked > 0) != had_mark:
			had_mark = marked > 0
			marks.append("mark%s@%d" % ["+" if had_mark else "-", state.tick])
		CombatSim.step(state)
		for i in range(seen_events, state.events.size()):
			var e := state.events[i]
			if e.kind == CG.EventKind.SUMMONED:
				var summoned := state.unit(e.target_id)
				if summoned != null and summoned.enemy_id == &"siege_engine":
					tally.engines_built += 1
			if e.action_id != BOLT:
				continue
			match e.kind:
				CG.EventKind.ACTION_FIRE: tally.fires += 1
				CG.EventKind.ACTION_START: tally.starts += 1
				CG.EventKind.BLOCKED: tally.blocked += 1
				CG.EventKind.MISS: tally.fire_misses += 1
				CG.EventKind.DAMAGE:
					tally.damage_events += 1
					tally.damage_total += e.amount
					tally.raw += e.amount_before_mitigation
					tally.mitigated += e.amount_after_mitigation
		seen_events = state.events.size()
		for p in state.projectiles:
			if p.action_id != BOLT or classified.has(p.id):
				continue
			if not p.resolved:
				continue
			classified[p.id] = true
			_classify(state, p, tally)
	for p in state.projectiles:
		if p.action_id == BOLT:
			tally.created += 1
			if not p.resolved:
				tally.in_flight_at_end += 1
	if marks.size() > 0:
		print("  %s" % " ".join(marks))

## Whether the Siege Master is free, can pay for `spotter_mark` and has an
## enemy inside the reach its plan row is gated on. Asked without calling
## `decide`, the way `Tools/EngineProbe.gd` asks it.
func _master_could_mark(state: CombatState) -> bool:
	for u in state.units:
		if not u.alive or u.pawn == null or u.pawn.pawn_class == null:
			continue
		if u.pawn.pawn_class.id != &"siege_master":
			continue
		if u.is_busy() or u.resource < 15:
			continue
		for o in state.units:
			if o.alive and o.team != u.team and o.position.distance_to(u.position) <= 350.0:
				return true
	return false

## Why one resolved bolt ended: a hit, a shield, or a miss with a reason.
func _classify(state: CombatState, p: Projectile, tally: Dictionary) -> void:
	tally.resolved += 1
	tally.flight_ticks += state.tick - p.spawn_tick
	tally.flight_units += p.origin.distance_to(p.aim_point)
	var landed := false
	for e in state.events:
		if e.tick == state.tick and e.action_id == BOLT and e.source_id == p.source_id \
				and (e.kind == CG.EventKind.DAMAGE or e.kind == CG.EventKind.BLOCKED):
			landed = true
	if landed:
		return
	var target := state.unit(p.target_id)
	if target == null or not target.alive:
		tally.miss_target_dead += 1
		return
	var gap := p.aim_point.distance_to(target.position)
	if gap > target.radius:
		tally.miss_lead += 1
		tally.lead_error += gap
		return
	if state.grid.sight_blocked(p.position, target.position):
		tally.miss_sight += 1
		return
	tally.miss_other += 1

func _print(l: DamageLedger.Ledger, t: Dictionary) -> void:
	print("\nBolt census, issue 764: %d floor runs, planned pawns, seeds 0-%d.\n" % [SEEDS, SEEDS - 1])
	var abilities: Dictionary = l.by_ability.get(CG.Team.PLAYER, {})
	var fired: Dictionary = l.fires.get(CG.Team.PLAYER, {})
	for id in [SHOT, BOLT]:
		var row: Dictionary = abilities.get(id, {"total": 0, "casts": 0})
		## The ledger's "casts" column counts DAMAGE events, not casts, so both
		## numbers are printed here beside each other.
		print("  %-20s damage %6d over %3d damage events, from %3d casts" % [
			String(id), row.total, row.casts, int(fired.get(id, {}).get("count", 0))])
	print("")
	print("  engines built                 %d" % t.engines_built)
	print("  ticks an engine was alive     %d" % t.engine_alive_ticks)
	print("  ticks an enemy was marked     %d" % t.marked_ticks)
	print("  ticks with both at once       %d" % t.engine_and_marked_ticks)
	print("  bolt casts (ACTION_FIRE)      %d" % t.fires)
	print("  bolt commits (ACTION_START)   %d" % t.starts)
	print("  projectiles created           %d" % t.created)
	print("  projectiles resolved          %d" % t.resolved)
	print("  still in flight at fight end  %d" % t.in_flight_at_end)
	print("  damage events                 %d  (%d damage)" % [t.damage_events, t.damage_total])
	print("  raw before mitigation         %d  (%d after)" % [t.raw, t.mitigated])
	print("  fires that found no target    %d" % t.fire_misses)
	print("  blocked by a shield           %d" % t.blocked)
	print("  engine alive, master could mark %d ticks" % t.master_could_mark)
	print("  missed, target died in flight %d" % t.miss_target_dead)
	print("  missed, target had moved      %d" % t.miss_lead)
	print("  missed, sight blocked         %d" % t.miss_sight)
	print("  missed, other                 %d" % t.miss_other)
	if t.resolved > 0:
		print("  mean flight  %.1f ticks, %.0f units" % [
			float(t.flight_ticks) / t.resolved, t.flight_units / t.resolved])
	if t.miss_lead > 0:
		print("  mean miss distance %.0f units against a %.0f-unit body" % [
			t.lead_error / t.miss_lead, CombatUnit.new().radius])
