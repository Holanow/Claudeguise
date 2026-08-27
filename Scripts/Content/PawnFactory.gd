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

## The armour a class starts wearing, one entry per class on the player's
## ruling that "every class should have default dress" (issue 226).
##
## Every entry must pass `EquipmentDef.allows_class`, and the tags leave little
## room: only `gown` fits the Abomination at all, and the Siege Master's choice
## between `silk_wraps` and `gown` is settled by its primary role. There is a
## test for both the gate and the completeness of this table.
const STARTING_ARMOR := {
	&"warrior": &"plate_mail",
	&"priest": &"robes",
	&"geysermancer": &"robes",
	&"siege_master": &"silk_wraps",
	&"abomination": &"gown",
}

## The attributes a generated pawn rolls. **WIS is deliberately not among
## them**, on the player's ruling: *"I wouldn't randomise WIS access, give it a
## baseline and let gear improve it."* Its baseline is each class's own current
## WIS, so a generated pawn can always reach its own class library, and armour
## is what buys rows past it.
const ROLLED_ATTRIBUTES: Array[CG.Attribute] = [
	CG.Attribute.STR, CG.Attribute.DEX, CG.Attribute.AGI,
	CG.Attribute.CON, CG.Attribute.INT, CG.Attribute.ATN,
]

## The pool every pawn distributes, before jitter. **The same for every class**:
## classes differ in where the points land, not in how many they get.
##
## 30 is the mean of the five classes' own totals (29.8), so levelling is
## net-neutral across the roster rather than a buff or a nerf to all of it. A
## constant rather than a recomputed mean, because a sixth class must not
## silently move every existing pawn's power; a test fails if it drifts far
## from the roster it was derived from.
const POOL_SIZE := 30

## How much a pawn's pool may differ from `POOL_SIZE`, either way. The player
## asked for "roughly the same size", so this is the roughly.
const POOL_JITTER := 2

## A class's floor for an attribute, as a fraction of its own baseline: a pawn
## can lose at most half of anything that defines its class.
##
## Per class and not necessarily 1, per the ruling. It falls out low where a
## class is meant to be incapable -- a Warrior floors INT and ATN at 0 -- and
## high where identity depends on it, the same Warrior flooring CON at 7. If a
## class ever wants a floor this rule does not give, that is a per-class
## override and it should be added when there is a case for one.
const FLOOR_FRACTION := 0.5

static func make_starter_pawn(class_id: StringName, pawn_id: StringName, display_name: String) -> PawnData:
	var pawn := PawnData.new()
	pawn.id = pawn_id
	pawn.display_name = display_name
	pawn.pawn_class = ClassLibrary.get_class_def(class_id)
	if STARTING_WEAPON.has(class_id):
		pawn.weapon = ItemLibrary.get_equipment(STARTING_WEAPON[class_id])
	if STARTING_ARMOR.has(class_id):
		pawn.armor = ItemLibrary.get_equipment(STARTING_ARMOR[class_id])
	return pawn

## The same pawn with its attributes distributed from `run_seed`. Issue 485:
## one pool of the same size for every class, placed with a weighting based on
## class, over floors the class declares. Classes differ in where the points
## land, not in how many they get.
##
## **`make_starter_pawn` above is the fixed roster and is still the default.**
## Every tool and test in this repo builds pawns through it and none of them
## has to change, which is the property the issue asks for -- a tool that
## cannot pin its pawns cannot compare anything.
static func make_rolled_pawn(class_id: StringName, pawn_id: StringName, display_name: String, run_seed: int) -> PawnData:
	var pawn := make_starter_pawn(class_id, pawn_id, display_name)
	if pawn.pawn_class == null:
		return pawn
	var cls := pawn.pawn_class
	var rng := roll_rng(run_seed, class_id)
	var weights := class_weights(cls)
	var pool := maxi(floor_cost(cls), POOL_SIZE + rng.randi_range(-POOL_JITTER, POOL_JITTER))

	## The floors are handed out first and the rest is distributed freely.
	## **Pre-allocated, never clamped afterwards**, and that is the whole
	## defence against issue 484: clipping a roll at a floor pushes its mean up,
	## while starting from the floor leaves the free part unbiased.
	var placed := {}
	for a in ROLLED_ATTRIBUTES:
		placed[a] = attribute_floor(cls, a)
	for i in pool - floor_cost(cls):
		var a := _weighted_pick(rng, weights)
		placed[a] = int(placed[a]) + 1

	for a in ROLLED_ATTRIBUTES:
		pawn.attribute_bonus[a] = int(placed[a]) - cls.attribute(a)
	return pawn

## What a class is weighted toward, read off its own base spread. Derived
## rather than authored beside it, for the reason `ClassDef.tags()` is: a
## second table saying what a Warrior is would drift from the first one.
static func class_weights(class_def: ClassDef) -> Dictionary:
	var out := {}
	for a in ROLLED_ATTRIBUTES:
		out[a] = maxi(0, class_def.attribute(a))
	return out

## The lowest this class may ever have of this attribute.
static func attribute_floor(class_def: ClassDef, a: CG.Attribute) -> int:
	return floori(float(maxi(0, class_def.attribute(a))) * FLOOR_FRACTION)

## What the floors cost a class before a single point is placed freely. **A
## class with high floors has less free budget than one with low floors**,
## because the pool is levelled and the floors come out of it: the Abomination
## spends 19 of 30 and the Priest 11.
static func floor_cost(class_def: ClassDef) -> int:
	var total := 0
	for a in ROLLED_ATTRIBUTES:
		total += attribute_floor(class_def, a)
	return total

## A class's own total across the rolled attributes. Not the pool any more --
## `POOL_SIZE` is -- but it is still what the weights are read from, and the
## test that `POOL_SIZE` still resembles the roster reads it.
static func class_total(class_def: ClassDef) -> int:
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
