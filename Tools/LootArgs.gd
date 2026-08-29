extends RefCounted
class_name LootArgs

## Issue 811: reads the drop-rate multiplier off the command line, so the drop
## table can be swept without editing it. The table itself is the player's
## decision; this exists so a sweep can show them the curve before they take it.
##
##   ... --script res://Tools/FloorRuns.gd -- --loot-scale 2.0
##
## Returns the line the tool prints, so every report says which rate produced
## it. Absent, `LootTables.CHANCE_SCALE` keeps its shipped 1.0.
static func apply() -> String:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--loot-scale" and i + 1 < args.size():
			LootTables.CHANCE_SCALE = float(args[i + 1])
	return "loot: the shipped drop table x%.2f" % LootTables.CHANCE_SCALE
