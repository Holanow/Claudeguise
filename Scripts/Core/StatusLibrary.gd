extends RefCounted
class_name StatusLibrary

## The `CG.Status` -> `StatusDef` lookup. Listed rather than scanned, for the
## reason `ActionLibrary` gives: a `DirAccess` walk is ordered by the
## filesystem and nothing in a deterministic simulation may depend on that.
##
## Loaded lazily, on the first lookup. Not at class init: a `static var`
## initialiser runs while the script loads, and loading a resource there runs
## inside the headless import pass the gate depends on.

const PATHS: Array[String] = [
	"res://Scripts/Core/Statuses/shield.tres",
	"res://Scripts/Core/Statuses/bleed.tres",
	"res://Scripts/Core/Statuses/taunted.tres",
	"res://Scripts/Core/Statuses/burn.tres",
	"res://Scripts/Core/Statuses/haste.tres",
	"res://Scripts/Core/Statuses/stun.tres",
	"res://Scripts/Core/Statuses/block.tres",
	"res://Scripts/Core/Statuses/marked.tres",
	"res://Scripts/Core/Statuses/poison.tres",
	"res://Scripts/Core/Statuses/slowed.tres",
	"res://Scripts/Core/Statuses/taunting.tres",
	"res://Scripts/Core/Statuses/shielding.tres",
	"res://Scripts/Core/Statuses/sustaining.tres",
]

static var _defs: Dictionary = {}

static func _load() -> void:
	if not _defs.is_empty():
		return
	for path in PATHS:
		var def: StatusDef = load(path)
		if def == null:
			push_error("StatusLibrary: %s did not load" % path)
			continue
		if _defs.has(def.status):
			push_error("StatusLibrary: two defs claim %s" % CG.Status.keys()[def.status])
			continue
		_defs[def.status] = def

## The def for one status. Never null for a real `CG.Status`: a missing file is
## a defect, and an empty def would let every number silently read as zero,
## which is the failure this issue exists to make impossible.
static func of(status: CG.Status) -> StatusDef:
	_load()
	var def: StatusDef = _defs.get(status)
	if def == null:
		push_error("StatusLibrary: no def for %s" % CG.Status.keys()[status])
	return def

## Every def, in `CG.Status` order. For a test or a tool that wants to walk the
## whole set; the simulation never iterates this, because the order it ticks
## damage-over-time in is its own decision rather than the enum's.
static func all() -> Array[StatusDef]:
	_load()
	var out: Array[StatusDef] = []
	for s in CG.Status.values():
		out.append(_defs[s])
	return out
