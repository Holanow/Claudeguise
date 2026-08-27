extends RefCounted


## The loader for the action library. Issue 621 moved the actions themselves out of GDScript and
## into `.tres` under `Scripts/Content/Actions/`.

## "Reaches anywhere in the room", expressed as a real number.
const ARENA_SPAN := 1200.0

static func classes() -> Array[ClassDef]:
	return []

static func actions() -> Array[ActionDef]:
	var out: Array[ActionDef] = []
	for path in ActionLibrary.PATHS:
		out.append(load(path))
	return out

static func enemies() -> Array[EnemyDef]:
	return []

static func encounters() -> Array[Encounter]:
	return []

static func items() -> Array[EquipmentDef]:
	return []
