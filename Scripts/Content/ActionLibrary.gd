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
	"res://Scripts/Content/Actions/priest_bolt.tres",
	"res://Scripts/Content/Actions/priest_haste.tres",
	"res://Scripts/Content/Actions/priest_heal.tres",
	"res://Scripts/Content/Actions/priest_smite.tres",
	"res://Scripts/Content/Actions/priest_ward.tres",
	"res://Scripts/Content/Actions/rat_bite.tres",
	"res://Scripts/Content/Actions/rat_king_eat_blood.tres",
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
	"res://Scripts/Content/Actions/warden_throw.tres",
	"res://Scripts/Content/Actions/warden_throw_impact.tres",
	"res://Scripts/Content/Actions/warrior_block.tres",
	"res://Scripts/Content/Actions/warrior_execute.tres",
	"res://Scripts/Content/Actions/warrior_guard.tres",
	"res://Scripts/Content/Actions/warrior_second_wind.tres",
	"res://Scripts/Content/Actions/warrior_strike.tres",
	"res://Scripts/Content/Actions/warrior_taunt.tres",
]

## Sorted by id, because dictionary iteration order is not something a fight
## may depend on. Issue #658 lever 3A.
static func all_ids() -> Array[StringName]:
	_load()
	var ids: Array[StringName] = []
	ids.assign(_by_id.keys())
	ids.sort_custom(func(a: StringName, b: StringName) -> bool:
		return String(a) < String(b))
	return ids
static var _by_id: Dictionary = {}
static var _loaded: bool = false

static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	for path in PATHS:
		var a: ActionDef = load(path)
		_by_id[a.id] = a

static func get_action(id: StringName) -> ActionDef:
	_load()
	return _by_id.get(id)

## Issue 100: everything a pawn can actually do -- its class's `starting_actions`
## plus whatever its equipment grants. Moved off `Registry` in #658; it was
## never a registry lookup, just habitually parked on one.
static func actions_for_pawn(pawn: PawnData) -> Array[StringName]:
	var out: Array[StringName] = []
	if pawn == null:
		return out
	if pawn.pawn_class != null:
		for a in pawn.pawn_class.starting_action_ids():
			if not out.has(a):
				out.append(a)
	for e in pawn.equipment():
		for a in e.granted_actions:
			if not out.has(a):
				out.append(a)
	return out
