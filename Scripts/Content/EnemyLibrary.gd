extends RefCounted
class_name EnemyLibrary

## Issue 662: every enemy `.tres` the game ships, listed rather than scanned,
## for the reason `ActionLibrary` and `ClassLibrary` give -- a `DirAccess` walk
## is ordered by the filesystem, and the registry may not be.
##
## The order is the one the builders registered in, siege_engine first, because
## `core_actions` came before `floor1_enemies` in `Registry.MODULES`.

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

## Same rule as `Registry._sort_ids`: sorted by id, because dictionary/array
## iteration order is not something a fight may depend on. Issue #658 lever 3A.
static func all_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for path in PATHS:
		var e: EnemyDef = load(path)
		ids.append(e.id)
	ids.sort_custom(func(a: StringName, b: StringName) -> bool:
		return String(a) < String(b))
	return ids
