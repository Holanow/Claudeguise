extends RefCounted

const PawnData := preload("res://Scripts/Core/PawnData.gd")

## What the party select screen hands to the battle screen. Small on purpose:
## these three fields are the entire input to a fight, and that is what makes
## "change one thing and re-run" possible.
##
## MANAGER-OWNED SHAPE.

var party: Array[PawnData] = []
var encounter_id: StringName = &""
var seed: int = 0

## A seed the player can read, type back in and get the same fight from. Shown
## on the battle screen. Without this, "re-run the same fight" only works while
## the process stays alive, which is not enough to compare two tuning passes.
func seed_text() -> String:
	return "%08X" % (seed & 0xFFFFFFFF)

static func parse_seed(text: String) -> int:
	var t := text.strip_edges()
	if t.is_valid_hex_number(false) and t.length() <= 8:
		return t.hex_to_int()
	return int(hash(t))
