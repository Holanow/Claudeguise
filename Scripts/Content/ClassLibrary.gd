extends RefCounted
class_name ClassLibrary

## Issue 628: every class `.tres` the game ships, listed rather than scanned,
## for the reason `ActionLibrary` gives -- a `DirAccess` walk is ordered by the
## filesystem, and the registry may not be.

const PATHS: Array[String] = [
	"res://Scripts/Content/Classes/warrior.tres",
	"res://Scripts/Content/Classes/priest.tres",
	"res://Scripts/Content/Classes/geysermancer.tres",
	"res://Scripts/Content/Classes/siege_master.tres",
	"res://Scripts/Content/Classes/abomination.tres",
]
