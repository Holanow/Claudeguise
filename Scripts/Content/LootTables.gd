extends RefCounted

const Registry := preload("res://Scripts/Content/Registry.gd")
const EquipmentDef := preload("res://Scripts/Core/EquipmentDef.gd")
const FloorRoom := preload("res://Scripts/Floor/FloorRoom.gd")

## What drops, and how often. Issue 41's own outcome: items are loot, earned
## mid-run, not starting gear -- starting gear flattened all five real
## parties to 18-20/20 and erased the coin flips issue 37 spent the night
## building. wren's floor curve already degrades party entry health 98.7% ->
## 93.7% -> 73.8% across rooms; this is the content that answers that curve.
##
## OWNER: teal.
##
## `FloorRoom` says "this is a treasure room with difficulty 3", never what it
## contains (its own doc comment). This file is the "never" half. It reads
## `FloorRoom.Type` and the room's own `difficulty` int -- both wren's shape,
## read-only here -- and returns an `EquipmentDef` or null, never touching
## `Scripts/Floor/**` itself. Wiring the call (when a room resolves, ask this
## for a drop, hand the result to the party) is wren's, same boundary as
## FloorRun's own "does not call CombatSim" rule.

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

## Returns null on "nothing dropped", never an empty-but-real EquipmentDef --
## a caller that wants "did anything drop" gets to ask that directly rather
## than checking a sentinel id.
##
## `rng` is required rather than optional and defaulting to a fresh
## generator, unlike `Balance.attack_power`'s `rng` -- there is no safe
## "no variance" reading for a drop roll the way there is for damage, and a
## fresh generator here would silently break "same seed, same floor" the
## instant a caller forgot to pass one. Pass the run's own `CombatState.rng`
## or `FloorPlan`'s own seeded generator, whichever the caller already has;
## never `RandomNumberGenerator.new()`.
static func roll_drop(room_type: FloorRoom.Type, difficulty: int, rng: RandomNumberGenerator) -> EquipmentDef:
	var chance: float = DROP_CHANCE.get(room_type, 0.0)
	if chance <= 0.0:
		return null
	if rng.randf() >= chance:
		return null
	return _pick_item(difficulty, rng)

## No rarity tier exists on EquipmentDef yet -- every registered item is
## equally likely regardless of `difficulty`. `difficulty` is threaded
## through now (rather than added when a tier field exists) so the call
## site and the roll's own determinism don't need to change shape later;
## only this function's body would.
static func _pick_item(difficulty: int, rng: RandomNumberGenerator) -> EquipmentDef:
	var _unused := difficulty
	var ids := Registry.all_equipment_ids()
	if ids.is_empty():
		return null
	var index := rng.randi_range(0, ids.size() - 1)
	return Registry.get_equipment(ids[index])
