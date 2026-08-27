extends RefCounted
class_name DamageTypeLibrary

## The `CG.DamageType` -> `DamageType` lookup. Listed rather than scanned, for
## the reason `ActionLibrary` and `StatusLibrary` both give: a `DirAccess` walk
## is ordered by the filesystem and nothing in a deterministic simulation may
## depend on that.
##
## Loaded lazily, on the first lookup. Not at class init: a `static var`
## initialiser runs while the script loads, and loading a resource there runs
## inside the headless import pass the gate depends on.

const PATHS: Array[String] = [
	"res://Scripts/Core/DamageTypes/physical.tres",
	"res://Scripts/Core/DamageTypes/fire.tres",
	"res://Scripts/Core/DamageTypes/water.tres",
	"res://Scripts/Core/DamageTypes/air.tres",
	"res://Scripts/Core/DamageTypes/earth.tres",
	"res://Scripts/Core/DamageTypes/divine.tres",
	"res://Scripts/Core/DamageTypes/profane.tres",
	"res://Scripts/Core/DamageTypes/raw.tres",
]

static var _defs: Dictionary = {}

static func _load() -> void:
	if not _defs.is_empty():
		return
	for path in PATHS:
		var def: DamageTypeDef = load(path)
		if def == null:
			push_error("DamageTypeLibrary: %s did not load" % path)
			continue
		if _defs.has(def.damage_type):
			push_error("DamageTypeLibrary: two defs claim %s" % CG.DamageType.keys()[def.damage_type])
			continue
		_defs[def.damage_type] = def

## The def for one damage type. Never null for a real `CG.DamageType`: a
## missing file is a defect, and an empty def would let a colour silently read
## as white and a name as empty, which is the failure this issue exists to make
## impossible.
static func of(damage_type: CG.DamageType) -> DamageTypeDef:
	_load()
	var def: DamageTypeDef = _defs.get(damage_type)
	if def == null:
		push_error("DamageTypeLibrary: no def for %s" % CG.DamageType.keys()[damage_type])
	return def

## Every def, in `CG.DamageType` order. For a test or a tool that wants to walk
## the whole set.
static func all() -> Array[DamageTypeDef]:
	_load()
	var out: Array[DamageTypeDef] = []
	for d in CG.DamageType.values():
		out.append(_defs[d])
	return out
