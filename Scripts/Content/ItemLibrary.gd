extends RefCounted
class_name ItemLibrary

## Issue 662: every equipment `.tres` the game ships, listed rather than
## scanned, for the reason `ActionLibrary`, `ClassLibrary` and `EnemyLibrary`
## give -- a `DirAccess` walk is ordered by the filesystem, and the registry may
## not be.
##
## Main hands, then off hands, then body, then head, then the accessory: the
## order the equip screen offers them in, and README's own floor 1 tables.

const PATHS: Array[String] = [
	"res://Scripts/Content/Items/sword.tres",
	"res://Scripts/Content/Items/mace.tres",
	"res://Scripts/Content/Items/rune_gauntlet.tres",
	"res://Scripts/Content/Items/reaper.tres",
	"res://Scripts/Content/Items/wand.tres",
	"res://Scripts/Content/Items/staff.tres",
	"res://Scripts/Content/Items/bow.tres",
	"res://Scripts/Content/Items/tower_shield.tres",
	"res://Scripts/Content/Items/standard.tres",
	"res://Scripts/Content/Items/orb.tres",
	"res://Scripts/Content/Items/book.tres",
	"res://Scripts/Content/Items/focus.tres",
	"res://Scripts/Content/Items/quiver.tres",
	"res://Scripts/Content/Items/plate_mail.tres",
	"res://Scripts/Content/Items/robes.tres",
	"res://Scripts/Content/Items/great_helm.tres",
	"res://Scripts/Content/Items/hood.tres",
	"res://Scripts/Content/Items/censer.tres",
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
		var i: EquipmentDef = load(path)
		_by_id[i.id] = i

static func get_equipment(id: StringName) -> EquipmentDef:
	_load()
	return _by_id.get(id)
