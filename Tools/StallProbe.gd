extends SceneTree

## Issue 255. Reproduce the `floor1_cover` stall, then say where the units are.
##
##   godot --headless --path . --script res://Tools/StallProbe.gd -- --seeds 400
##
## finch measured 1 in 5,000 and traced the mechanism to units ending up inside
## the pillar at Rect2(20, -50, 100, 100). This finds the seeds, and for each one
## prints every living unit's position against every blocking rect, so "inside
## the pillar" is read off the fight rather than inferred.
##
## Also prints, before any fight runs, whether any authored spawn is already
## inside a blocking rect -- the cheapest explanation, and worth ruling in or out
## first.

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const Terrain := preload("res://Scripts/Core/Terrain.gd")

const ENCOUNTER := &"floor1_cover"

func _init() -> void:
	var seeds := 400
	var only_seed := -1
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seeds" and i + 1 < args.size():
			seeds = int(args[i + 1])
		if args[i] == "--seed" and i + 1 < args.size():
			only_seed = int(args[i + 1])
			seeds = only_seed + 1

	var encounter := Registry.get_encounter(ENCOUNTER)
	print("terrain on %s:" % ENCOUNTER)
	for f in encounter.terrain:
		print("  kind %d rect %s blocks_movement %s" % [f.kind, str(f.rect), str(f.blocks_movement())])

	var class_ids := Registry.all_class_ids()
	var stalls := 0
	var total := 0
	for party_ids in _parties(class_ids):
		for s in seeds:
			if only_seed >= 0 and s != only_seed:
				continue
			var party: Array[PawnData] = []
			for cid in party_ids:
				party.append(PawnFactory.make_starter_pawn(
					cid, StringName("%s_%d" % [cid, party.size()]), String(cid)))
			var state := CombatSim.build(party, encounter, s)
			if total == 0:
				_report_spawns(state)
			total += 1
			CombatSim.run(state)
			if state.tick < CG.MAX_TICKS:
				continue
			stalls += 1
			print("")
			print("STALL: %s seed %d, outcome %s, tick %d" % [
				"+".join(PackedStringArray(party_ids)), s,
				CombatState.Outcome.keys()[state.outcome], state.tick])
			for u in state.units:
				if not u.alive:
					continue
				var inside: Array[String] = []
				for f in state.terrain:
					if f.contains_point(u.position):
						inside.append("kind %d%s%s" % [f.kind,
							" blocks_movement" if f.blocks_movement() else "",
							" blocks_sight" if f.blocks_sight() else ""])
				print("  %-16s team %d pos %s radius %.0f%s  standing in: %s" % [
					String(u.pawn.id) if u.pawn != null else String(u.enemy_id),
					u.team, str(u.position), u.radius,
					"  *** INSIDE A BLOCKING RECT ***" if Terrain.point_is_blocked(
						state.terrain, u.position, u.radius) else "",
					str(inside) if not inside.is_empty() else "open floor"])
			# Whether anybody can see anybody. A deadlock is only a deadlock if
			# every pair is blocked; one open sightline would mean the stall is
			# something else and this report would be wrong.
			for a in state.units:
				if not a.alive:
					continue
				for b in state.units:
					if not b.alive or b.team == a.team:
						continue
					print("    %s -> %s: distance %.1f, sight %s" % [
						String(a.pawn.id) if a.pawn != null else String(a.enemy_id),
						String(b.pawn.id) if b.pawn != null else String(b.enemy_id),
						a.position.distance_to(b.position),
						"BLOCKED" if Terrain.line_is_blocked(
							state.terrain, a.position, b.position) else "clear"])
	print("")
	print("%d fights, %d reached CG.MAX_TICKS (%.3f%%)" % [
		total, stalls, 100.0 * float(stalls) / float(maxi(total, 1))])
	quit(0)

## The cheapest explanation, ruled in or out before anything else: a spawn point
## authored inside a wall would put a unit there on tick zero with no mechanism
## needed at all.
func _report_spawns(state) -> void:
	var bad := 0
	for u in state.units:
		if Terrain.point_is_blocked(state.terrain, u.position, u.radius):
			bad += 1
			print("SPAWN INSIDE A WALL: unit %d at %s radius %.0f" % [u.id, str(u.position), u.radius])
	print("spawns inside a blocking rect: %d of %d" % [bad, state.units.size()])

func _parties(class_ids: Array) -> Array:
	var out := []
	if class_ids.size() > 4:
		for skip in class_ids.size():
			var party := []
			for i in class_ids.size():
				if i != skip:
					party.append(class_ids[i])
			out.append(party)
	elif class_ids.size() >= 1:
		out.append(class_ids.slice(0, mini(4, class_ids.size())))
	return out
