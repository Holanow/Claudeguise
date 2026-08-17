extends RefCounted

const ClassDef := preload("res://Scripts/Core/ClassDef.gd")
const ActionDef := preload("res://Scripts/Core/ActionDef.gd")
const EnemyDef := preload("res://Scripts/Core/EnemyDef.gd")
const Encounter := preload("res://Scripts/Core/Encounter.gd")
const EquipmentDef := preload("res://Scripts/Core/EquipmentDef.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")

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
## **`Array[StringName].sort()` does not sort alphabetically.** It compares
## interned pointers, so `[zebra, apple, mango]` sorts to `[mango, apple,
## zebra]` -- checked directly, not inferred. The order it produces depends on
## what interned each name first, which varies with the entry point.
##
## That mattered far beyond tidiness. `party[i]` is placed at
## `party_spawns[i]`, so the order of `all_class_ids()` decides **who stands
## where** in every fight a measurement tool builds. `SampleFights`,
## `TickBudget`, `ArenaUsage` and the test suite each build their parties
## after touching different content, so they were arranging the same party
## differently and then disagreeing about the result.
##
## That is almost certainly issue 63, an instrument disagreement open for
## days which I personally failed to explain three times -- every attempt
## assumed the two instruments were running the same fight. They were not.
## It also fits finch's separate finding that the Warden's outcome swings
## 20/20 versus 8/20 on build order alone.
##
## Found by heron while authoring rooms. Comparing as `String` is the whole
## fix; the cost is one conversion per element on lists of five to twenty.
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
##
## **Deliberately not sorted, unlike every other accessor here.** This one is
## read straight into a player-facing list, and `_sort_ids` would order the
## picker by id text rather than by the order the content is authored in. The
## module's own `encounters()` array is that order.
##
## Not a fourth source of truth: it holds no list of its own, it filters the
## flag the content sets. Whether a room is offered is decided beside the room.
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
## plus every `granted_actions` entry of every equipped piece, deduplicated, in a
## stable order (class actions first, then equipment in weapon/armor/accessory
## order).
##
## **One definition, because there were about to be three and they were already
## disagreeing.** `CombatSim._collect_player_actions` computes this union to
## decide what a unit may do in a fight. `InspectPanel._available_actions`
## computes `starting_actions` alone to decide what the player may plan with. So
## the moment an item granted an action, the fight knew about it and the plan
## editor did not -- the player could never plan the ability their armour gave
## them, which is the entire point of `granted_actions`.
##
## Lives here rather than in either caller so that neither owns the answer. It is
## `Scripts/Content` because "what can this pawn do" is a content question: it is
## the class table plus the item table and nothing else.
static func actions_for_pawn(pawn: PawnData) -> Array[StringName]:
	var out: Array[StringName] = []
	if pawn == null:
		return out
	if pawn.pawn_class != null:
		for a in pawn.pawn_class.starting_actions:
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
