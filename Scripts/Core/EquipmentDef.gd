extends Resource
class_name EquipmentDef


## A weapon, a piece of armor or an accessory. All share one shape and the
## slot decides which fields are read. Issue 745: five slots, main hand and
## off hand split from weapon, head and body split from armor.

enum Slot { MAIN_HAND, OFF_HAND, HEAD, BODY, ACCESSORY }

@export var id: StringName = &""
@export var display_name: String = ""
@export var slot: Slot = Slot.MAIN_HAND

## Which part in `Assets/Units/parts/` this item draws in the `Weapon` slot.
## Empty means it draws nothing, which is every item that is not a weapon.
@export var part: StringName = &""

## What the player reads on the item. Write what it does to the pawn, not to the
## numbers: "Heavy, and slows you down" rather than "AGI -0.15".
@export var description: String = ""

## Percentage multipliers keyed by CG.Attribute. 0.10 is +10%.
@export var attribute_percent: Dictionary = {}

## Flat additions keyed by CG.Attribute.
@export var attribute_flat: Dictionary = {}

## Issue 632: shape changes this item makes to abilities it did not author.
## Empty on every item that ships today, so nothing changes until one is set.
@export var modifiers: Array[AbilityModifier] = []

## Fraction of incoming damage removed before it is applied. The best across
## every equipped item counts, not the sum -- see `PawnData.gear_damage_reduction`.
@export var damage_reduction: float = 0.0

## Issue 746: percentage points per second added to `SimDeps._default_resource_regen_per_tick`.
## Additive across equipment; 0.0 does nothing, which is every item but the focus.
@export var resource_regen_percent_bonus: float = 0.0

## Issue 918: percentage points taken off every action's cooldown, summed
## across equipment. 0.0 does nothing, which is every item but the Book.
@export var cooldown_reduction_percent: float = 0.0

## Issue 918: percentage added to its wearer's maximum resource pool. Additive
## across equipment; 0.0 does nothing, which is every item but the Orb.
@export var resource_max_percent_bonus: float = 0.0

## Issue 916: what this piece rolled when it was generated. Empty on every
## hand-authored item, which is all fourteen that ship.
@export var affixes: Array[AffixRoll] = []

## ActionDef ids this piece grants its wielder.
@export var granted_actions: Array[StringName] = []

## Issue 917: this main hand fills the off hand as well, so its wielder gives
## up whatever action an off hand would have granted.
@export var two_handed: bool = false

## Every tag a class must carry to wear or wield this, all of them, not any.
## **Empty means anyone**, and only `gate_tags()` may appear here: tag counts
## are unevenly distributed across classes, so gating on a role permanently
## advantages whichever class carries the most. Issue 915 reverses #131.
@export var required_tags: Array[int] = []

## The only tags a piece may gate on: Method crossed with Style. Read off
## `ClassDef`'s own maps so the two cannot drift apart.
static func gate_tags() -> Array[int]:
	var out: Array[int] = []
	out.assign(ClassDef.METHOD_TAG.values() + ClassDef.STYLE_TAG.values())
	return out

## Issue 916: rarity is the affix count, not a second stored field -- README's
## own sentence makes them one number.
enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

func rarity() -> Rarity:
	return clampi(affixes.size(), 0, int(Rarity.LEGENDARY)) as Rarity

static func rarity_name(r: Rarity) -> String:
	match r:
		Rarity.UNCOMMON: return "Uncommon"
		Rarity.RARE: return "Rare"
		Rarity.EPIC: return "Epic"
		Rarity.LEGENDARY: return "Legendary"
	return "Common"

## This piece's own `attribute_flat` plus every affix that rolled onto it. One
## place, so the simulation and the equip screen cannot disagree.
func total_attribute_flat(a: int) -> float:
	return float(attribute_flat.get(a, 0)) + _affix_total(AffixDef.Effect.ATTRIBUTE_FLAT, a)

## Summed within one piece, because base and affix are the same piece of gear;
## `PawnData.gear_damage_reduction` still takes the best ACROSS pieces.
func total_damage_reduction() -> float:
	return damage_reduction + _affix_total(AffixDef.Effect.DAMAGE_REDUCTION, -1)

## Flat maximum health. Only an affix can carry this -- authored gear is a
## capability layer and `test_content_items` forbids it raw numbers.
func affix_max_hp_flat() -> float:
	return _affix_total(AffixDef.Effect.MAX_HP_FLAT, -1)

## Multiplies its wearer's attack power for every action, read by
## `AbilityModifiers.power_multiplier`.
func affix_power_multiplier() -> float:
	return 1.0 + _affix_total(AffixDef.Effect.DAMAGE_PERCENT, -1)

## Issue 931: the share of a landed hit this piece returns to its wielder.
func affix_life_leech() -> float:
	return _affix_total(AffixDef.Effect.LIFE_LEECH, -1)

## Issue 931: the share of the killer's own pool this piece grants on a kill.
func affix_resource_on_kill() -> float:
	return _affix_total(AffixDef.Effect.RESOURCE_ON_KILL, -1)

## Issue 931: the Book's percentage points and a rolled fraction are the same
## effect in two units, so they are summed here in the fraction both callers
## want and `cooldown_reduction_percent` is never read alone.
func total_cooldown_reduction() -> float:
	return cooldown_reduction_percent / 100.0 + _affix_total(AffixDef.Effect.COOLDOWN_RECOVERY, -1)

## Issue 931: the same shape `AbilityModifiers.added_statuses` returns for a
## modifier, so one landed hit applies both through one list.
func affix_added_statuses() -> Array:
	var out: Array = []
	for r in affixes:
		if r == null or r.affix == null or r.affix.effect != AffixDef.Effect.ON_HIT_STATUS:
			continue
		out.append({"status": r.affix.status, "ticks": r.affix.status_ticks,
			"chance": r.value, "source": "%s: %s" % [display_name, r.affix.display_name]})
	return out

func _affix_total(effect: AffixDef.Effect, a: int) -> float:
	var out := 0.0
	for r in affixes:
		if r == null or r.affix == null or r.affix.effect != effect:
			continue
		if effect == AffixDef.Effect.ATTRIBUTE_FLAT and int(r.affix.attribute) != a:
			continue
		out += r.value
	return out

## Here rather than in the equip screen or the registry, so every caller answers
## the question the same way.
func allows_class(class_def: ClassDef) -> bool:
	return missing_tags(class_def).is_empty()

## Which required tags this class does not carry, in declaration order. A caller
## that has to say *why* a piece is refused reads this; `allows_class` is the
## same question asked for a yes or no.
func missing_tags(class_def: ClassDef) -> Array[int]:
	if class_def == null:
		return []
	var have := class_def.tags()
	var out: Array[int] = []
	for t in required_tags:
		if not have.has(t):
			out.append(t)
	return out

## The method axis alone, for callers that hold a `CG.Method` and no class.
## Weaker than `allows_class` by exactly the tags it cannot see.
func allows(pawn_method: CG.Method) -> bool:
	var wanted: int = ClassDef.METHOD_TAG[pawn_method]
	for t in required_tags:
		if ClassDef.METHOD_TAG.values().has(t) and t != wanted:
			return false
	return true
