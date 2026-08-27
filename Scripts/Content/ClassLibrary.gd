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
		var c: ClassDef = load(path)
		_by_id[c.id] = c

static func get_class_def(id: StringName) -> ClassDef:
	_load()
	return _by_id.get(id)
