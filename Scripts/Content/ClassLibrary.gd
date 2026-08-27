extends RefCounted
class_name ClassLibrary

## Issue 628: every class `.tres` the game ships, listed rather than scanned,
## for the reason `ActionLibrary` gives -- a `DirAccess` walk is ordered by the
## filesystem, and the registry may not be.

const PATHS: Array[String] = [
	"res://Scripts/Content/Classes/warrior.tres",
	"res://Scripts/Content/Classes/priest.tres",
	"res://Scripts/Content/Classes/geysermancer.tres",
	"res://Scripts/Content/Classes/siege_master.tres",
	"res://Scripts/Content/Classes/abomination.tres",
]

## Same rule as `Registry._sort_ids`: sorted by id, because dictionary/array
## iteration order is not something a fight may depend on. Issue #658 lever 3A.
static func all_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for path in PATHS:
		var c: ClassDef = load(path)
		ids.append(c.id)
	ids.sort_custom(func(a: StringName, b: StringName) -> bool:
		return String(a) < String(b))
	return ids
