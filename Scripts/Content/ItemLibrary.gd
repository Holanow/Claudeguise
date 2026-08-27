extends RefCounted
class_name ItemLibrary

## Issue 662: every equipment `.tres` the game ships, listed rather than
## scanned, for the reason `ActionLibrary`, `ClassLibrary` and `EnemyLibrary`
## give -- a `DirAccess` walk is ordered by the filesystem, and the registry may
## not be.
##
## Weapons, then armor, then the accessory: the order `core_items.gd` built
## them in, which is the order the equip screen offers them in.

const PATHS: Array[String] = [
	"res://Scripts/Content/Items/sword.tres",
	"res://Scripts/Content/Items/wrench.tres",
	"res://Scripts/Content/Items/sickle.tres",
	"res://Scripts/Content/Items/orb.tres",
	"res://Scripts/Content/Items/bow.tres",
	"res://Scripts/Content/Items/staff.tres",
	"res://Scripts/Content/Items/plate_mail.tres",
	"res://Scripts/Content/Items/silk_wraps.tres",
	"res://Scripts/Content/Items/robes.tres",
	"res://Scripts/Content/Items/gown.tres",
	"res://Scripts/Content/Items/censer.tres",
]
