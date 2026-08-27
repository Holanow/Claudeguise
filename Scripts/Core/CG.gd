extends RefCounted
class_name CG

## Frozen vocabulary for the whole project. Enums and simulation constants.
##

const TICKS_PER_SECOND := 15
const TICK_SECONDS := 1.0 / float(TICKS_PER_SECOND)

## Arena is centred on (0, 0). World units, not pixels. The view scales.
const ARENA_HALF_WIDTH := 480.0
const ARENA_HALF_HEIGHT := 270.0

## A fight that has not resolved by this tick is a draw. Stops a stalemate
## between two passive parties from hanging the runner.
const MAX_TICKS := 3600

## The party deploys inside the left-hand fraction of the arena, so a fight
## always begins with ground between the two sides and somebody has to cross it.
const DEFAULT_ENCOUNTER := &"floor1_room1"

const PARTY_DEPLOY_FRACTION := 1.0 / 3.0

## Rightmost x a party member may start at. Derived rather than typed so it
## cannot drift away from the arena bounds.
static func party_deploy_max_x() -> float:
	return -ARENA_HALF_WIDTH + (ARENA_HALF_WIDTH * 2.0 * PARTY_DEPLOY_FRACTION)

enum Team {
	PLAYER,
	ENEMY,
}

enum Attribute {
	STR,
	DEX,
	AGI,
	CON,
	INT,
	ATN,
	WIS,
}

enum ResourceKind {
	MANA,
	RAGE,
	ENERGY,
}

enum DamageType {
	PHYSICAL,
	FIRE,
	WATER,
	AIR,
	EARTH,
	DIVINE,
	PROFANE,
	RAW,
}

enum Method { MARTIAL, MAGICAL }
enum Style { MELEE, RANGED, SUMMONER }
enum Role { DPS, SUPPORT, ANTI_SUPPORT, TANK, HEALER }

## Issue 131: the one namespace a piece of gear draws its requirements from.
## Flat rather than per-axis because the player's own example is `MARTIAL |
## TANK`, a Method and a Role, so a requirement cannot be typed to one axis.
##
## Append only. A class never authors these -- `ClassDef.tags()` derives them
## from the three fields above, so the two can never disagree.
enum Tag {
	MARTIAL,
	MAGICAL,
	MELEE,
	RANGED,
	SUMMONER,
	DPS,
	SUPPORT,
	ANTI_SUPPORT,
	TANK,
	HEALER,
}

## Status effects. Each damage type has one helpful and one harmful effect in
## README.md; only the ones the slice actually applies are listed. Adding one is
## a manager edit, not a content edit, because the sim must handle it.
enum Status {
	SHIELD,
	BLEED,
	TAUNTED,
	BURN,
	HASTE,
	STUN,
	BLOCK,
	MARKED,
	POISON,
	SLOWED,
	TAUNTING,
	## A ranged attack crossing this unit's front arc is stopped by it.
	SHIELDING,
	SUSTAINING,
}

## Whether a status is something a unit would want removed. Issue 627: the
## seven-member list this used to hold is now `StatusDef.harmful`, one field on
## the file that owns everything else about the status. The signature stays,
## because twenty call sites read it and none of them care where it comes from.
static func is_harmful(s: Status) -> bool:
	var def := StatusLibrary.of(s)
	return def != null and def.harmful

## What a decision layer asks a unit to do on a tick. The plan interpreter and
## the default behaviour both produce these; the simulation consumes them and is
## the only thing allowed to mutate a CombatUnit.
enum IntentKind {
	IDLE,
	MOVE_TO,
	USE_ACTION,
}

## Why a fight stopped, carried on the FIGHT_END event.
##
enum EndReason {
	UNSET,
	## The losing side has no living unit left. The ending the game has always
	## had.
	NO_SURVIVORS,
	CANNOT_ACT,
}

## Issue 344. Which single thing removed the most of an incoming hit, so the log
## can name the cause beside the number. One cause, never a list.
enum MitigationCause {
	NONE,
	TOUGHNESS,
	ARMOR,
	HIDE,
	SHIELD,
	BLOCK,
	## Issue 593: a raised directional block soaked it. Distinct from BLOCK,
	## which is `warrior_guard`'s flat 25% and takes a share of every hit --
	## this one is a pool of health that runs out.
	RAISED_SHIELD,
}

## Everything the simulation reports outwards. The view and the combat log read
## these and nothing else: no reaching into CombatUnit for "what just happened".
enum EventKind {
	FIGHT_START,
	FIGHT_END,
	DAMAGE,
	HEAL,
	DEATH,
	ACTION_START,
	ACTION_FIRE,
	STATUS_APPLIED,
	STATUS_EXPIRED,
	RESOURCE_SPENT,
	## An action landed and reached nothing: the target left range during the
	## wind-up, or was never in range when the action was committed.
	MISS,
	## A SHIELDING unit stepped in front of a hostile shot and took it instead
	## of whoever it was aimed at.
	BLOCKED,
	## A unit began holding a sustained action. Issue 61.
	SUSTAIN_START,
	## A unit stopped holding a sustained action, whatever ended it: its plan
	## chose something else, its resource ran out, it was stunned, or it died.
	SUSTAIN_END,
	## A committed action was cancelled before it fired. Today that is STUN
	## landing on a unit mid-wind-up; the mechanism itself is not stun-specific.
	INTERRUPTED,
	## A unit was built onto the field mid-fight. Issue 193.
	SUMMONED,
	## Terrain appeared mid-fight. Issue 492, and the first time `terrain` is
	## anything but the room it was authored as.
	TERRAIN_ADDED,
	## Terrain went away mid-fight, whole or in part.
	TERRAIN_REMOVED,
	## Issue 593: a raised shield soaked damage that would otherwise have
	## reached a health bar. Appended rather than filed beside BLOCKED because
	## these values are ordinals and inserting one renumbers every kind below.
	SHIELD_ABSORBED,
}

## Why a piece of terrain appeared or went away. Issue 492: the log has to be
## able to say which, because a fire going out for an invisible reason is the
## same trap as a pawn moving for one.
enum TerrainChange {
	## An action laid it down.
	CAST,
	## Water met fire and both lost the ground they shared.
	DOUSED,
}

static func attribute_name(a: Attribute) -> String:
	match a:
		Attribute.STR: return "STR"
		Attribute.DEX: return "DEX"
		Attribute.AGI: return "AGI"
		Attribute.CON: return "CON"
		Attribute.INT: return "INT"
		Attribute.ATN: return "ATN"
		Attribute.WIS: return "WIS"
	return "?"

static func damage_type_name(d: DamageType) -> String:
	match d:
		DamageType.PHYSICAL: return "Physical"
		DamageType.FIRE: return "Fire"
		DamageType.WATER: return "Water"
		DamageType.AIR: return "Air"
		DamageType.EARTH: return "Earth"
		DamageType.DIVINE: return "Divine"
		DamageType.PROFANE: return "Profane"
		DamageType.RAW: return "Raw"
	return "?"
