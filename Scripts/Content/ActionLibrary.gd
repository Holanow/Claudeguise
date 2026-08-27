extends RefCounted
class_name ActionLibrary

## Issue 621: every action `.tres` the game ships, listed rather than
## scanned. A `DirAccess` walk is ordered by the filesystem, and the
## registry may not be.

const PATHS: Array[String] = [
	"res://Scripts/Content/Actions/abomination_claw.tres",
	"res://Scripts/Content/Actions/abomination_grapple.tres",
	"res://Scripts/Content/Actions/abomination_hook.tres",
	"res://Scripts/Content/Actions/abomination_immolate.tres",
	"res://Scripts/Content/Actions/archer_shot.tres",
	"res://Scripts/Content/Actions/brute_roar.tres",
	"res://Scripts/Content/Actions/brute_slam.tres",
	"res://Scripts/Content/Actions/build_siege_engine.tres",
	"res://Scripts/Content/Actions/channel_mana.tres",
	"res://Scripts/Content/Actions/cultist_bolt.tres",
	"res://Scripts/Content/Actions/geyser_blast.tres",
	"res://Scripts/Content/Actions/geyser_cleanse.tres",
	"res://Scripts/Content/Actions/geyser_scald.tres",
	"res://Scripts/Content/Actions/geyser_spout.tres",
	"res://Scripts/Content/Actions/ghoul_maul.tres",
	"res://Scripts/Content/Actions/goblin_arrow.tres",
	"res://Scripts/Content/Actions/goblin_stab.tres",
	"res://Scripts/Content/Actions/grunt_smash.tres",
	"res://Scripts/Content/Actions/priest_bolt.tres",
	"res://Scripts/Content/Actions/priest_haste.tres",
	"res://Scripts/Content/Actions/priest_heal.tres",
	"res://Scripts/Content/Actions/priest_smite.tres",
	"res://Scripts/Content/Actions/priest_ward.tres",
	"res://Scripts/Content/Actions/rat_bite.tres",
	"res://Scripts/Content/Actions/rat_king_lash.tres",
	"res://Scripts/Content/Actions/sellsword_crescent.tres",
	"res://Scripts/Content/Actions/sellsword_seeker_bolts.tres",
	"res://Scripts/Content/Actions/sellsword_strike.tres",
	"res://Scripts/Content/Actions/siege_engine_bolt.tres",
	"res://Scripts/Content/Actions/siege_master_shot.tres",
	"res://Scripts/Content/Actions/spotter_mark.tres",
	"res://Scripts/Content/Actions/stalker_dart.tres",
	"res://Scripts/Content/Actions/stalker_mark.tres",
	"res://Scripts/Content/Actions/warden_axe.tres",
	"res://Scripts/Content/Actions/warden_chain_toss.tres",
	"res://Scripts/Content/Actions/warrior_block.tres",
	"res://Scripts/Content/Actions/warrior_execute.tres",
	"res://Scripts/Content/Actions/warrior_guard.tres",
	"res://Scripts/Content/Actions/warrior_second_wind.tres",
	"res://Scripts/Content/Actions/warrior_strike.tres",
	"res://Scripts/Content/Actions/warrior_taunt.tres",
]

## Same rule as `Registry._sort_ids`: sorted by id, because dictionary/array
## iteration order is not something a fight may depend on. Issue #658 lever 3A.
static func all_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for path in PATHS:
		var a: ActionDef = load(path)
		ids.append(a.id)
	ids.sort_custom(func(x: StringName, y: StringName) -> bool:
		return String(x) < String(y))
	return ids
