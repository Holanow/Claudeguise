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
	preload("res://Scripts/Content/Rooms/floor1_rat_king.tscn"),
	preload("res://Scripts/Content/Rooms/floor1_warden.tscn"),
]
