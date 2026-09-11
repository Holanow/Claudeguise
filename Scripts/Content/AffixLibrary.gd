extends RefCounted
class_name AffixLibrary

## Issue 916: every affix `.tres` the game ships, listed rather than scanned,
## for the reason `ItemLibrary` gives -- a `DirAccess` walk is ordered by the
## filesystem, and a roll may not be.

const PATHS: Array[String] = [
	"res://Scripts/Content/Affixes/tempered.tres",
	"res://Scripts/Content/Affixes/balanced.tres",
	"res://Scripts/Content/Affixes/swift.tres",
	"res://Scripts/Content/Affixes/reinforced.tres",
	"res://Scripts/Content/Affixes/etched.tres",
	"res://Scripts/Content/Affixes/attuned.tres",
	"res://Scripts/Content/Affixes/vital.tres",
	"res://Scripts/Content/Affixes/padded.tres",
	"res://Scripts/Content/Affixes/keen.tres",
]

static var _by_id: Dictionary = {}
static var _loaded: bool = false

static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	for path in PATHS:
		var a: AffixDef = load(path)
		_by_id[a.id] = a

static func get_affix(id: StringName) -> AffixDef:
	_load()
	return _by_id.get(id)

## Sorted by id, because dictionary iteration order is not something a roll may
## depend on.
static func all_ids() -> Array[StringName]:
	_load()
	var ids: Array[StringName] = []
	ids.assign(_by_id.keys())
	ids.sort_custom(func(a: StringName, b: StringName) -> bool:
		return String(a) < String(b))
	return ids
