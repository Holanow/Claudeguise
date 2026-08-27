extends SceneTree

## Issue 495: does the state pair give #481's pawn something to do in cover?
##
## #481 measured a Geysermancer with `move_into_cover` and no ACTION block: 91%
## cover and 0 of 20 wins, with no row a player could add that named the state.
## The arms below are that measurement plus the rows the pair now makes
## writable. Reads positions, statuses and finished events only; never calls
## `decide` (issue 329), and `in_cover_from` is a pure read that touches neither
## `state.rng` nor `focus_id`. Sampling was added after the first run and moved
## nothing: same wins, same casts, same cover percentages. Every arm spends the
## same 8 plan blocks, so a difference is the rows and not the budget.

const SEEDS := 20

const PARTY: Array[StringName] = [&"geysermancer", &"priest", &"siege_master", &"warrior"]

## Arm -> how the Geysermancer's plans are rewritten. `""` leaves them alone.
const ARMS := [
	"preset, no cover row",
	"cover row, no action",
	"state pair, then Scald",
	"state pair, then Scour",
]

func _init() -> void:
	for arm in ARMS:
		var in_cover := 0
		var alive := 0
		var taken := 0
		var wins := 0
		var casts := 0
		var blocks := 0
		var shield_ticks := 0
		var ally_focus_ticks := 0
		var stale_focus_ticks := 0
		var cover_terrain := 0
		var cover_shield := 0
		var castable_terrain := 0
		var castable_shield := 0
		for seed in SEEDS:
			var party := _party(arm)
			blocks = _blocks(party[0])
			var state := CombatSim.build(party, Registry.get_encounter(&"floor1_cover"), seed, SimDeps.new())
			var me := _geysermancer(state)
			while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
				## Sampled BEFORE the step: this is the focus the condition on the
				## next decision reads, and a unit whose recovery ends inside the
				## tick reads as free afterwards.
				if me != null and me.alive:
					var focus := state.unit(me.focus_id)
					var foe_now := _nearest_foe(state, me)
					if focus != null and focus.team == me.team and focus.id != me.id:
						ally_focus_ticks += 1
					if focus != null and foe_now != null and focus.team == CG.Team.ENEMY and focus.id != foe_now.id:
						stale_focus_ticks += 1
					for ally in state.living(CG.Team.PLAYER):
						if ally.id != me.id and ally.has_status(CG.Status.SHIELDING):
							shield_ticks += 1
							break
					## Which half of `in_cover_from` is answering, and whether a
					## line-of-sight action could fire from there at all.
					if focus != null and focus.alive and PlanInterpreter.in_cover_from(state, me, me.position, focus):
						var by_terrain := state.grid.sight_blocked(focus.position, me.position)
						var can_shoot := foe_now != null and not state.grid.sight_blocked(me.position, foe_now.position)
						if by_terrain:
							cover_terrain += 1
							if can_shoot:
								castable_terrain += 1
						else:
							cover_shield += 1
							if can_shoot:
								castable_shield += 1
				CombatSim.step(state)
				if me != null and me.alive:
					alive += 1
					var foe := _nearest_foe(state, me)
					if foe != null and state.grid.sight_blocked(foe.position, me.position):
						in_cover += 1
			if state.outcome == CombatState.Outcome.PLAYER_WIN:
				wins += 1
			for e in state.events:
				if me == null:
					continue
				if e.kind == CG.EventKind.DAMAGE and e.target_id == me.id:
					taken += e.amount
				if e.source_id == me.id and e.source_plan == &"cover_act":
					casts += 1
		print("%-22s : %d blocks, %d of %d alive ticks in cover (%.1f%%), %d damage taken, %d casts from the in-cover row, %d/%d wins" % [
			arm, blocks, in_cover, alive, 100.0 * float(in_cover) / float(maxi(1, alive)), taken, casts, wins, SEEDS])
		## Which mechanism, not just which number: a shielding ally is the only
		## cover a line-of-sight action can shoot out of, and a focus that is an
		## ally or a stale enemy is the pair asking about the wrong unit.
		print("%-22s   mechanism: %d ticks with a SHIELDING ally, %d focused on an ally, %d on a stale enemy focus" % [
			"", shield_ticks, ally_focus_ticks, stale_focus_ticks])
		print("%-22s   in cover by terrain %d ticks (%d of them with a clear shot anyway), by shield %d ticks (%d with a clear shot)" % [
			"", cover_terrain, castable_terrain, cover_shield, castable_shield])
	quit(0)

func _blocks(pawn: PawnData) -> int:
	var n := 0
	for p in pawn.plans:
		n += p.block_count()
	return n

## The Geysermancer's rows, rewritten per arm. Rows are removed from the bottom
## before rows are added on top, so every arm spends the same block budget.
func _party(arm: String) -> Array[PawnData]:
	var out: Array[PawnData] = []
	for cid in PARTY:
		var pawn := PawnFactory.make_preset_pawn(cid, StringName("%s_0" % cid), String(cid))
		if cid == &"geysermancer":
			match arm:
				"cover row, no action":
					pawn.plans.remove_at(pawn.plans.size() - 1)
					pawn.plans.insert(0, _cover_plan(&"", &""))
				"state pair, then Scald":
					_swap_in_pair(pawn, &"geyser_scald", &"target_nearest_enemy")
				"state pair, then Scour":
					_swap_in_pair(pawn, &"geyser_cleanse", &"target_ally_with_harmful_status")
		out.append(pawn)
	return out

func _swap_in_pair(pawn: PawnData, action_id: StringName, targeting: StringName) -> void:
	pawn.plans.remove_at(pawn.plans.size() - 1)
	pawn.plans.remove_at(pawn.plans.size() - 1)
	pawn.plans.insert(0, _act_plan(action_id, targeting))
	pawn.plans.insert(0, _cover_plan(&"", &"self_not_in_cover"))

## Take cover from the nearest enemy, gated on `condition` when one is named.
func _cover_plan(action_id: StringName, condition: StringName) -> Plan:
	var movement := MoveIntoCoverBlock.new()
	var p := Plan.new()
	p.id = &"cover_move"
	p.display_name = "Take cover"
	p.blocks = [_targeting(&"target_nearest_enemy"), movement]
	if condition != &"":
		p.condition = _condition(condition)
	if action_id != &"":
		p.blocks.append(_action(action_id))
	return p

## The row the pair makes writable: while in cover, do this.
func _act_plan(action_id: StringName, targeting: StringName) -> Plan:
	var p := Plan.new()
	p.id = &"cover_act"
	p.display_name = "Act from cover"
	p.condition = _condition(&"self_in_cover")
	p.blocks = [_targeting(targeting), _action(action_id)]
	return p

func _condition(op: StringName) -> ConditionBlock:
	var b := BlockCatalog.condition(op)
	return b

func _targeting(op: StringName) -> TargetingBlock:
	var b := BlockCatalog.targeting(op)
	return b

func _action(action_id: StringName) -> UseActionBlock:
	var b := UseActionBlock.new()
	b.action = ActionLibrary.get_action(action_id)
	return b

func _geysermancer(state: CombatState) -> CombatUnit:
	for u in state.units:
		if u.team == CG.Team.PLAYER and u.pawn != null and u.pawn.pawn_class.id == &"geysermancer":
			return u
	return null

func _nearest_foe(state: CombatState, me: CombatUnit) -> CombatUnit:
	var best: CombatUnit = null
	var best_dist := INF
	for u in state.living(CG.Team.ENEMY):
		var d := me.position.distance_to(u.position)
		if d < best_dist:
			best_dist = d
			best = u
	return best
