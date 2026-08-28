extends RefCounted
class_name RoomLibrary

## The manifest of room scenes. Issue 680: hand-ordered, not a directory scan
## -- `pickable_encounter_ids` carries a player-visible order (#32). Copied
## verbatim from `floor1_encounters.gd`'s own registration order.
const ROOMS: Array[PackedScene] = [
	preload("res://Scripts/Content/Rooms/floor1_room1.tscn"),
	preload("res://Scripts/Content/Rooms/floor1_horde.tscn"),
	preload("res://Scripts/Content/Rooms/floor1_ghoul_den.tscn"),
	preload("res://Scripts/Content/Rooms/floor1_cover.tscn"),
	preload("res://Scripts/Content/Rooms/floor1_hazard.tscn"),
	preload("res://Scripts/Content/Rooms/floor1_chokepoint.tscn"),
	preload("res://Scripts/Content/Rooms/floor1_sellsword.tscn"),
	preload("res://Scripts/Content/Rooms/floor1_narrows_elite.tscn"),
	preload("res://Scripts/Content/Rooms/floor1_rat_king.tscn"),
	preload("res://Scripts/Content/Rooms/floor1_warden.tscn"),
]

static var _rooms: Dictionary = {}

## `ROOMS` order, kept as ids because that order is player-visible and a
## Dictionary's is not.
static var _order: Array[StringName] = []
static var _loaded: bool = false

static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	for scene in ROOMS:
		var room := RoomLoader.load_room(scene)
		if room.id == &"":
			push_error("RoomLibrary: a room scene declares no id")
			continue
		if _rooms.has(room.id):
			push_error("RoomLibrary: two rooms share the id '%s'" % room.id)
			continue
		_rooms[room.id] = room
		_order.append(room.id)

static func get_room(id: StringName) -> RoomData:
	_load()
	return _rooms.get(id)

## Sorted by id, because dictionary iteration order is not something a fight may
## depend on.
static func all_ids() -> Array[StringName]:
	_load()
	var ids: Array[StringName] = []
	ids.assign(_rooms.keys())
	ids.sort_custom(func(a: StringName, b: StringName) -> bool:
		return String(a) < String(b))
	return ids

## The rooms the picker offers, in ROOMS order. Issue #180, and that order is
## player-visible (#32) -- never sort this one.
static func pickable_ids() -> Array[StringName]:
	_load()
	var ids: Array[StringName] = []
	for id in _order:
		if _rooms[id].pickable:
			ids.append(id)
	return ids
