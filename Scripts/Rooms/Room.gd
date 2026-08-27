extends Node2D
class_name Room

## A room's scene root. Issue 680: the scene IS the room -- terrain, spawns
## and identity live in one file, read off-tree by `RoomLoader`.

@export var id: StringName = &""
@export var display_name: String = ""
@export var pickable: bool = false
