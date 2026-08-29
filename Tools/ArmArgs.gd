extends RefCounted
class_name ArmArgs

## Issue 814: which of the three closings of the five-authored/four-played gap
## a sweep is measuring, off the command line, so one build measures all three
## rather than a hand edit between runs.
##
##   ... --script res://Tools/FloorRuns.gd -- --arm 1
##
## 0 is the shipped floor and is the baseline every arm is read against.
##
## Returns the line the tool prints. Every report says which arm produced it,
## because a sweep that does not state its configuration is a number nobody
## can trust -- finch caught a `--loot-enemy` sweep silently running at 0.00
## on exactly this.
static func apply() -> String:
	var arm := 0
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--arm" and i + 1 < args.size():
			arm = int(args[i + 1])
	match arm:
		0:
			RoomScale.MODE = RoomScale.Mode.OFF
			PawnFactory.FILL_EMPTY_SLOTS = false
			return "arm 0 -- BASELINE: the shipped floor, rooms as authored, two of five slots filled"
		1:
			RoomScale.MODE = RoomScale.Mode.EVERY_ROOM
			PawnFactory.FILL_EMPTY_SLOTS = false
			return "arm 1 -- ROOMS SCALE TO PARTY SIZE: every room's count x party/%d" % \
				RoomScale.AUTHORED_PARTY_SIZE
		2:
			RoomScale.MODE = RoomScale.Mode.OUTLIER_ROOMS
			PawnFactory.FILL_EMPTY_SLOTS = false
			return "arm 2 -- FLOOR 1'S COUNTS COME DOWN: the %d-enemy rooms x party/%d, the rest authored" % \
				[RoomScale.OUTLIER_COUNT, RoomScale.AUTHORED_PARTY_SIZE]
		3:
			RoomScale.MODE = RoomScale.Mode.OFF
			PawnFactory.FILL_EMPTY_SLOTS = true
			return "arm 3 -- PAWNS START BETTER EQUIPPED: rooms as authored, off_hand and accessory filled"
		4:
			RoomScale.MODE = RoomScale.Mode.EVERY_ROOM
			PawnFactory.FILL_EMPTY_SLOTS = true
			return "arm 1+3 -- NOT ONE OF THE THREE: both together, measured because a null needs a next step"
	printerr("--arm %d: there are arms 0, 1, 2, 3 and the 1+3 pair at 4" % arm)
	return ""
