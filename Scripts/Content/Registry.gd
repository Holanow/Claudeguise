extends RefCounted

const ClassDef := preload("res://Scripts/Core/ClassDef.gd")
const ActionDef := preload("res://Scripts/Core/ActionDef.gd")
const EnemyDef := preload("res://Scripts/Core/EnemyDef.gd")
const Encounter := preload("res://Scripts/Core/Encounter.gd")
const EquipmentDef := preload("res://Scripts/Core/EquipmentDef.gd")

## The composition root, split. Every class, action, enemy and encounter lives
## in its own file under Scripts/Content/, and this file only composes them.
##
## OWNER: teal.
##
## The rule that makes this shape worth having: adding content is a new file
## plus one line here, never surgery inside a block somebody else is editing.
## When a second content session exists, split MODULES per session before
## anything else. A registry that is a literal list everyone edits in place is
## the worst conflict site a repository can have.
##
## Each module script exposes:
##
##   static func classes() -> Array[ClassDef]
##   static func actions() -> Array[ActionDef]
##   static func enemies() -> Array[EnemyDef]
##   static func encounters() -> Array[Encounter]
##   static func items() -> Array[EquipmentDef]
##
## Any of them may return an empty array.

const MODULES: Array = [
	preload("res://Scripts/Content/Modules/core_actions.gd"),
	preload("res://Scripts/Content/Modules/starting_classes.gd"),
	preload("res://Scripts/Content/Modules/floor1_enemies.gd"),
	preload("res://Scripts/Content/Modules/floor1_encounters.gd"),
	preload("res://Scripts/Content/Modules/core_items.gd"),
	## Issue 19: rooms kite's level editor saved to disk. Kept last so a
	## hand-authored room can never win an id collision against a
	## hand-written encounter registered above it -- `_register` already
	## rejects the second registration of any id with a loud error, and
	## iteration order over `MODULES` decides which one is "first".
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
static func all_class_ids() -> Array[StringName]:
	_load()
	var ids: Array[StringName] = []
	for k in _classes.keys():
		ids.append(k)
	ids.sort()
	return ids

static func all_encounter_ids() -> Array[StringName]:
	_load()
	var ids: Array[StringName] = []
	for k in _encounters.keys():
		ids.append(k)
	ids.sort()
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
	ids.sort()
	return ids

static func all_equipment_ids() -> Array[StringName]:
	_load()
	var ids: Array[StringName] = []
	for k in _items.keys():
		ids.append(k)
	ids.sort()
	return ids
