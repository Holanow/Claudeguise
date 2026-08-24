extends SceneTree

## Issue 495: does the state pair give #481's pawn something to do in cover?
##
## #481 measured a Geysermancer with `move_into_cover` and no ACTION block: 91%
## cover and 0 of 20 wins, with no row a player could add that named the state.
## The arms below are that measurement plus the rows the pair now makes
## writable. Reads positions and finished events only; never calls `decide`
## (issue 329). Every arm spends the same 8 plan blocks, so a difference is the
## rows and not the budget.

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
		for seed in SEEDS:
			var party := _party(arm)
			blocks = _blocks(party[0])
			var state := CombatSim.build(party, Registry.get_encounter(&"floor1_cover"), seed, SimDeps.new())
			var me := _geysermancer(state)
			while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
				CombatSim.step(state)
				if me != null and me.alive:
					alive += 1
					var foe := _nearest_foe(state, me)
					if foe != null and Terrain.line_is_blocked(state.terrain, foe.position, me.position):
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
	var movement := PlanBlock.new()
	movement.kind = PlanBlock.Kind.MOVEMENT
	movement.op = &"move_into_cover"
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

func _condition(op: StringName) -> PlanBlock:
	var b := PlanBlock.new()
	b.kind = PlanBlock.Kind.CONDITION
	b.op = op
	return b

func _targeting(op: StringName) -> PlanBlock:
	var b := PlanBlock.new()
	b.kind = PlanBlock.Kind.TARGETING
	b.op = op
	return b

func _action(action_id: StringName) -> PlanBlock:
	var b := PlanBlock.new()
	b.kind = PlanBlock.Kind.ACTION
	b.op = &"use_action"
	b.args = {"action_id": action_id}
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
