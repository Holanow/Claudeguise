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

## How far a rolled attribute moves from its class baseline, either way.
##
## Chosen structurally rather than measured: two points is what a single item
## is already worth in this game -- Robes carry +2 WIS and that is a whole plan
## row -- so it is the smallest step the existing table already treats as
## meaningful. No win rate was consulted and none should be used to change it.
const ROLL_SPREAD := 2

## A rolled attribute never drops below this, so a class value of 1 cannot
## become 0 or negative and silently switch off whatever reads it.
const ROLL_FLOOR := 1

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

## The same pawn with its attributes rolled from `run_seed`. Issue 131's
## stopgap: what randomised pawns feel like, before generation exists.
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
	for a in ROLLED_ATTRIBUTES:
		var base := pawn.pawn_class.attribute(a)
		var rolled := clampi(base + rng.randi_range(-ROLL_SPREAD, ROLL_SPREAD), ROLL_FLOOR, 999)
		pawn.attribute_bonus[a] = rolled - base
	return pawn

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
