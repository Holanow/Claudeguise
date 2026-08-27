extends RefCounted
class_name RoomLibrary

## The manifest of room scenes. Issue 680: hand-ordered, not a directory scan
## -- `pickable_encounter_ids` carries a player-visible order (#32).
const ROOMS: Array[PackedScene] = [
	preload("res://Scripts/Content/Rooms/floor1_room1.tscn"),
]
