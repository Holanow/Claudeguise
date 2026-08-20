extends SceneTree

## Issue 233. What is actually *in* a pawnless tail.
##
##   godot --headless --path . --script res://Tools/TailAnatomy.gd
##   godot --headless --path . --script res://Tools/TailAnatomy.gd -- --seed 0
##
## A tail length in ticks cannot say whether the tail is a fight or dead air.
## This measures the thing that can: after the last pawn dies, how much of the
## remaining fight contains **anything the player's side does**.
##
## With `--seed N` it prints one tail second by second instead of the table.


const ENCOUNTER := &"floor1_warden"
const PARTY := ["geysermancer", "priest", "siege_master", "warrior"]
const SEEDS := 40

var _detail := -1

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seed" and i + 1 < args.size():
			_detail = int(args[i + 1])
	if _detail >= 0:
		_one(_detail)
	else:
		print("seed  tail(s)  player acts in tail  player dmg in tail  silent tail(s)  outcome")
		for s in SEEDS:
			_one(s)
	quit(0)

func _one(seed_value: int) -> void:
	var party: Array[PawnData] = []
	for cid in PARTY:
		party.append(PawnFactory.make_starter_pawn(
			StringName(cid), StringName("%s_%d" % [cid, party.size()]), String(cid)))
	var state := CombatSim.build(party, Registry.get_encounter(ENCOUNTER), seed_value)

	var last_pawn_death := -1
	var cursor := 0
	var bucket := {}
	var player_acts := 0
	var player_damage := 0
	var last_player_act_tick := -1
	while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
		CombatSim.step(state)
		if last_pawn_death < 0 and _living_pawns(state) == 0:
			last_pawn_death = state.tick
			if _detail >= 0:
				print("--- last pawn died at tick %d ---" % last_pawn_death)
				print("alive: %s" % _roster(state))
		if last_pawn_death >= 0:
			for i in range(cursor, state.events.size()):
				var e = state.events[i]
				if e.source_id >= 0 and state.units[e.source_id].team == CG.Team.PLAYER:
					match e.kind:
						CG.EventKind.ACTION_START, CG.EventKind.ACTION_FIRE:
							player_acts += 1
							last_player_act_tick = e.tick
						CG.EventKind.DAMAGE, CG.EventKind.HEAL:
							player_damage += e.amount
							last_player_act_tick = e.tick
				if _detail >= 0:
					var sec := int((e.tick - last_pawn_death) / CG.TICKS_PER_SECOND)
					if not bucket.has(sec):
						bucket[sec] = []
					bucket[sec].append(_describe(state, e))
		cursor = state.events.size()

	var tail := state.tick - last_pawn_death if last_pawn_death >= 0 else 0
	if _detail < 0:
		if last_pawn_death < 0 or tail <= 0:
			return
		# The stretch at the end of the fight in which the player's side does
		# nothing at all. This is the dead air, and it is what a tail length
		# on its own hides.
		var silent := state.tick - maxi(last_player_act_tick, last_pawn_death)
		print("%4d  %6.1f  %19d  %18d  %14.1f  %s" % [
			seed_value, float(tail) / float(CG.TICKS_PER_SECOND), player_acts, player_damage,
			float(silent) / float(CG.TICKS_PER_SECOND),
			CombatState.Outcome.keys()[state.outcome]])
		return

	print("--- fight ended tick %d, %s ---" % [
		state.tick, CombatState.Outcome.keys()[state.outcome]])
	var secs := bucket.keys()
	secs.sort()
	for sec in secs:
		var counts := {}
		for line in bucket[sec]:
			counts[line] = int(counts.get(line, 0)) + 1
		var parts: Array[String] = []
		for k in counts:
			parts.append("%s x%d" % [k, counts[k]] if counts[k] > 1 else String(k))
		print("t+%2ds: %s" % [sec, ", ".join(parts)])
	print("tail %.1fs, player acts %d, player damage %d" % [
		float(tail) / float(CG.TICKS_PER_SECOND), player_acts, player_damage])

func _describe(state, e) -> String:
	return "%s %s->%s %s%s" % [
		CG.EventKind.keys()[e.kind], _who(state, e.source_id), _who(state, e.target_id),
		String(e.action_id), (" %d" % e.amount) if e.amount != 0 else ""]

func _who(state, id: int) -> String:
	if id < 0 or id >= state.units.size():
		return "-"
	var u = state.units[id]
	return String(u.pawn.id) if u.pawn != null else String(u.enemy_id)

func _roster(state) -> String:
	var out: Array[String] = []
	for u in state.units:
		if u.alive:
			out.append("%s(%s hp %d/%d, actions %s)" % [
				String(u.pawn.id) if u.pawn != null else String(u.enemy_id),
				"P" if u.team == CG.Team.PLAYER else "E", u.hp, u.hp_max, str(u.actions)])
	return ", ".join(out)

static func _living_pawns(state) -> int:
	var n := 0
	for u in state.units:
		if u.alive and u.team == CG.Team.PLAYER and u.pawn != null:
			n += 1
	return n
