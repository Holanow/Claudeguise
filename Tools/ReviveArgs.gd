extends RefCounted
class_name ReviveArgs

## Issue 802: reads the revive cadence and returning-health knobs off the
## command line so one build measures every configuration in the sweep,
## rather than a hand edit between runs.
##
##   ... --script res://Tools/FloorRuns.gd -- --revive-every 3 --revive-hp 0.25
##
## Returns the line the tool prints, so every report says which configuration
## produced it. Absent arguments leave FloorRun's shipped defaults alone.
static func apply() -> String:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--revive-every" and i + 1 < args.size():
			FloorRun.REVIVE_EVERY_N_ROOMS = int(args[i + 1])
		elif args[i] == "--revive-hp" and i + 1 < args.size():
			FloorRun.REVIVE_AT_HP_FRACTION = float(args[i + 1])
	if FloorRun.REVIVE_EVERY_N_ROOMS <= 0:
		return "revive: never"
	return "revive: every %d room(s), returning at %d%% of max hp" % [
		FloorRun.REVIVE_EVERY_N_ROOMS, int(round(100.0 * FloorRun.REVIVE_AT_HP_FRACTION))]
