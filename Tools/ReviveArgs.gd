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

## Issue 908: a comparison arm, not a shipped rule -- the always-available
## revive the camp is measured against.
static var ONCE_ON_TWO_DOWN := true

## Issue 924: the second such arm, #802's fixed cadence. 0 is never.
static var EVERY_N_ROOMS := 0

static func apply() -> String:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--revive-every" and i + 1 < args.size():
			EVERY_N_ROOMS = int(args[i + 1])
		elif args[i] == "--revive-hp" and i + 1 < args.size():
			FloorRun.REVIVE_AT_HP_FRACTION = float(args[i + 1])
		elif args[i] == "--revive-once-on-two-down":
			ONCE_ON_TWO_DOWN = true
		elif args[i] == "--no-revive":
			ONCE_ON_TWO_DOWN = false
			EVERY_N_ROOMS = 0
	var hp := int(round(100.0 * FloorRun.REVIVE_AT_HP_FRACTION))
	if ONCE_ON_TWO_DOWN:
		return "revive: ONCE per floor (camp), held until two are down, returning at %d%% of max hp" % hp
	if EVERY_N_ROOMS <= 0:
		return "revive: never"
	return "revive: every %d room(s), returning at %d%% of max hp" % [EVERY_N_ROOMS, hp]
