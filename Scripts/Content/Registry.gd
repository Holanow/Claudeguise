extends RefCounted
class_name Registry


## The composition root, split. Every class, action, enemy and encounter lives
## in its own file under Scripts/Content/, and this file only composes them.

const MODULES: Array = [
	preload("res://Scripts/Content/Modules/core_actions.gd"),
	preload("res://Scripts/Content/Modules/floor1_enemies.gd"),
	preload("res://Scripts/Content/Modules/floor1_encounters.gd"),
	preload("res://Scripts/Content/Modules/core_items.gd"),
	preload("res://Scripts/Content/Modules/authored_rooms.gd"),
]

static var _classes: Dictionary = {}
static var _actions: Dictionary = {}
static var _enemies: Dictionary = {}
static var _encounters: Dictionary = {}
static var _items: Dictionary = {}
static var _loaded: bool = false

static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	for path in ClassLibrary.PATHS:
		var c: ClassDef = load(path)
		var bad := c.invalid_attribute_keys()
		if not bad.is_empty():
			push_error("Registry: class '%s' has attribute keys that are not attribute names: %s" % [c.id, bad])
		_register(_classes, c.id, c, "class")
	for m in MODULES:
		for c in m.classes():
			_register(_classes, c.id, c, "class")
		for a in m.actions():
			_register(_actions, a.id, a, "action")
		for e in m.enemies():
			_register(_enemies, e.id, e, "enemy")
		for e in m.encounters():
			_register(_encounters, e.id, e, "encounter")
		for i in m.items():
			_register(_items, i.id, i, "item")

static func _register(into: Dictionary, id: StringName, value: Variant, what: String) -> void:
	if id == &"":
		push_error("Registry: a %s was declared with an empty id" % what)
		return
	if into.has(id):
		push_error("Registry: two %ss share the id '%s'" % [what, id])
		return
	into[id] = value

static func get_class_def(id: StringName) -> ClassDef:
	_load()
	return _classes.get(id)

static func get_action(id: StringName) -> ActionDef:
	_load()
	return _actions.get(id)

static func get_enemy(id: StringName) -> EnemyDef:
	_load()
	return _enemies.get(id)

static func get_encounter(id: StringName) -> Encounter:
	_load()
	return _encounters.get(id)

static func get_equipment(id: StringName) -> EquipmentDef:
	_load()
	return _items.get(id)

## Ordered by id so that anything iterating content is deterministic. Dictionary
## order is not something the fight may depend on.
static func _sort_ids(ids: Array[StringName]) -> void:
	ids.sort_custom(func(a: StringName, b: StringName) -> bool:
		return String(a) < String(b))

static func all_class_ids() -> Array[StringName]:
	_load()
	var ids: Array[StringName] = []
	for k in _classes.keys():
		ids.append(k)
	_sort_ids(ids)
	return ids

static func all_encounter_ids() -> Array[StringName]:
	_load()
	var ids: Array[StringName] = []
	for k in _encounters.keys():
		ids.append(k)
	_sort_ids(ids)
	return ids

## The rooms the picker offers, in registration order. Issue #180.
static func pickable_encounter_ids() -> Array[StringName]:
	_load()
	var ids: Array[StringName] = []
	for k in _encounters.keys():
		if _encounters[k].pickable:
			ids.append(k)
	return ids

## The missing fourth sibling of all_class_ids/all_encounter_ids/
## all_equipment_ids -- every enemy this project knows about, not just
## whichever ones a hand-written encounter happens to reference. Added for
## the level editor's bestiary picker: deriving that list from encounters
## already used was correct while every enemy that existed was used
## somewhere, and wrong the moment someone registers one that isn't --
## exactly what an editor exists to let a player do.
static func all_enemy_ids() -> Array[StringName]:
	_load()
	var ids: Array[StringName] = []
	for k in _enemies.keys():
		ids.append(k)
	_sort_ids(ids)
	return ids

## Issue 100: everything a pawn can actually do -- its class's `starting_actions`
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

## Issue 93: the fifth sibling. Added because two of that issues assertions are
## about what every action in the game does NOT do -- no other action carries a
## summon cap, no other action is marked-only -- and a negative like that cannot
## be checked by naming actions by hand, which is how it would go stale the day
## someone adds one.
static func all_action_ids() -> Array[StringName]:
	_load()
	var ids: Array[StringName] = []
	for k in _actions.keys():
		ids.append(k)
	_sort_ids(ids)
	return ids

static func all_equipment_ids() -> Array[StringName]:
	_load()
	var ids: Array[StringName] = []
	for k in _items.keys():
		ids.append(k)
	_sort_ids(ids)
	return ids
