extends SceneTree

## Issue 316: does a `move_into_cover` row actually put a pawn behind something?
##
## Two arms differing by one plan row on one pawn. Reads positions and events
## only; never calls `decide` (issue 329).

const SEEDS := 20

func _init() -> void:
	for arm in ["without the cover row", "with the cover row"]:
		var in_cover := 0
		var alive := 0
		var taken := 0
		var wins := 0
		for seed in SEEDS:
			var party := _party(arm == "with the cover row")
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
				if e.kind == CG.EventKind.DAMAGE and me != null and e.target_id == me.id:
					taken += e.amount
		print("%-24s: %d of %d alive ticks in cover (%.1f%%), %d damage taken, %d/%d wins" % [
			arm, in_cover, alive, 100.0 * float(in_cover) / float(maxi(1, alive)), taken, wins, SEEDS])
	quit(0)

## The Geysermancer gains one row above its own: take cover from the nearest
## enemy, then Scald from there.
func _party(with_cover: bool) -> Array[PawnData]:
	var out: Array[PawnData] = []
	for cid in [&"geysermancer", &"priest", &"siege_master", &"warrior"]:
		var pawn := PawnFactory.make_starter_pawn(cid, StringName("%s_0" % cid), String(cid))
		if with_cover and cid == &"geysermancer":
			## Block-equal arms. A row costs plan blocks out of the pawn's WIS
			## budget, so inserting one silently makes the bottom row inert --
			## which is a difference of budget, not of cover.
			pawn.plans.remove_at(pawn.plans.size() - 1)
			pawn.plans.insert(0, _cover_plan())
		out.append(pawn)
	return out

func _cover_plan() -> Plan:
	var targeting := PlanBlock.new()
	targeting.kind = PlanBlock.Kind.TARGETING
	targeting.op = &"target_nearest_enemy"
	var movement := PlanBlock.new()
	movement.kind = PlanBlock.Kind.MOVEMENT
	movement.op = &"move_into_cover"
	var p := Plan.new()
	p.id = &"geyser_take_cover"
	p.display_name = "Take cover"
	p.blocks = [targeting, movement]
	return p

func _geysermancer(state: CombatState) -> CombatUnit:
	for u in state.units:
		if u.pawn != null and u.pawn.pawn_class.id == &"geysermancer":
			return u
	return null

func _nearest_foe(state: CombatState, unit: CombatUnit) -> CombatUnit:
	var best: CombatUnit = null
	var best_d := INF
	for u in state.living(CG.Team.ENEMY):
		var d := unit.position.distance_to(u.position)
		if d < best_d:
			best_d = d
			best = u
	return best
