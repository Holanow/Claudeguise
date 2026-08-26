extends SceneTree

## Issue 625: how often does a ranged pawn have a line to nothing at all?
##
## Issue 481 was *"a pawn that reaches cover with nothing to do there wins 0 of
## 20"*. Bodies blocking sight brings that back at scale: a ranged pawn behind
## its own frontline has no legal target, `_action_can_fire` rejects every row
## in silence, and the pawn looks broken. If this number is large the fix is an
## **authored movement row that seeks a firing line, never a hidden rule.**
##
## SAMPLES BEFORE `step()`, per ENGINEER.md. Reads positions and asks the grid;
## never calls `decide`, so it draws nothing from `state.rng` and writes no
## `focus_id`. Run `-- verify` to re-run every fight unprobed and confirm the
## outcomes and tick counts did not move.

const SEEDS := 6
const ROOMS := [&"floor1_cover", &"floor1_chokepoint", &"floor1_hazard", &"floor1_horde"]
const PARTY := [&"geysermancer", &"siege_master", &"priest", &"warrior"]

## A pawn counts as ranged when its longest sighted action outreaches this.
## Below it the pawn is walking into contact anyway and a blocked line is not
## what stops it.
const RANGED_MIN := 120.0

func _initialize() -> void:
	if OS.get_cmdline_user_args().size() > 0:
		_verify()
		return
	print("ticks a living ranged pawn had NO line to any living enemy in range")
	print("%-22s %10s %12s %12s %10s" % [
		"room", "pawn-ticks", "no line", "terrain only", "bodies"])
	var t_all := 0
	var t_none := 0
	var t_terrain := 0
	for room in ROOMS:
		var r := _measure(room)
		t_all += r[0]
		t_none += r[1]
		t_terrain += r[2]
		_row(String(room), r[0], r[1], r[2])
	print("")
	_row("ALL THREE", t_all, t_none, t_terrain)
	quit(0)

func _row(label: String, all: int, none: int, terrain_only: int) -> void:
	var d := float(maxi(1, all))
	print("%-22s %10d %7d %4.1f%% %7d %4.1f%% %6d %4.1f%%" % [
		label, all,
		none, 100.0 * float(none) / d,
		terrain_only, 100.0 * float(terrain_only) / d,
		none - terrain_only, 100.0 * float(none - terrain_only) / d])

## Returns [ranged pawn-ticks, no line at all, no line from terrain alone].
## The terrain-only arm excludes every unit body from the ray, so the same
## fight yields the before-number and the after-number with no second run and
## no perturbation at all.
func _measure(room: StringName) -> Array:
	var all := 0
	var none := 0
	var terrain_only := 0
	for s in SEEDS:
		var state := CombatSim.build(_party(), Registry.get_encounter(room), s, SimDeps.new())
		var every_id: Array[int] = []
		for u in state.units:
			every_id.append(u.id)
		while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
			for u in state.units:
				if not u.alive:
					continue
				var reach := _sighted_reach(u)
				if reach < RANGED_MIN:
					continue
				all += 1
				if not _has_line(state, u, reach, [u.id]):
					none += 1
				if not _has_line(state, u, reach, every_id):
					terrain_only += 1
			CombatSim.step(state)
	return [all, none, terrain_only]

## True when some living enemy is inside `reach` and the grid gives a line to
## it. The target is excluded from the ray, as `CombatSim` excludes it: hitting
## the thing you aimed at is success, not obstruction.
func _has_line(state: CombatState, u: CombatUnit, reach: float, ignore: Array[int]) -> bool:
	for foe in state.living(_other(u.team)):
		if u.position.distance_to(foe.position) > reach:
			continue
		var mask: Array[int] = ignore.duplicate()
		if not mask.has(foe.id):
			mask.append(foe.id)
		if not state.grid.sight_blocked(u.position, foe.position, mask):
			return true
	return false

## The longest range among the unit's actions that need a line at all. An
## action that needs no line is not evidence the pawn can see anything.
func _sighted_reach(u: CombatUnit) -> float:
	var best := 0.0
	for id in u.actions:
		var a := Registry.get_action(id)
		if a != null and a.requires_line_of_sight:
			best = maxf(best, a.range_units)
	return best

func _other(team: CG.Team) -> CG.Team:
	return CG.Team.ENEMY if team == CG.Team.PLAYER else CG.Team.PLAYER

func _party() -> Array[PawnData]:
	var out: Array[PawnData] = []
	for cid in PARTY:
		out.append(PawnFactory.make_starter_pawn(cid, StringName("%s_p" % cid),
			Registry.get_class_def(cid).display_name))
	return out

## The step ENGINEER.md says almost nobody does: run every fight again with the
## probe removed and confirm nothing moved.
func _verify() -> void:
	var perturbed := 0
	for room in ROOMS:
		for s in SEEDS:
			var a := CombatSim.build(_party(), Registry.get_encounter(room), s, SimDeps.new())
			CombatSim.run(a)
			var b := CombatSim.build(_party(), Registry.get_encounter(room), s, SimDeps.new())
			while b.outcome == CombatState.Outcome.UNRESOLVED and b.tick < CG.MAX_TICKS:
				for u in b.units:
					if u.alive and _sighted_reach(u) >= RANGED_MIN:
						_has_line(b, u, _sighted_reach(u), [u.id])
				CombatSim.step(b)
			if a.outcome != b.outcome or a.tick != b.tick or a.events.size() != b.events.size():
				perturbed += 1
	print("%d perturbed of %d fights" % [perturbed, ROOMS.size() * SEEDS])
	quit(0)
