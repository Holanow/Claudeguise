extends RefCounted
class_name RoomData

## What a fight is built from. Never saved -- `RoomLoader` builds one fresh
## from a room scene every time. Issue 680.

var id: StringName = &""
var display_name: String = ""
var pickable: bool = false
var enemy_spawns: Array[Dictionary] = []
var party_spawns: Array[Vector2] = []
var cells: Dictionary = {}
