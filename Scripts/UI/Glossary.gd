extends RefCounted
class_name Glossary


## Explanatory copy for every game term with no description anywhere today:

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
		_:
			return ""

## The data half of the status hover text.
##
## A status with a number on its `StatusDef` reads it. BLEED, TAUNTED, STUN and
## TAUNTING have none to duplicate -- magnitude and duration are
## per-action data on whichever ActionDef grants them, and TAUNTING's radius is
## `ActionDef.taunt_radius`, applied by `_apply_taunt` -- so their sentence
## names the mechanism rather than a number that would be wrong for most
## casters.
static func status_text(s: CG.Status) -> String:
	match s:
		CG.Status.SHIELD:
			return "Reduces incoming damage by %d%% while it lasts." % int(round(StatusLibrary.of(s).damage_reduction * 100.0))
		CG.Status.BLOCK:
			return "Reduces incoming damage by %d%% while it lasts." % int(round(StatusLibrary.of(s).damage_reduction * 100.0))
		CG.Status.BLEED:
			return "Deals damage each tick for a fixed duration."
		CG.Status.TAUNTED:
			return "Forced to attack whoever taunted this unit until it wears off or is cleansed."
		CG.Status.BURN:
			return "Burns for a share of the hit that lit it, each tick, until it wears off. A Geyser Blast snuffs it out and hits far harder for doing so."
		CG.Status.POISON:
			return "Deals %.2f%% of max hp each tick for a fixed duration." % StatusLibrary.of(s).damage_percent_of_max_hp_per_tick
		CG.Status.HASTE:
			return "Speeds up wind-up and recovery to %d%% of their normal length." % int(round(StatusLibrary.of(s).tick_scale * 100.0))
		CG.Status.STUN:
			return "Locks out actions entirely while it lasts."
		CG.Status.MARKED:
			return "Reduces this unit's damage reduction by %d%%, so every hit against it lands harder." % int(round(StatusLibrary.of(s).vulnerability * 100.0))
		CG.Status.SLOWED:
			return "Reduces move speed to %d%% of normal while it lasts. Does not affect action timing." % int(round(StatusLibrary.of(s).speed_scale * 100.0))
		CG.Status.TAUNTING:
			return "Forces nearby enemies to target this unit while it lasts."
		CG.Status.SHIELDING:
			return "Stops an incoming ranged shot aimed at an ally standing behind this unit, and soaks damage until the shield is spent."
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
static func status_magnitude_text(status: CG.Status, magnitude: int) -> String:
	if magnitude <= 0:
		return ""
	var def := StatusLibrary.of(status)
	if def.stacks:
		return "%d stack%s" % [magnitude, "" if magnitude == 1 else "s"]
	if def.hit_scaled:
		return "strength %d" % magnitude
	## Issue 593: the block is spent by damage rather than by time, so the
	## number a player needs is how much of it is left.
	if status == CG.Status.SHIELDING:
		return "%d shield left" % magnitude
	return ""

## The live half of the popup: what `unit` is carrying of `status` at `tick`.
static func status_now_text(unit, status: CG.Status, tick: int) -> String:
	if unit == null or not unit.statuses.has(status):
		return ""
	var parts: Array[String] = []
	var magnitude := status_magnitude_text(status, int(unit.status_magnitude.get(status, 0.0)))
	if magnitude != "":
		parts.append(magnitude)
	var left := maxi(int(unit.statuses[status]) - tick, 0)
	parts.append("%.1fs left" % (float(left) / float(CG.TICKS_PER_SECOND)))
	return "On %s now: %s." % [unit.display_name, ", ".join(parts)]

## The whole popup for one status badge, general sentence and live numbers.
static func status_popup_text(unit, status: CG.Status, tick: int) -> String:
	var lines: Array[String] = [status_text(status)]
	var now := status_now_text(unit, status, tick)
	if now != "":
		lines.append(now)
	return "\n\n".join(lines)

## The status's name, as every screen already spells it.
static func status_name(s: CG.Status) -> String:
	return String(CG.Status.keys()[s]).capitalize()

## ---------------------------------------------------------------------------
## Issue 449: *"I need a mouse-over glossary on basically everything."*
##
## Hover is the cheap version of the click card, not a competitor to it, so
## every sentence below is `UnitCard`'s own. Clicking pauses the fight; hovering
## must not, which is the whole reason there are two of these.

const HOVER_CLICK_HINT := "Click it for everything the game knows about it."

## One unit, in the four lines that answer "what is it doing and why". The
## status list is names and timers only -- what each one MEANS is one badge
## hover away, and repeating it here would make the box taller than the fight.
static func unit_hover_text(state: CombatState, u: CombatUnit) -> String:
	var lines: Array[String] = [UnitCard.side_text(u), UnitCard.resource_line(u),
		UnitCard.doing_line(state, u)]
	lines.append_array(UnitCard.focus_lines(state, u))
	var carried := status_summary(state, u)
	if carried != "":
		lines.append(carried)
	lines.append(HOVER_CLICK_HINT)
	return "\n".join(lines)

## Every status on the unit as name and countdown, in the badge row's own order.
static func status_summary(state: CombatState, u: CombatUnit) -> String:
	var parts := _status_parts(state, u, UnitView.ordered_statuses(u))
	if parts.is_empty():
		return ""
	return "Carrying %s." % ", ".join(parts)

## The statuses the badge row had no room for, which is what the "+N" chip is
## hiding. Named because a count the player cannot expand is a worse answer
## than no chip at all.
static func hidden_statuses_text(state: CombatState, u: CombatUnit) -> String:
	var all := UnitView.ordered_statuses(u)
	var hidden := all.slice(all.size() - UnitView.hidden_status_count(u))
	var parts := _status_parts(state, u, hidden)
	if parts.is_empty():
		return ""
	return "The badge row has no space for %s. Hover the badges beside it, or click the unit." % [
		", ".join(parts)]

static func _status_parts(state: CombatState, u: CombatUnit, statuses: Array) -> Array[String]:
	var parts: Array[String] = []
	for s in statuses:
		var bits: Array[String] = []
		var magnitude := status_magnitude_text(s, int(u.status_magnitude.get(s, 0.0)))
		if magnitude != "":
			bits.append(magnitude)
		bits.append("%.1fs left" % (float(maxi(int(u.statuses[s]) - state.tick, 0)) / float(CG.TICKS_PER_SECOND)))
		parts.append("%s (%s)" % [status_name(s), ", ".join(bits)])
	return parts

## A team-panel row, in the numbers it is drawing rather than the names of its
## bars. The bars say how much is left; only words can say of what, and what the
## pawn is doing with it.
static func team_row_text(state: CombatState, u: CombatUnit) -> String:
	var lines: Array[String] = ["%s. %d of %d hp." % [u.display_name, maxi(u.hp, 0), u.hp_max]]
	if u.pawn == null:
		lines.append("Summoned into this fight; its row goes when it does.")
	lines.append_array([UnitCard.resource_line(u), UnitCard.doing_line(state, u)])
	lines.append_array(UnitCard.focus_lines(state, u))
	return "\n".join(lines)
