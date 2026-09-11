extends RefCounted
class_name AffixPools

## Issue 916: which affixes a slot may roll, and how large its numbers are. A
## helm rolls from its own list, not a global one.

## Ordered arrays, never dictionary keys: a roll indexes into these and the
## order has to be the same on every machine. `vital` is in every pool because
## README ranks body against ring at +HP and cannot do that unless both roll it.
## Issue 931: the verbs sit in these same lists and `ItemRoller.unlocked`
## filters them out below the verb floor, so there is no second pool to keep in
## step. A verb is placed where its sentence makes sense on the piece: a weapon
## leeches and bleeds, a shield and a helm shorten a cooldown.
const POOLS: Dictionary = {
	EquipmentDef.Slot.MAIN_HAND: [&"tempered", &"balanced", &"etched", &"keen", &"vital",
		&"thirsting", &"ravenous", &"serrated"],
	EquipmentDef.Slot.OFF_HAND: [&"reinforced", &"attuned", &"padded", &"vital",
		&"flowing", &"serrated"],
	EquipmentDef.Slot.HEAD: [&"reinforced", &"attuned", &"etched", &"padded", &"vital",
		&"flowing"],
	EquipmentDef.Slot.BODY: [&"reinforced", &"tempered", &"padded", &"vital", &"flowing"],
	EquipmentDef.Slot.ACCESSORY: [&"swift", &"attuned", &"keen", &"vital",
		&"thirsting", &"flowing", &"ravenous"],
}

## Multiplies an affix's `base_min`/`base_max`, which are written at the
## ACCESSORY scale. README ranks exactly one pair of slots -- "a body always
## beats a ring at +HP" -- and 3 against 1 makes those two bands disjoint at
## every affix here. The three slots README never ordered sit between them and
## overlap both, which is the honest reading of a document that does not rank
## them.
const SLOT_SCALE: Dictionary = {
	EquipmentDef.Slot.MAIN_HAND: 2.0,
	EquipmentDef.Slot.OFF_HAND: 2.0,
	EquipmentDef.Slot.HEAD: 2.0,
	EquipmentDef.Slot.BODY: 3.0,
	EquipmentDef.Slot.ACCESSORY: 1.0,
}

static func for_slot(slot: EquipmentDef.Slot) -> Array[AffixDef]:
	var out: Array[AffixDef] = []
	for id in POOLS.get(slot, []):
		var a := AffixLibrary.get_affix(id)
		if a != null:
			out.append(a)
	return out

static func scale_for(slot: EquipmentDef.Slot) -> float:
	return float(SLOT_SCALE.get(slot, 1.0))

## The inclusive range this affix rolls in this slot, in the units it is drawn
## in: whole points for an attribute or a life roll, hundredths for a fraction.
static func draw_range(affix: AffixDef, slot: EquipmentDef.Slot) -> Vector2i:
	var scale := scale_for(slot)
	var unit := 100.0 if affix.is_fraction() else 1.0
	return Vector2i(
		int(round(affix.base_min * scale * unit)),
		int(round(affix.base_max * scale * unit)))
