extends RefCounted

const CG := preload("res://Scripts/Core/CG.gd")
const Balance := preload("res://Scripts/Content/Balance.gd")

## Explanatory copy for every game term with no description anywhere today:
## class tags (Role/Style/Method), stats (CG.Attribute) and statuses
## (CG.Status). Hover-info-box system, phase 1 (see TEAM_LOG.md, wren's
## block) — Control-based screens first, the battle arena (where statuses
## actually appear on screen) second.
##
## OWNER: wren. Explanatory copy is presentation, not simulation — same
## reasoning Palette.gd already applies to colour.
##
## The one rule that matters more than the wording: **this file owns the
## sentence, Balance owns the number.** Every numeric fact below is read
## from a real Balance/Core constant at call time, never retyped as a
## literal — rook's own correction after the condition-editor bug (a UI
## file captioned a control from the op's default instead of the plan's
## real value, i.e. kept a second copy of a fact PlanInterpreter already
## owned). A description here can go stale the moment a balance pass
## changes a number; reading the constant instead of copying it is what
## keeps that impossible.
##
## Percent constants in Balance are stored as whole numbers (e.g. `0.30`
## already means "0.30%", not "30%" — see POISON_DAMAGE_PERCENT_PER_TICK's
## own doc comment) and some as fractions of 1.0 (e.g.
## STATUS_SHIELD_REDUCTION). Each formatter below matches whichever the
## constant it reads actually uses; nothing here re-derives a percent from
## a fraction or vice versa.

static func role_text(role: CG.Role) -> String:
	match role:
		CG.Role.DPS:
			return "Deals most of a party's damage."
		CG.Role.SUPPORT:
			return "Buffs or heals allies rather than dealing damage itself."
		CG.Role.ANTI_SUPPORT:
			return "Reduces or disrupts what enemies can do, rather than dealing damage directly."
		CG.Role.TANK:
			return "Draws and absorbs hits so squishier allies don't have to take them."
		CG.Role.HEALER:
			return "Restores allies' hp during a fight."
		_:
			return ""

static func style_text(style: CG.Style) -> String:
	match style:
		CG.Style.MELEE:
			return "Fights at close range."
		CG.Style.RANGED:
			return "Fights from a distance with real travel time on every shot."
		CG.Style.SUMMONER:
			return "Fights indirectly, through units it brings into the fight."
		_:
			return ""

static func method_text(method: CG.Method) -> String:
	match method:
		CG.Method.MARTIAL:
			return "Physical actions."
		CG.Method.MAGICAL:
			return "Magical actions."
		_:
			return ""

## One line combining a class's three tags, the same trio PartyCard and
## InspectPanel both already show side by side ("Tank · Melee · Martial").
## Single source for both screens' tooltip copy so they cannot drift apart.
static func class_tags_text(role: CG.Role, style: CG.Style, method: CG.Method) -> String:
	return "%s %s %s" % [role_text(role), style_text(style), method_text(method)]

## Which attribute drives a class's own attack power, per Balance.attack_power
## -- Melee Martial reads STR, Ranged/Summoner Martial reads DEX, any Magical
## class reads INT regardless of style. Mirrored here (not called) because
## attack_power needs a live PawnData and the glossary describes the stat in
## general, not one pawn's current total.
static func attribute_text(a: CG.Attribute) -> String:
	match a:
		CG.Attribute.STR:
			return "Adds %d hp per point. Drives attack power (%.1f per point) for Melee Martial classes." % [
				Balance.HP_PER_STR_BONUS, Balance.ATTACK_POWER_PER_POINT]
		CG.Attribute.DEX:
			return "Adds %.2f move speed per point. Drives attack power (%.1f per point) for Ranged and Summoner Martial classes." % [
				Balance.MOVE_PER_DEX_BONUS, Balance.ATTACK_POWER_PER_POINT]
		CG.Attribute.AGI:
			return "Adds %.1f move speed per point. Shortens wind-up and recovery, capped at %d%% faster." % [
				Balance.MOVE_PER_AGI, int(round(Balance.MAX_AGI_TICK_SCALE * 100.0))]
		CG.Attribute.CON:
			return "Adds %d hp per point. Reduces incoming damage by %d%% per point, capped at %d%%." % [
				Balance.HP_PER_CON, int(round(Balance.DAMAGE_REDUCTION_PER_CON * 100.0)), int(round(Balance.NATURAL_DAMAGE_REDUCTION_CAP * 100.0))]
		CG.Attribute.INT:
			return "Adds %d max resource per point. Drives attack power (%.1f per point) for Magical classes." % [
				Balance.RESOURCE_PER_INT_BONUS, Balance.ATTACK_POWER_PER_POINT]
		CG.Attribute.ATN:
			return "Adds %d max resource per point." % Balance.RESOURCE_PER_ATN
		CG.Attribute.WIS:
			return "Raises how many plan blocks a pawn's plans may total. At least 1 regardless of WIS."
		_:
			return ""

## Statuses are drawn in the battle arena (UnitView's status tags, phase 2 of
## the hover system); this is the data half, written now so phase 2 wires a
## mechanism against text that already exists rather than writing both at
## once. Every status with a Balance-owned number reads it; BLEED, ENRAGE,
## STUN, TAUNTING and SHIELDING have no single tunable number to duplicate
## (BLEED/ENRAGE/SHIELDING's magnitude and duration are per-action data on
## whichever ActionDef grants them, not a shared Balance constant; TAUNTING
## reads EnemyDef.spawn_taunt_radius per-caster) -- their sentence names the
## mechanism rather than inventing one number that would be wrong for most
## casters.
static func status_text(s: CG.Status) -> String:
	match s:
		CG.Status.SHIELD:
			return "Reduces incoming damage by %d%% while it lasts." % int(round(Balance.STATUS_SHIELD_REDUCTION * 100.0))
		CG.Status.BLOCK:
			return "Reduces incoming damage by %d%% while it lasts." % int(round(Balance.STATUS_BLOCK_REDUCTION * 100.0))
		CG.Status.BLEED:
			return "Deals damage each tick for a fixed duration."
		CG.Status.ENRAGE:
			return "Increases damage dealt while it lasts."
		CG.Status.BURN:
			return "Deals %.2f%% of max hp each tick for a fixed duration." % Balance.BURN_DAMAGE_PERCENT_PER_TICK
		CG.Status.POISON:
			return "Deals %.2f%% of max hp each tick for a fixed duration." % Balance.POISON_DAMAGE_PERCENT_PER_TICK
		CG.Status.HASTE:
			return "Speeds up wind-up and recovery to %d%% of their normal length." % int(round(Balance.HASTE_TICK_SCALE * 100.0))
		CG.Status.STUN:
			return "Locks out actions entirely while it lasts."
		CG.Status.MARKED:
			return "Reduces this unit's damage reduction by %d%%, so every hit against it lands harder." % int(round(Balance.MARKED_VULNERABILITY_BONUS * 100.0))
		CG.Status.SLOWED:
			return "Reduces move speed to %d%% of normal while it lasts. Does not affect action timing." % int(round(Balance.SLOWED_SPEED_SCALE * 100.0))
		CG.Status.TAUNTING:
			return "Forces nearby enemies to target this unit while it lasts."
		CG.Status.SHIELDING:
			return "Stops an incoming ranged shot aimed at an ally standing behind this unit, while it lasts."
		## Issue 61. No number, and for a different reason from the others above:
		## this status has no magnitude of its own at all. What it costs and what
		## it reaches are per-action data on whichever ActionDef is being held,
		## so a shared constant here would be wrong for every caster but one.
		##
		## **swift wrote this, in wren's file.** `test_ui_glossary.gd` refuses a
		## CG.Status with no text, which is the guard working -- the sentence is
		## one line and is meant to be rewritten by whoever owns the copy.
		CG.Status.SUSTAINING:
			return "This unit is holding an action open. It pays that action's cost every tick, and stops when its plan chooses something else or it can no longer pay."
		_:
			return ""
