extends RefCounted
class_name Palette


## Every colour, size and spacing value in the project. One file so that nobody
## picks a colour inline and nothing has to be hunted down later.

const BACKGROUND := Color("14131a")
const ARENA_FLOOR := Color("1e1c26")
const ARENA_EDGE := Color("35313f")
const TEXT := Color("e8e4f0")
const TEXT_DIM := Color("9a94aa")

const TEAM_PLAYER := Color("6fd3c7")
const TEAM_ENEMY := Color("e0705f")

const HP_FULL := Color("7cc46b")

## **`HP_LOW` is byte-identical to `TEAM_ENEMY`, and that aliasing has caused
## three separate defects.** Read this before using either.
const HP_LOW := Color("e0705f")
const HP_BACK := Color("2a2733")

const RESOURCE_MANA := Color("6a8fe0")
const RESOURCE_RAGE := Color("e08a4b")
const RESOURCE_ENERGY := Color("e0d24b")

const FOCUS_LINE := Color("ffffff40")

## ---------------------------------------------------------------------------
## THE LEDGER. Issue 807.
##
## The player reviews the combat records of mercenaries they hired, so every
## information surface is a page of that ledger and the arena is not: the fight
## is the record being replayed, not a page. Everything above this line is the
## arena's; everything below it is the page's. `TEXT` and `INK` are the same
## job on the two sides of that line and neither may be used on the other.

## Three paper tones, used structurally rather than as one beige. The leaf is
## the screen, the field is a card laid on it, the shade is a recess or a
## banded row.
const PAPER_LEAF := Color("e2d5ba")
const PAPER_FIELD := Color("efe6d2")
const PAPER_SHADE := Color("cdbc9b")

## Iron gall ink dries brown-black rather than black, and a true black on paper
## reads as a screenshot of a website.
const INK := Color("2a2118")
const INK_DIM := Color("6a5946")
const INK_FAINT := Color("9b8a72")

## The two ruling colours, and they are the whole reason this does not read as
## generic old paper. Account books were ruled with red vertical money columns
## over blue-grey horizontal feint.
const RULE_RED := Color("9a3324")
const RULE_FEINT := Color("7d8b9c")

## The book itself: board, leather, the strap the arena is mounted under.
const BINDING := Color("4b3226")
const BINDING_DEEP := Color("2e1e17")

## Team colours are information and keep their meaning on paper, but the arena
## versions are chosen against `#14131a` and go chalky on parchment. These are
## the same two hues at paper contrast.
const TEAM_PLAYER_INK := Color("1d5f61")
const TEAM_ENEMY_INK := Color("8e3527")

static func team_ink(t: CG.Team) -> Color:
	return TEAM_PLAYER_INK if t == CG.Team.PLAYER else TEAM_ENEMY_INK

## The paper counterpart of `damage_color`. A damage type's own colour is
## authored against the dark arena; darkened it keeps its hue and its identity
## and stops glowing off the page.
static func damage_ink(d: CG.DamageType) -> Color:
	return ink_of(damage_color(d))

## Any arena colour, pulled down to something that reads as ink on paper.
static func ink_of(c: Color) -> Color:
	var out := c.darkened(0.45)
	out.s = minf(out.s * 1.15, 1.0)
	return out

const SPACE_XS := 4.0
const SPACE_S := 8.0
const SPACE_M := 16.0
const SPACE_L := 32.0

## Sized for a phone held at arm's length, not for a desktop window you can
## lean into. The user's framing: "imagine that I'm playing this on a mobile
## device". That is a forcing function rather than a port -- if a fight is
## readable at this size it is readable everywhere, and everything that only
## works at 11px was never carrying its weight.
const FONT_SIZE_BODY := 20
const FONT_SIZE_SMALL := 16
const FONT_SIZE_HEADING := 30
const FONT_SIZE_FLOATER := 34

## Minimum side of anything a finger has to hit. Touch targets are the one
## mobile constraint that has no desktop equivalent and cannot be discovered by
## looking at a screenshot.
const TOUCH_TARGET_MIN := 48.0

## Issue 631: the eight colours live on the `DamageType` resources now, so this
## is the one reader rather than one of several parallel tables.
static func damage_color(d: CG.DamageType) -> Color:
	var def := DamageTypeLibrary.of(d)
	return def.color if def != null else TEXT

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
