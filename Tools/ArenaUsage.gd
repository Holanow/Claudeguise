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
##
## ---
##
## **BOUNDING BOX ONLY WAS NOT ENOUGH, and the first fresh-eyes playtest is
## what showed it.** A reader with no project context, looking at rendered
## frames:
##
##   "All combat happens in a ~250x250 blob in the upper-left of a ~795x450
##   arena. The right 40% is empty all fight."
##
## Ran against this tool, that reads as a contradiction: the box is 46% of the
## arena, which is not a corner. Both are correct. **A blob that wanders and an
## even spread that stays put have the same bounding box**, because a box is
## decided by four extreme samples and says nothing about the other thousands.
## So the tool answered "is the extent big enough" -- yes -- to a complaint
## that was never about extent.
##
## Three columns added by heron, and each answers a different half of what the
## reader actually said:
##
##   cover%   what fraction of the arena's cells EVER hold a unit. This is the
##            "right 40% is empty" claim, directly. A wandering blob scores
##            low here while its bounding box scores high.
##   blob%    at a typical tick, how far the living units stand from their own
##            centre of mass, as a fraction of the arena's half-diagonal.
##            This is "a ~250x250 blob". Small means converged.
##   at       where the fighting actually happens: the mean of every unit
##            sample, as a percentage across and down the arena. 50/50 is dead
##            centre. This is the "upper-left" claim and it is the one
##            nobody had ever checked.
##
## Same fights, same loop, one extra pass over the units already being read --
## the tool costs what it always did.
##
## **What this tool still cannot tell you** is whether a low cover% is bad. A
## fight that resolves quickly covers little ground because it is short, not
## because it is badly shaped. Read the columns beside the tick counts in
## `SampleFights`, and hold the room fixed when comparing.


const SEEDS := 10
const CLASSES := ["warrior", "priest", "abomination", "geysermancer", "siege_master"]

func _init() -> void:
	var aw := CG.ARENA_HALF_WIDTH * 2.0
	var ah := CG.ARENA_HALF_HEIGHT * 2.0
	print("arena %.0f x %.0f world units" % [aw, ah])
	print("")
	print("%-20s %7s %7s %7s %7s %7s %9s" % ["encounter", "width%", "height%", "area%", "cover%", "blob%", "at x/y%"])
	print("%-20s %7s %7s %7s %7s %7s %9s" % ["---------", "------", "-------", "-----", "------", "-----", "-------"])

	var all_w := 0.0
	var all_h := 0.0
	var all_a := 0.0
	var all_cover := 0.0
	var all_blob := 0.0
	var n := 0

	for enc_id in Registry.all_encounter_ids():
		var tw := 0.0
		var th := 0.0
		var ta := 0.0
		var tcover := 0.0
		var tblob := 0.0
		var tcx := 0.0
		var tcy := 0.0
		var runs := 0
		for left_out in CLASSES:
			for s in range(SEEDS):
				var u := _fight_usage(_party_without(left_out), enc_id, s)
				var box: Rect2 = u["box"]
				if box.size.x <= 0.0:
					continue
				tw += box.size.x / aw
				th += box.size.y / ah
				ta += (box.size.x * box.size.y) / (aw * ah)
				tcover += float(u["cover"])
				tblob += float(u["blob"])
				tcx += float(u["at_x"])
				tcy += float(u["at_y"])
				runs += 1
		if runs == 0:
			continue
		print("%-20s %7.0f%% %7.0f%% %7.0f%% %7.0f%% %7.0f%% %4.0f/%-4.0f"
			% [enc_id, 100.0 * tw / runs, 100.0 * th / runs, 100.0 * ta / runs,
				100.0 * tcover / runs, 100.0 * tblob / runs,
				100.0 * tcx / runs, 100.0 * tcy / runs])
		all_w += tw / runs
		all_h += th / runs
		all_a += ta / runs
		all_cover += tcover / runs
		all_blob += tblob / runs
		n += 1

	print("")
	print("mean across %d encounters: %.0f%% of width, %.0f%% of height, %.0f%% of area"
		% [n, 100.0 * all_w / n, 100.0 * all_h / n, 100.0 * all_a / n])
	print("mean across %d encounters: %.0f%% of the arena's cells ever hold a unit, blob %.0f%%"
		% [n, 100.0 * all_cover / n, 100.0 * all_blob / n])
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

## The arena split into cells for `cover%`. 24 x 14 over 960 x 540 world units
## is a cell of 40 x 39, which is about one unit across -- units have radius 8
## to 22. Finer than that and a cell counts less than a body; coarser and two
## units standing apart share one.
const COVER_COLS := 24
const COVER_ROWS := 14

## Everything this tool reports about one fight, from one run of it.
##
## `box`   the bounding box every unit visits, unchanged and still first.
## `cover` fraction of the COVER_COLS x COVER_ROWS cells that ever hold a
##         living unit's centre.
## `blob`  mean over ticks of the mean distance from the living units to their
##         own centroid, over the arena's half-diagonal. Per tick, not over the
##         fight: a fight where two clusters approach and merge should read as
##         converging, and a whole-fight figure would average that away.
## `at_x`  where the fighting happens, as a fraction across (0 = left edge)
## `at_y`  and down (0 = top edge), meaned over every unit sample. Weighted by
##         samples rather than by unit, so a long standoff counts for more than
##         a body that died in the first second -- which is what "where does
##         the fight happen" means.
func _fight_usage(ids: Array, enc_id: StringName, s: int) -> Dictionary:
	var party: Array[PawnData] = []
	for cid in ids:
		var c := StringName(cid)
		party.append(PawnFactory.make_starter_pawn(
			c, StringName("%s_%d" % [cid, party.size()]), Registry.get_class_def(c).display_name
		))
	var state := CombatSim.build(party, Registry.get_encounter(enc_id), s)

	var aw := CG.ARENA_HALF_WIDTH * 2.0
	var ah := CG.ARENA_HALF_HEIGHT * 2.0
	var half_diagonal := sqrt(aw * aw + ah * ah) * 0.5

	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	var seen := false
	var cells := {}
	var sum_pos := Vector2.ZERO
	var samples := 0
	var spread_total := 0.0
	var spread_ticks := 0

	while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
		CombatSim.step(state)
		var living := 0
		var centroid := Vector2.ZERO
		for u in state.units:
			if u.hp <= 0:
				continue
			seen = true
			lo.x = minf(lo.x, u.position.x)
			lo.y = minf(lo.y, u.position.y)
			hi.x = maxf(hi.x, u.position.x)
			hi.y = maxf(hi.y, u.position.y)

			# Clamped rather than skipped: a unit outside the arena is a
			# defect somewhere else and dropping it here would hide it in an
			# average instead of showing it pinned to an edge.
			var col := clampi(int((u.position.x + CG.ARENA_HALF_WIDTH) / aw * COVER_COLS), 0, COVER_COLS - 1)
			var row := clampi(int((u.position.y + CG.ARENA_HALF_HEIGHT) / ah * COVER_ROWS), 0, COVER_ROWS - 1)
			cells[row * COVER_COLS + col] = true

			sum_pos += u.position
			samples += 1
			centroid += u.position
			living += 1

		# One unit is trivially at its own centroid, so a fight decided down to
		# a single survivor would otherwise report a spread of zero and drag
		# the mean toward "blob" for the wrong reason.
		if living < 2:
			continue
		centroid /= float(living)
		var spread := 0.0
		for u in state.units:
			if u.hp <= 0:
				continue
			spread += u.position.distance_to(centroid)
		spread_total += (spread / float(living)) / half_diagonal
		spread_ticks += 1

	if not seen:
		return {"box": Rect2(), "cover": 0.0, "blob": 0.0, "at_x": 0.0, "at_y": 0.0}

	var mean_pos := sum_pos / float(maxi(1, samples))
	return {
		"box": Rect2(lo, hi - lo),
		"cover": float(cells.size()) / float(COVER_COLS * COVER_ROWS),
		"blob": spread_total / float(maxi(1, spread_ticks)),
		"at_x": (mean_pos.x + CG.ARENA_HALF_WIDTH) / aw,
		"at_y": (mean_pos.y + CG.ARENA_HALF_HEIGHT) / ah,
	}
