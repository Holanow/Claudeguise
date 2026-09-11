extends RefCounted
class_name ItemRoller

## Issue 916: turns an authored base item into a generated one. Every draw
## comes from the `RandomNumberGenerator` the caller passes, the same way
## `LootTables.roll_drop` takes one -- never from `randomize`, `shuffle` or
## `pick_random`, each of which reads the global stream and would make a run
## unreproducible.

## The player, 2026-09-10: floor 1 rolls one affix about 40% of the time and
## two about 10%, which leaves half of floor 1 rolling none. Index is the affix
## count, so this is also the rarity distribution.
const FLOOR_ONE_AFFIX_WEIGHTS: Array[float] = [0.5, 0.4, 0.1, 0.0, 0.0]

## Verbs change what a pawn does and README unlocks them deeper. Floor 1 rolls
## numbers only; nothing authored is a verb yet, so this gate is proved by a
## fixture rather than by content.
const VERB_UNLOCK_FLOOR := 2

static func unlocked(affix: AffixDef, floor_index: int) -> bool:
	if affix.kind == AffixDef.Kind.VERB:
		return floor_index >= VERB_UNLOCK_FLOOR
	return true

## Weights per floor. Only floor 1 is authored; deeper floors take its table
## until somebody has a reason to write theirs, which is not this issue.
static func affix_count_weights(floor_index: int) -> Array[float]:
	var _unused := floor_index
	return FLOOR_ONE_AFFIX_WEIGHTS

## A copy of `base` carrying rolled affixes. Never mutates `base`: the library
## hands out one shared instance of every item and a roll that wrote into it
## would change every other copy in the game.
static func roll(base: EquipmentDef, floor_index: int, rng: RandomNumberGenerator) -> EquipmentDef:
	return roll_from(base, floor_index, rng, AffixPools.for_slot(base.slot))

static func roll_from(base: EquipmentDef, floor_index: int, rng: RandomNumberGenerator,
		pool: Array[AffixDef]) -> EquipmentDef:
	var eligible: Array[AffixDef] = []
	for a in pool:
		if unlocked(a, floor_index):
			eligible.append(a)
	var count := mini(_draw_count(floor_index, rng), eligible.size())
	var rolled: Array[AffixRoll] = []
	for i in count:
		var index := rng.randi_range(0, eligible.size() - 1)
		var affix: AffixDef = eligible[index]
		eligible.remove_at(index)
		rolled.append(_draw_value(affix, base.slot, rng))
	var out: EquipmentDef = base.duplicate(true)
	out.affixes = rolled
	if not rolled.is_empty():
		out.display_name = "%s %s" % [
			EquipmentDef.rarity_name(out.rarity()), base.display_name]
	return out

## Cumulative over the weight table, so one `randf` decides the count and the
## stream advances by exactly one draw whatever the answer is.
static func _draw_count(floor_index: int, rng: RandomNumberGenerator) -> int:
	var weights := affix_count_weights(floor_index)
	var pick := rng.randf()
	var seen := 0.0
	for n in weights.size():
		seen += weights[n]
		if pick < seen:
			return n
	return 0

static func _draw_value(affix: AffixDef, slot: EquipmentDef.Slot,
		rng: RandomNumberGenerator) -> AffixRoll:
	var band := AffixPools.draw_range(affix, slot)
	var drawn := rng.randi_range(band.x, band.y)
	var roll := AffixRoll.new()
	roll.affix = affix
	roll.value = float(drawn) / 100.0 if affix.is_fraction() else float(drawn)
	return roll
