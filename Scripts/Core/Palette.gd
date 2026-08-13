extends RefCounted

const CG := preload("res://Scripts/Core/CG.gd")

## Every colour, size and spacing value in the project. One file so that nobody
## picks a colour inline and nothing has to be hunted down later.
##
## MANAGER-OWNED. Do not edit. Propose the exact line in TEAM_LOG.md.

const BACKGROUND := Color("14131a")
const ARENA_FLOOR := Color("1e1c26")
const ARENA_EDGE := Color("35313f")
const TEXT := Color("e8e4f0")
const TEXT_DIM := Color("9a94aa")

const TEAM_PLAYER := Color("6fd3c7")
const TEAM_ENEMY := Color("e0705f")

const HP_FULL := Color("7cc46b")
const HP_LOW := Color("e0705f")
const HP_BACK := Color("2a2733")

const RESOURCE_MANA := Color("6a8fe0")
const RESOURCE_RAGE := Color("e08a4b")
const RESOURCE_ENERGY := Color("e0d24b")

const FOCUS_LINE := Color("ffffff40")
const WIND_UP := Color("f0c674")

const SPACE_XS := 4.0
const SPACE_S := 8.0
const SPACE_M := 16.0
const SPACE_L := 32.0

const FONT_SIZE_BODY := 14
const FONT_SIZE_SMALL := 11
const FONT_SIZE_HEADING := 22
const FONT_SIZE_FLOATER := 18

static func damage_color(d: CG.DamageType) -> Color:
	match d:
		CG.DamageType.PHYSICAL: return Color("d8d3c4")
		CG.DamageType.FIRE: return Color("e8703a")
		CG.DamageType.WATER: return Color("4aa3d8")
		CG.DamageType.AIR: return Color("bfe0e8")
		CG.DamageType.EARTH: return Color("a8834b")
		CG.DamageType.DIVINE: return Color("f2e08a")
		CG.DamageType.PROFANE: return Color("9c5fbd")
		CG.DamageType.RAW: return Color("ff5fa8")
	return TEXT

static func team_color(t: CG.Team) -> Color:
	return TEAM_PLAYER if t == CG.Team.PLAYER else TEAM_ENEMY

static func resource_color(r: CG.ResourceKind) -> Color:
	match r:
		CG.ResourceKind.MANA: return RESOURCE_MANA
		CG.ResourceKind.RAGE: return RESOURCE_RAGE
		CG.ResourceKind.ENERGY: return RESOURCE_ENERGY
	return TEXT

static func hp_color(fraction: float) -> Color:
	return HP_LOW.lerp(HP_FULL, clampf(fraction, 0.0, 1.0))
