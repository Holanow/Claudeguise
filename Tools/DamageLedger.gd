extends RefCounted
class_name DamageLedger

## Issue 737. One summary, read from `state.events`, called from both the
## in-game end screen (`Scripts/UI/EndScreen.gd`) and the headless sweep
## (`Tools/DamageLedgerReport.gd`) -- the player's own ruling: a balance
## number nobody but a designer can see is the same defect the pawn-behaviour
## principle already forbids, aimed at numbers instead of decisions.
##
## Two damage paths: a direct hit carries `action_id` and lands in
## `by_ability`; status damage (burn, poison) carries `status` instead and
## lands in `by_dot`, attributed to whoever applied it via `source_id`.
## Read-only: never touches `CombatSim` or writes back onto a `CombatState`.

class Ledger:
	var by_ability: Dictionary = {}   # team -> {action_id -> {total, casts}}
	var by_dot: Dictionary = {}       # team -> {status -> {total, ticks}}
	var by_type: Dictionary = {}      # team -> {damage_type -> {dealt, taken}}
	var fires: Dictionary = {}        # team -> {action_id -> {count}}
	## Keyed by the TARGET's team: whether armour on that side did anything.
	var mitigation: Dictionary = {}   # team -> {before, after, absorbed, dealt, cause: {}}

	func _row(dict: Dictionary, team: int, key, fields: Dictionary) -> Dictionary:
		if not dict.has(team):
			dict[team] = {}
		var per_team: Dictionary = dict[team]
		if not per_team.has(key):
			per_team[key] = fields.duplicate(true)
		return per_team[key]

	func _mit(team: int) -> Dictionary:
		return _row(mitigation, team, "totals", \
			{"before": 0, "after": 0, "absorbed": 0, "dealt": 0, "cause": {}})

## One fight's worth of events into one ledger.
static func build(state: CombatState) -> Ledger:
	var l := Ledger.new()
	for e in state.events:
		if e.kind == CG.EventKind.ACTION_FIRE:
			var caster := state.unit(e.source_id)
			if caster != null:
				l._row(l.fires, caster.team, e.action_id, {"count": 0}).count += 1
			continue
		if e.kind != CG.EventKind.DAMAGE:
			continue
		var source := state.unit(e.source_id)
		var target := state.unit(e.target_id)
		if e.action_id != &"":
			if source != null:
				var ab := l._row(l.by_ability, source.team, e.action_id, {"total": 0, "casts": 0})
				ab.total += e.amount
				ab.casts += 1
			if target != null:
				var m := l._mit(target.team)
				m.before += e.amount_before_mitigation
				m.after += e.amount_after_mitigation
				m.absorbed += e.amount_absorbed
				m.dealt += e.amount
				if e.mitigation_cause != CG.MitigationCause.NONE:
					m.cause[e.mitigation_cause] = int(m.cause.get(e.mitigation_cause, 0)) + \
						(e.amount_before_mitigation - e.amount_after_mitigation)
		elif source != null:
			var st := l._row(l.by_dot, source.team, e.status, {"total": 0, "ticks": 0})
			st.total += e.amount
			st.ticks += 1
		if source != null:
			l._row(l.by_type, source.team, e.damage_type, {"dealt": 0, "taken": 0}).dealt += e.amount
		if target != null:
			l._row(l.by_type, target.team, e.damage_type, {"dealt": 0, "taken": 0}).taken += e.amount
	return l

## Sums several fights' ledgers (one floor's worth of rooms) into one.
static func merge(ledgers: Array) -> Ledger:
	var out := Ledger.new()
	for l in ledgers:
		_merge_counts(out.by_ability, l.by_ability, ["total", "casts"])
		_merge_counts(out.by_dot, l.by_dot, ["total", "ticks"])
		_merge_counts(out.by_type, l.by_type, ["dealt", "taken"])
		_merge_counts(out.fires, l.fires, ["count"])
		for team in l.mitigation:
			var src: Dictionary = l.mitigation[team]["totals"]
			var dst := out._mit(team)
			dst.before += src.before
			dst.after += src.after
			dst.absorbed += src.absorbed
			dst.dealt += src.dealt
			for c in src.cause:
				dst.cause[c] = int(dst.cause.get(c, 0)) + int(src.cause[c])
	return out

static func _merge_counts(dst: Dictionary, src: Dictionary, fields: Array) -> void:
	for team in src:
		if not dst.has(team):
			dst[team] = {}
		for key in src[team]:
			if not dst[team].has(key):
				dst[team][key] = src[team][key].duplicate()
				continue
			for f in fields:
				dst[team][key][f] += src[team][key][f]

## Ability casts and DoT ticks together, highest total first, so a screen with
## room for a handful of lines can show "what did the most" without caring
## which of the two damage paths it came from.
static func top_sources(l: Ledger, team: int, limit: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in l.by_ability.get(team, {}):
		var row: Dictionary = l.by_ability[team][id]
		out.append({"name": ability_name(id), "total": row.total, "count": row.casts, "unit": "casts"})
	for status in l.by_dot.get(team, {}):
		var row: Dictionary = l.by_dot[team][status]
		out.append({"name": String(CG.Status.keys()[status]), "total": row.total, "count": row.ticks, "unit": "ticks"})
	out.sort_custom(func(a, b): return a.total > b.total)
	if out.size() > limit:
		out.resize(limit)
	return out

## Empty when no direct hit ever landed on `team`.
static func mitigation_summary(l: Ledger, team: int) -> Dictionary:
	return l.mitigation.get(team, {}).get("totals", {})

## An ability that fired and can deal damage (a non-healing `HitEffect` in its
## own `effects`) but landed zero total across the whole run -- the
## unreachable-ability shape #737 asks this ledger to surface.
static func zero_damage_fires(l: Ledger, team: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in l.fires.get(team, {}):
		if l.by_ability.get(team, {}).has(id):
			continue
		var action := ActionLibrary.get_action(id)
		if action == null:
			continue
		var deals_damage := false
		for fx in action.effects:
			if fx is HitEffect and not fx.heals:
				deals_damage = true
				break
		if deals_damage:
			out.append({"name": ability_name(id), "fires": l.fires[team][id].count})
	return out

static func ability_name(id: StringName) -> String:
	var a := ActionLibrary.get_action(id)
	return a.display_name if a != null else String(id)

static func team_name(team: int) -> String:
	return "player" if team == CG.Team.PLAYER else "enemy"
