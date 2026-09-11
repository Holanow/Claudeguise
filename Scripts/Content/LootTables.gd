extends RefCounted
class_name LootTables


## What a cleared room's chest holds. Issue 919 replaced the per-room-type drop
## chance with the player's own rate: every fight on floor 1 drops 1 to 3 items.

const MIN_ITEMS := 1
const MAX_ITEMS := 3

## Issue 919, README: weighting reads pawn scaling, not equipped gear, so a run
## does not converge on whatever the player found first. A class's tags are what
## it scales on, so a base type is weighted by how many living pawns are allowed
## it -- and this is a reading of that sentence rather than a quotation of it.
const BASELINE_WEIGHT := 1
const PER_PAWN_WEIGHT := 2

## One chest: 1 to 3 rolled pieces, at least one of them legal for a living
## pawn's class. `floor_index` is the 1-based floor and never a room difficulty
## (#916) -- passing difficulty through would open the verb tier on any
## difficulty-2 room of floor 1.
static func roll_batch(pawns: Array[PawnData], floor_index: int,
		rng: RandomNumberGenerator) -> Array[EquipmentDef]:
	var ids := ItemLibrary.all_ids()
	if ids.is_empty():
		return [] as Array[EquipmentDef]
	var out: Array[EquipmentDef] = []
	for i in rng.randi_range(MIN_ITEMS, MAX_ITEMS):
		out.append(ItemRoller.roll(_weighted_base(ids, pawns, rng), floor_index, rng))
	if not _any_usable(out, pawns):
		var usable := _usable_ids(ids, pawns)
		if not usable.is_empty():
			out[0] = ItemRoller.roll(
				ItemLibrary.get_equipment(usable[rng.randi_range(0, usable.size() - 1)]),
				floor_index, rng)
	return out

static func _weighted_base(ids: Array[StringName], pawns: Array[PawnData],
		rng: RandomNumberGenerator) -> EquipmentDef:
	var total := 0
	for id in ids:
		total += _weight(ItemLibrary.get_equipment(id), pawns)
	var roll := rng.randi_range(0, total - 1)
	for id in ids:
		roll -= _weight(ItemLibrary.get_equipment(id), pawns)
		if roll < 0:
			return ItemLibrary.get_equipment(id)
	return ItemLibrary.get_equipment(ids[ids.size() - 1])

static func _weight(item: EquipmentDef, pawns: Array[PawnData]) -> int:
	var n := 0
	for p in pawns:
		if item.allows_class(p.pawn_class):
			n += 1
	return BASELINE_WEIGHT + PER_PAWN_WEIGHT * n

static func _usable_ids(ids: Array[StringName], pawns: Array[PawnData]) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in ids:
		for p in pawns:
			if ItemLibrary.get_equipment(id).allows_class(p.pawn_class):
				out.append(id)
				break
	return out

static func _any_usable(items: Array[EquipmentDef], pawns: Array[PawnData]) -> bool:
	for item in items:
		for p in pawns:
			if item.allows_class(p.pawn_class):
				return true
	return false
