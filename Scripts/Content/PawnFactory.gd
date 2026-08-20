extends RefCounted
class_name PawnFactory


## Builds a starter PawnData: class definition, preset plans, starting gear.
## The only way a fightable pawn gets made right now. Not part of the Registry
## module contract. OWNER: teal.
##
## **An empty main hand means no basic attack** -- the attack is granted by the
## weapon (#129), and there is no implicit unarmed strike. A Warrior or an
## Abomination with an empty weapon slot stops entirely, because Rage only
## refills from landed hits.

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

## The armour a class starts wearing, and **it has exactly one entry on
## purpose.**
##
## **Issue 160: a starter pawn wearing nothing made every measurement tool in
## this repo blind to any armour-granted ability**, and there is exactly one of
## those -- `plate_mail` grants `warrior_block`, which fired zero times across 40
## seeds of 7 encounters against 9,000+ enemy shots. Arming the Warrior closes
## the whole of that gap today.
##
## **The other four are left bare deliberately, and it is a deferral rather than
## an answer.** `silk_wraps`, `robes`, `gown` and `scrubs` grant no action; they
## are stat sticks, so dressing a Priest is five separate design calls about
## which stat suits which class, and every one of them moves the whole balance
## table the way issue 129's weapons did. Nothing is blocked on it: no ability
## anywhere becomes reachable. Filed as its own question rather than smuggled in
## behind a defect fix.
##
## Armour carries no `allowed_methods`, unlike the weapons above, so `allows()`
## is vacuously true for every pawn and there is nothing here to keep in step
## with a class's method.
const STARTING_ARMOR := {
	&"warrior": &"plate_mail",
}

static func make_starter_pawn(class_id: StringName, pawn_id: StringName, display_name: String) -> PawnData:
	var pawn := PawnData.new()
	pawn.id = pawn_id
	pawn.display_name = display_name
	pawn.pawn_class = Registry.get_class_def(class_id)
	pawn.plans = PresetPlans.for_class(class_id)
	if STARTING_WEAPON.has(class_id):
		pawn.weapon = Registry.get_equipment(STARTING_WEAPON[class_id])
	if STARTING_ARMOR.has(class_id):
		pawn.armor = Registry.get_equipment(STARTING_ARMOR[class_id])
	return pawn
