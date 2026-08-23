extends RefCounted
class_name PawnFactory


## Builds a starter PawnData: class definition, starting gear, and no plan rows.

## The weapon each class starts holding. Every entry must satisfy
## `EquipmentDef.allows(class.method)` -- MARTIAL takes Sword and Bow, MAGICAL
## takes Sickle, Orb and Staff -- or the pawn is equipped with something the
## equip screen would refuse to offer it. There is a test for that.
const STARTING_WEAPON := {
	&"warrior": &"sword",
	&"priest": &"staff",
	&"geysermancer": &"orb",
	&"siege_master": &"bow",
	&"abomination": &"sickle",
}

## The armour a class starts wearing.
##
## **Issue 160: a starter pawn wearing nothing made every measurement tool in
## this repo blind to any armour-granted ability**, and there is exactly one of
## those -- `plate_mail` grants `warrior_block`. Issue 166 adds the two Mana
## casters for the same reason at one remove: the Robes carry the two points of
## WIS that pay for their Channel row.
const STARTING_ARMOR := {
	&"warrior": &"plate_mail",
	&"priest": &"robes",
	&"geysermancer": &"robes",
}

## The attributes a generated pawn rolls. **WIS is deliberately not among
## them**, on the player's ruling: *"I wouldn't randomise WIS access, give it a
## baseline and let gear improve it."* Its baseline is each class's own current
## WIS, so a generated pawn can always reach its own class library, and Robes
## and Scrubs are what buy rows past it.
const ROLLED_ATTRIBUTES: Array[CG.Attribute] = [
	CG.Attribute.STR, CG.Attribute.DEX, CG.Attribute.AGI,
	CG.Attribute.CON, CG.Attribute.INT, CG.Attribute.ATN,
]

## How much a pawn's pool may differ from its class's own total, either way.
## The player asked for "roughly the same size", so this is the roughly.
const POOL_JITTER := 2

static func make_starter_pawn(class_id: StringName, pawn_id: StringName, display_name: String) -> PawnData:
	var pawn := PawnData.new()
	pawn.id = pawn_id
	pawn.display_name = display_name
	pawn.pawn_class = Registry.get_class_def(class_id)
	if STARTING_WEAPON.has(class_id):
		pawn.weapon = Registry.get_equipment(STARTING_WEAPON[class_id])
	if STARTING_ARMOR.has(class_id):
		pawn.armor = Registry.get_equipment(STARTING_ARMOR[class_id])
	return pawn

## The same pawn with its attributes distributed from `run_seed`. Issue 485:
## a pool of points of roughly the same size per pawn, placed with a weighting
## based on class, rather than each attribute rolled on its own.
##
## **`make_starter_pawn` above is the fixed roster and is still the default.**
## Every tool and test in this repo builds pawns through it and none of them
## has to change, which is the property the issue asks for -- a tool that
## cannot pin its pawns cannot compare anything.
static func make_rolled_pawn(class_id: StringName, pawn_id: StringName, display_name: String, run_seed: int) -> PawnData:
	var pawn := make_starter_pawn(class_id, pawn_id, display_name)
	if pawn.pawn_class == null:
		return pawn
	var rng := roll_rng(run_seed, class_id)
	var weights := class_weights(pawn.pawn_class)
	var pool := maxi(1, pool_size(pawn.pawn_class) + rng.randi_range(-POOL_JITTER, POOL_JITTER))
	var placed := {}
	for i in pool:
		var a := _weighted_pick(rng, weights)
		placed[a] = int(placed.get(a, 0)) + 1
	for a in ROLLED_ATTRIBUTES:
		pawn.attribute_bonus[a] = int(placed.get(a, 0)) - pawn.pawn_class.attribute(a)
	return pawn

## What a class is weighted toward, read off its own base spread. Derived
## rather than authored beside it, for the reason `ClassDef.tags()` is: a
## second table saying what a Warrior is would drift from the first one.
static func class_weights(class_def: ClassDef) -> Dictionary:
	var out := {}
	for a in ROLLED_ATTRIBUTES:
		out[a] = maxi(0, class_def.attribute(a))
	return out

## The pool a class distributes, before jitter: its own current total across the
## rolled attributes.
##
## **"Roughly the same size" is read as per pawn across seeds, not as equal
## across classes.** Levelling every class to one shared number would move the
## Abomination from 41 points to about 30 and the Priest from 25 up, which is
## every balance number in the game at once and not a change a session makes on
## its own reading. Issue 485 says so; it is one function to change.
static func pool_size(class_def: ClassDef) -> int:
	var total := 0
	for a in ROLLED_ATTRIBUTES:
		total += maxi(0, class_def.attribute(a))
	return total

## One point, landing on an attribute with probability proportional to its
## weight. A class with 14 CON and 1 INT places fourteen times as many points
## on CON, which is what stops a Warrior rolling into a caster.
static func _weighted_pick(rng: RandomNumberGenerator, weights: Dictionary) -> CG.Attribute:
	var total := 0
	for a in ROLLED_ATTRIBUTES:
		total += int(weights[a])
	if total <= 0:
		return ROLLED_ATTRIBUTES[0]
	var roll := rng.randi_range(0, total - 1)
	for a in ROLLED_ATTRIBUTES:
		roll -= int(weights[a])
		if roll < 0:
			return a
	return ROLLED_ATTRIBUTES[ROLLED_ATTRIBUTES.size() - 1]

## One generator per class rather than one for the roster. A shared stream
## would make every pawn's roll depend on how many classes were built before
## it, so registering a sixth class would silently reroll the other five.
static func roll_rng(run_seed: int, class_id: StringName) -> RandomNumberGenerator:
	var h := run_seed & 0x7FFFFFFF
	for c in String(class_id).to_utf8_buffer():
		h = (h * 31 + int(c)) & 0x7FFFFFFF
	var rng := RandomNumberGenerator.new()
	rng.seed = h
	return rng

## The same pawn with every preset in its library added, which is the state a
## player reaches by adding all of them. Nothing in the game calls this; it is
## how a test measures authored behaviour now that a starter pawn has none.
static func make_preset_pawn(class_id: StringName, pawn_id: StringName, display_name: String) -> PawnData:
	var pawn := make_starter_pawn(class_id, pawn_id, display_name)
	pawn.plans = PresetPlans.for_class(class_id)
	return pawn
