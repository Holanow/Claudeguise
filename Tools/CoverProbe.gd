extends SceneTree

## Issue 316: does a `move_into_cover` row actually put a pawn behind something?
##
## Three arms differing by one plan row on one pawn. The Scald arm is the one
## #316's table is about and the file did not have it: the row was built with no
## ACTION block, so the probe measured "take cover and do nothing" while its own
## header said "then Scald" (#476). Reads positions and events only; never calls
## `decide` (issue 329).

const SEEDS := 20

## Arm name -> the action the cover row fires once in position, `&""` for none.
const ARMS := {
	"without the cover row": &"",
	"take cover, no action": &"",
	"take cover, then Scald": &"geyser_scald",
}

func _init() -> void:
	for arm in ARMS:
		var in_cover := 0
		var alive := 0
		var taken := 0
		var wins := 0
		for seed in SEEDS:
			var party := _party(arm != "without the cover row", ARMS[arm])
			var state := CombatSim.build(party, Registry.get_encounter(&"floor1_cover"), seed, SimDeps.new())
			var me := _geysermancer(state)
			while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
				CombatSim.step(state)
				if me != null and me.alive:
					alive += 1
					var foe := _nearest_foe(state, me)
					if foe != null and state.grid.sight_blocked(foe.position, me.position):
						in_cover += 1
			if state.outcome == CombatState.Outcome.PLAYER_WIN:
				wins += 1
			for e in state.events:
				if e.kind == CG.EventKind.DAMAGE and me != null and e.target_id == me.id:
					taken += e.amount
		print("%-24s : %d of %d alive ticks in cover (%.1f%%), %d damage taken, %d/%d wins" % [
			arm, in_cover, alive, 100.0 * float(in_cover) / float(maxi(1, alive)), taken, wins, SEEDS])
	quit(0)

## The Geysermancer gains one row above its own: take cover from the nearest
## enemy, and fire `action_id` from there once in position.
func _party(with_cover: bool, action_id: StringName) -> Array[PawnData]:
	var out: Array[PawnData] = []
	for cid in [&"geysermancer", &"priest", &"siege_master", &"warrior"]:
		## `make_preset_pawn`: since #399 a starter pawn has no plan rows, so
		## `remove_at` below ran on an empty array -- twenty out-of-bounds errors
		## a run, and arms that were not block-equal after all (#472).
		var pawn := PawnFactory.make_preset_pawn(cid, StringName("%s_0" % cid), String(cid))
		if with_cover and cid == &"geysermancer":
			## Block-equal arms. A row costs plan blocks out of the pawn's WIS
			## budget, so inserting one silently makes the bottom row inert --
			## which is a difference of budget, not of cover.
			pawn.plans.remove_at(pawn.plans.size() - 1)
			pawn.plans.insert(0, _cover_plan(action_id))
		out.append(pawn)
	return out

func _cover_plan(action_id: StringName) -> Plan:
	var targeting := TargetNearestEnemyBlock.new()
	var movement := MoveIntoCoverBlock.new()
	var p := Plan.new()
	p.id = &"geyser_take_cover"
	p.display_name = "Take cover"
	p.blocks = [targeting, movement]
	if action_id != &"":
		var action := UseActionBlock.new()
		action.action = ActionLibrary.get_action(action_id)
		p.blocks.append(action)
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
