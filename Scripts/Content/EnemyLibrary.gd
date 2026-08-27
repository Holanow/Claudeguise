extends RefCounted
class_name EnemyLibrary

## Issue 662: every enemy `.tres` the game ships, listed rather than scanned,
## for the reason `ActionLibrary` and `ClassLibrary` give -- a `DirAccess` walk
## is ordered by the filesystem, and the registry may not be.
##
## The order is the one the deleted builders registered in, siege_engine
## first. Kept because the fight depends on it, not because it is pretty.

const PATHS: Array[String] = [
	"res://Scripts/Content/Enemies/siege_engine.tres",
	"res://Scripts/Content/Enemies/goblin.tres",
	"res://Scripts/Content/Enemies/goblin_archer.tres",
	"res://Scripts/Content/Enemies/ghoul.tres",
	"res://Scripts/Content/Enemies/cultist.tres",
	"res://Scripts/Content/Enemies/the_warden.tres",
	"res://Scripts/Content/Enemies/brute.tres",
	"res://Scripts/Content/Enemies/stalker.tres",
	"res://Scripts/Content/Enemies/rat.tres",
	"res://Scripts/Content/Enemies/rat_king.tres",
	"res://Scripts/Content/Enemies/sellsword.tres",
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
		var e: EnemyDef = load(path)
		_by_id[e.id] = e

static func get_enemy(id: StringName) -> EnemyDef:
	_load()
	return _by_id.get(id)
