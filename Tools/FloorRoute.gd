extends SceneTree

## Issue 952: why an 11-room floor logs 14 to 23 room arrivals. Replays the
## autopilot's door choice on the bare graph -- no fight, no renderer -- and
## says of every door whether a better one was available.
##
##   Tools\run.ps1 FloorRoute -ToolArgs @('--seeds','1,3,5,7,11,21,36')

const DEFAULT_SEEDS := [1, 3, 5, 7, 11, 21, 36]

func _init() -> void:
	var total_worse := 0
	for s in _seeds():
		total_worse += _replay(s)
	print("")
	print("doors where a strictly better door existed, all seeds: %d" % total_worse)
	quit(0)

func _seeds() -> Array:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--seeds")
	if at < 0 or at + 1 >= args.size():
		return DEFAULT_SEEDS
	var out: Array = []
	for part in String(args[at + 1]).split(","):
		out.append(int(part))
	return out

## One floor, walked the way `FloorAutoPilot.next_door` walks it: the first step
## of `route_to_next_fight`, one room per click. The camp branch is not replayed
## -- it needs hp -- and is counted in the real run instead.
func _replay(seed: int) -> int:
	var plan := FloorGenerator.generate(seed)
	var walk := FloorWalk.new(plan)
	print("")
	print("seed %d: %d rooms, entrance %d, boss %d, camp %d" % [
		seed, plan.rooms.size(), plan.entrance_id, plan.boss_id, plan.camp_id])
	var arrivals := 1
	var transit := 0
	var worse := 0
	var cleared_neighbour_chosen_over_fight := 0
	var boss_leg := 0
	print("  arrival %2d room %2d %-22s FIGHT (entrance)" % [
		arrivals, walk.current_id, plan.room(walk.current_id).content_id])
	walk.mark_cleared(walk.current_id)
	while not _floor_finished(walk, plan):
		var route := walk.route_to_next_fight()
		if route.is_empty():
			print("  no route out of room %d -- stopping" % walk.current_id)
			break
		var target: int = route[route.size() - 1]
		var chosen: int = route[0]
		var dist := _distances(plan, target)
		var here: int = int(dist[walk.current_id])
		var best := here
		var best_id := chosen
		for n in plan.neighbours_of(walk.current_id):
			if int(dist.get(n, 1 << 20)) < best:
				best = int(dist[n])
				best_id = n
		if best < int(dist[chosen]):
			worse += 1
			print("  BETTER DOOR: from %d chose %d (d=%d) over %d (d=%d) toward %d" % [
				walk.current_id, chosen, int(dist[chosen]), best_id, best, target])
		if walk.is_cleared(chosen):
			for n in plan.neighbours_of(walk.current_id):
				if not walk.is_cleared(n) and walk.is_fight(n) and n != chosen:
					cleared_neighbour_chosen_over_fight += 1
					print("  CLEARED OVER FRESH: from %d chose cleared %d with fresh %d adjacent" % [
						walk.current_id, chosen, n])
					break
		walk.enter(chosen)
		arrivals += 1
		var fresh := not walk.is_cleared(walk.current_id)
		if fresh:
			walk.mark_cleared(walk.current_id)
		else:
			transit += 1
			if target == plan.boss_id:
				boss_leg += 1
		print("  arrival %2d room %2d %-22s %s  (route to %d was %s)" % [
			arrivals, walk.current_id, plan.room(walk.current_id).content_id,
			"FIGHT" if fresh else "transit", target, str(route)])
	print("  seed %d: arrivals %d = %d fights + %d transit (%d of it the walk back to the boss); better doors %d; turned away from an adjacent boss %d" % [
		seed, arrivals, arrivals - transit, transit, boss_leg, worse,
		cleared_neighbour_chosen_over_fight])
	return worse

## `BattleView._floor_finished`: the floor ends on the boss, not on every room.
func _floor_finished(walk: FloorWalk, plan: FloorPlan) -> bool:
	if plan.boss_id < 0:
		return walk.is_floor_cleared()
	return walk.is_cleared(plan.boss_id)

## Room id -> steps to `target` over grid adjacency, breadth-first.
func _distances(plan: FloorPlan, target: int) -> Dictionary:
	var out := {target: 0}
	var queue: Array[int] = [target]
	var head := 0
	while head < queue.size():
		var at: int = queue[head]
		head += 1
		for n in plan.neighbours_of(at):
			if out.has(n):
				continue
			out[n] = int(out[at]) + 1
			queue.append(n)
	return out
