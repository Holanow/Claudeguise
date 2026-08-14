extends SceneTree

## How much of the arena does a fight actually use?
##
##   godot --headless --path . --script res://Tools/ArenaUsage.gd
##
## MANAGER-OWNED. Not part of the game and not part of the gate.
##
## Issue 82, and the open question in issue 94. The player, looking at a
## screenshot: the room "may have to get a little bigger by the looks of it".
##
## They are reading that off a screen where the fight sits in a corner, and
## **a bigger box does not fix a fight that uses a fifth of the box** -- it
## just makes the fraction smaller. So the question is not "is the arena big
## enough" but "what does a fight actually cover", and nobody has measured it.
##
## I have already been wrong once on this issue by estimating from a
## screenshot instead of measuring: I called units "perhaps 10px across" when
## they are about 55px, an error of five times, stated as though it were a
## finding. Hence this.
##
## Samples every unit position every tick, and reports the bounding box the
## whole fight occupies as a fraction of the arena.

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")

const SEEDS := 10
const CLASSES := ["warrior", "priest", "abomination", "geysermancer", "siege_master"]

func _init() -> void:
	var aw := CG.ARENA_HALF_WIDTH * 2.0
	var ah := CG.ARENA_HALF_HEIGHT * 2.0
	print("arena %.0f x %.0f world units" % [aw, ah])
	print("")
	print("%-20s %8s %8s %8s" % ["encounter", "width%", "height%", "area%"])
	print("%-20s %8s %8s %8s" % ["---------", "------", "-------", "-----"])

	var all_w := 0.0
	var all_h := 0.0
	var all_a := 0.0
	var n := 0

	for enc_id in Registry.all_encounter_ids():
		var tw := 0.0
		var th := 0.0
		var ta := 0.0
		var runs := 0
		for left_out in CLASSES:
			for s in range(SEEDS):
				var box := _fight_box(_party_without(left_out), enc_id, s)
				if box.size.x <= 0.0:
					continue
				tw += box.size.x / aw
				th += box.size.y / ah
				ta += (box.size.x * box.size.y) / (aw * ah)
				runs += 1
		if runs == 0:
			continue
		print("%-20s %7.0f%% %7.0f%% %7.0f%%"
			% [enc_id, 100.0 * tw / runs, 100.0 * th / runs, 100.0 * ta / runs])
		all_w += tw / runs
		all_h += th / runs
		all_a += ta / runs
		n += 1

	print("")
	print("mean across %d encounters: %.0f%% of width, %.0f%% of height, %.0f%% of area"
		% [n, 100.0 * all_w / n, 100.0 * all_h / n, 100.0 * all_a / n])
	print("")
	print("Read this before changing ARENA_HALF_WIDTH/HEIGHT: if the fight")
	print("already leaves most of the arena empty, a bigger arena leaves more")
	print("of it empty. Spawn spread and terrain are what fill space.")
	quit(0)

func _party_without(left_out: String) -> Array:
	var ids: Array = []
	for c in CLASSES:
		if c != left_out:
			ids.append(c)
	return ids

## The bounding box every unit visits over the whole fight, sampled each tick.
func _fight_box(ids: Array, enc_id: StringName, s: int) -> Rect2:
	var party: Array[PawnData] = []
	for cid in ids:
		var c := StringName(cid)
		party.append(PawnFactory.make_starter_pawn(
			c, StringName("%s_%d" % [cid, party.size()]), Registry.get_class_def(c).display_name
		))
	var state := CombatSim.build(party, Registry.get_encounter(enc_id), s)

	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	var seen := false
	while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
		CombatSim.step(state)
		for u in state.units:
			if u.hp <= 0:
				continue
			seen = true
			lo.x = minf(lo.x, u.position.x)
			lo.y = minf(lo.y, u.position.y)
			hi.x = maxf(hi.x, u.position.x)
			hi.y = maxf(hi.y, u.position.y)
	if not seen:
		return Rect2()
	return Rect2(lo, hi - lo)
