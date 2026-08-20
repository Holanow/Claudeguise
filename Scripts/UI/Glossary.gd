extends RefCounted
class_name Glossary


## Explanatory copy for every game term with no description anywhere today:
## class tags (Role/Style/Method), stats (CG.Attribute) and statuses
## (CG.Status). Hover-info-box system, phase 1 (see TEAM_LOG.md, wren's
## block) -- Control-based screens first, the battle arena (where statuses
## actually appear on screen) second.
##
## OWNER: wren. Explanatory copy is presentation, not simulation -- same
## reasoning Palette.gd already applies to colour.
##
## The one rule that matters more than the wording: **this file owns the
## sentence, Balance owns the number.** Every numeric fact below is read
## from a real Balance/Core constant at call time, never retyped as a
## literal -- rook's own correction after the condition-editor bug (a UI
## file captioned a control from the op's default instead of the plan's
## real value, i.e. kept a second copy of a fact PlanInterpreter already
## owned). A description here can go stale the moment a balance pass
## changes a number; reading the constant instead of copying it is what
## keeps that impossible.
##
## Percent constants in Balance are stored as whole numbers (e.g. `0.30`
## already means "0.30%", not "30%" -- see POISON_DAMAGE_PERCENT_PER_TICK's
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
## InspectPanel both already show side by side ("Tank Â· Melee Â· Martial").
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
## once. Every status with a Balance-owned number reads it; BLEED, TAUNTED,
## STUN, TAUNTING and SHIELDING have no single tunable number to duplicate
## (BLEED/TAUNTED/SHIELDING's magnitude and duration are per-action data on
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
		CG.Status.TAUNTED:
			return "Forced to attack whoever taunted this unit until it wears off or is cleansed."
		# Issue 121, finch: no number, following BLEED's line above and wren's
		CG.Status.BURN:
			return "Burns for a share of the hit that lit it, each tick, until it wears off. A Geyser Blast snuffs it out and hits far harder for doing so."
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
		CG.Status.SUSTAINING:
			return "This unit is holding an action open. It pays that action's cost every tick, and stops when its plan chooses something else or it can no longer pay."
		_:
			return ""

## ---------------------------------------------------------------------------
## Issue 245: *"I should be able to mouse over a status icon in the party
## overview and get a more indepth description of the status."*
##
## The general sentence above is half the answer and it is the half that was
## already there. The other half is **what this badge is carrying right now** --
## how many stacks, how hard it burns, how long it has left -- which is the
## difference between a glossary and an explanation. A player watching a Warrior
## at three stacks of BLEED and a Warrior at one wants those to read differently,
## because they are.

## What a status is carrying beyond its expiry, in words, or "" for the statuses
## that carry nothing a player should be shown.
##
## **The two sets are read from `CombatSim`, not listed here**, and that is the
## whole point of the function. A generic "print the magnitude when it is not
## zero" is wrong and dangerously so: `TAUNTED` stores **the taunter's unit id**
## in that same field and `SUSTAINING` stores an action, so the naive version
## publishes a unit id to the player as if it were a strength. `CombatLogView`
## worked this out once already and this is that rule with one owner instead of
## two -- the log calls it now, so a line in the log and a popup on the panel
## cannot describe the same badge two different ways.
static func status_magnitude_text(status: CG.Status, magnitude: int) -> String:
	if magnitude <= 0:
		return ""
	if CombatSim._STACKING_STATUSES.has(status):
		return "%d stack%s" % [magnitude, "" if magnitude == 1 else "s"]
	if CombatSim._HIT_SCALED_STATUSES.has(status):
		return "strength %d" % magnitude
	return ""

## The live half of the popup: what `unit` is carrying of `status` at `tick`.
##
## Reads the unit rather than being handed numbers, because the two facts come
## from two dictionaries (`statuses` holds the expiry tick, `status_magnitude`
## holds the rest) and a caller assembling them itself is a second place for the
## pairing to go wrong.
##
## Returns "" when the unit does not have the status at all, so a caller can tell
## "nothing to add" from "carrying nothing", which are different sentences.
static func status_now_text(unit, status: CG.Status, tick: int) -> String:
	if unit == null or not unit.statuses.has(status):
		return ""
	var parts: Array[String] = []
	var magnitude := status_magnitude_text(status, int(unit.status_magnitude.get(status, 0.0)))
	if magnitude != "":
		parts.append(magnitude)
	# Ticks the player reads as the clock reads them, the same unit the cooldown
	var left := maxi(int(unit.statuses[status]) - tick, 0)
	parts.append("%.1fs left" % (float(left) / float(CG.TICKS_PER_SECOND)))
	return "On %s now: %s." % [unit.display_name, ", ".join(parts)]

## The whole popup for one status badge, general sentence and live numbers.
##
## One function because the panel and anything that describes a badge later must
## not each assemble their own -- four screens calling one status three different
## names is a failure this file already exists to prevent.
##
## **The body only. The name is the title**, on both surfaces -- `pin_title` on
## the chip feeds `Popout`'s own title row and `GlossaryTooltip`'s heading. The
## first version put the name in here as well and the pinned copy said "Taunting"
## twice, which no test saw because the string was correct in both places.
static func status_popup_text(unit, status: CG.Status, tick: int) -> String:
	var lines: Array[String] = [status_text(status)]
	var now := status_now_text(unit, status, tick)
	if now != "":
		lines.append(now)
	return "\n\n".join(lines)

## The status's name, as every screen already spells it.
##
## `CG.Status.keys()` is what the combat log, the plan sentence, the condition
## editor and the team panel all read. It lives here because the popup above
## needs it and this file is where the words are; `TeamStatusView.status_name`
## is kept as a call through to this, so nothing that already asks it changes.
static func status_name(s: CG.Status) -> String:
	return String(CG.Status.keys()[s]).capitalize()
