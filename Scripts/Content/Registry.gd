extends RefCounted
class_name Registry


## Rooms, and nothing else left. Classes, actions, enemies and items all moved
## to their own libraries in #658; every function that served them is gone
## because nothing calls it. This file is the last of #680's three encounter
## functions and goes when they do.

static var _rooms: Dictionary = {}
static var _loaded: bool = false

static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	for scene in RoomLibrary.ROOMS:
		var room := RoomLoader.load_room(scene)
		if room.id == &"":
			push_error("Registry: a room was declared with an empty id")
			continue
		if _rooms.has(room.id):
			push_error("Registry: two rooms share the id '%s'" % room.id)
			continue
		_rooms[room.id] = room

static func get_encounter(id: StringName) -> RoomData:
	_load()
	return _rooms.get(id)

## Sorted by id, because dictionary iteration order is not something a fight may
## depend on.
static func all_encounter_ids() -> Array[StringName]:
	_load()
	var ids: Array[StringName] = []
	ids.assign(_rooms.keys())
	ids.sort_custom(func(a: StringName, b: StringName) -> bool:
		return String(a) < String(b))
	return ids

## The rooms the picker offers, in registration order. Issue #180. That order is
## player-visible and comes from `RoomLibrary.ROOMS`.
static func pickable_encounter_ids() -> Array[StringName]:
	_load()
	var ids: Array[StringName] = []
	for k in _rooms.keys():
		if _rooms[k].pickable:
			ids.append(k)
	return ids
