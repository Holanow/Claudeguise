extends RefCounted
class_name LootTables


## What drops, and how often. Issue 41's own outcome: items are loot, earned
## mid-run, not starting gear -- starting gear flattened all five real
## parties to 18-20/20 and erased the coin flips issue 37 spent the night
## building. wren's floor curve already degrades party entry health 98.7% ->
## 93.7% -> 73.8% across rooms; this is the content that answers that curve.

## A room of one of these types may drop something. Every other type (TRAP,
## LIBRARY, CELL, ordinary ENEMY) drops nothing -- README's own text names
## Treasure Rooms as where equipment is found, and BIG_ENEMY/MINIBOSS/BOSS
## are the rooms with something worth rewarding for. A plain ENEMY room is
## the floor's bread and butter and should not out-drop the room built to
## contain drops.
const DROP_CHANCE: Dictionary = {
	FloorRoom.Type.TREASURE: 1.0,
	FloorRoom.Type.BOSS: 1.0,
	FloorRoom.Type.MINIBOSS: 0.75,
	FloorRoom.Type.BIG_ENEMY: 0.35,
}

## Issue 811: a multiplier on every chance above, so the drop rate can be swept
## from the command line without editing the table. 1.0 is the shipped table and
## nothing but Tools/LootArgs.gd ever assigns this.
static var CHANCE_SCALE := 1.0

## Returns null on "nothing dropped", never an empty-but-real EquipmentDef --
## a caller that wants "did anything drop" gets to ask that directly rather
## than checking a sentinel id. `candidate_ids` narrows what may be picked;
## empty is the whole library.
static func roll_drop(room_type: FloorRoom.Type, difficulty: int, rng: RandomNumberGenerator,
		candidate_ids: Array[StringName] = [] as Array[StringName]) -> EquipmentDef:
	var chance: float = float(DROP_CHANCE.get(room_type, 0.0)) * CHANCE_SCALE
	if chance <= 0.0:
		return null
	if rng.randf() >= chance:
		return null
	return _pick_item(difficulty, rng, candidate_ids)

## No rarity tier exists on EquipmentDef yet -- every registered item is
## equally likely regardless of `difficulty`. `difficulty` is threaded
## through now (rather than added when a tier field exists) so the call
## site and the roll's own determinism don't need to change shape later;
## only this function's body would.
static func _pick_item(difficulty: int, rng: RandomNumberGenerator,
		candidate_ids: Array[StringName]) -> EquipmentDef:
	var _unused := difficulty
	var ids := candidate_ids if not candidate_ids.is_empty() else ItemLibrary.all_ids()
	if ids.is_empty():
		return null
	var index := rng.randi_range(0, ids.size() - 1)
	return ItemLibrary.get_equipment(ids[index])
