extends SceneTree

## What does a sustained damage aura actually do to a single room?
##
##   godot --headless --path . --script res://Tools/SustainProbe.gd
##
## Not part of the game and not part of the gate. Issue 61, swift.
##
## **This measures a mechanism, not a card.** Immolate does not exist -- it is
## retired from the game and finch owns the action that will replace it. So the
## aura below is mine, invented for this probe, and every number it produces is
## a number about the shape I chose. Read it as "an aura of roughly this size
## moves the room by roughly this much", never as a proposal for what Immolate
## should cost.
##
## **Balance is frozen** (CLAUDE.md). Nothing here is tuned toward a win rate,
## and none of these constants belong in `Scripts/Content`. If the aura moves
## the table, that movement is the finding.
##
## The controller is deliberately IDEALISED and that is the largest caveat in
## the output: the Abomination holds the aura whenever an enemy is inside it and
## it can pay, ahead of claw, hook and grapple. A real authored plan will not be
## that disciplined, so treat these as an upper bound on what the mechanism can
## contribute rather than as a forecast.

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")
const SimDeps := preload("res://Scripts/Combat/SimDeps.gd")
const Intent := preload("res://Scripts/Core/Intent.gd")
const ActionDef := preload("res://Scripts/Core/ActionDef.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PlanInterpreter := preload("res://Scripts/Plans/PlanInterpreter.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")

## Single room, per CLAUDE.md: `floor1_room1` is the instrument, and a floor-run
## measurement is not evidence for a single-room decision.
const ENCOUNTER := &"floor1_room1"
const SEEDS := 150
const PARTY := ["abomination", "geysermancer", "priest", "warrior"]

const PROBE_ID := &"probe_immolate"

## The aura's shape. 90 units is a little over twice melee reach, so it rewards
## the Abomination for doing what its kit already wants (closing) without making
## it a ranged class. `power_scale` 0.35 against a 15-tick second means roughly
## five claw-strikes' worth of damage per second spread over everything in
## reach, which is a lot -- deliberately, so the mechanism's effect is visible
## above the noise rather than hidden inside it.
const RADIUS := 90.0
const POWER_SCALE := 0.35
const WIND_UP := 15
const COSTS := [1, 2, 4]

func _init() -> void:
	var base := _arm(0)
	print("")
	print("SUSTAINED AURA, %s, %d seeds, party %s" % [ENCOUNTER, SEEDS, PARTY])
	print("radius %.0f, power_scale %.2f, wind-up %d ticks. The aura is the probe's, not content's." % [RADIUS, POWER_SCALE, WIND_UP])
	print("")
	print("%-22s %7s %9s %10s %9s %9s %9s %9s %9s" % ["arm", "wins", "avg ticks", "aura dmg", "% party", "channels", "ticks held", "abom dmg", "abom hits"])
	_row("baseline (no aura)", base)
	for c in COSTS:
		_row("aura, %d rage/tick" % c, _arm(c))
	print("")
	print("rage: max %d, %.0f%% of max gained per landed hit" % [base["rage_max"], 18.0])
	print("'abom hits' is landed non-aura hits per fight, which is the ONLY way")
	print("a Rage pawn refills. An aura tick is not one: _tick_sustain does not")
	print("call _on_hit_landed, so a sustained action on a Rage pawn is a pure")
	print("dump that can never pay for itself.")
	print("")
	print("CAVEATS. The controller is idealised (the aura is preferred over claw,")
	print("hook and grapple whenever it is affordable and something is in reach),")
	print("so 'channels' and 'ticks held' are an upper bound. The aura is not")
	print("authored content and nothing in Scripts/Content uses it.")
	quit(0)

func _row(label: String, r: Dictionary) -> void:
	print("%-22s %3d/%-3d %9.0f %10d %8.1f%% %9.2f %10.1f %9d %9.2f" % [
		label, r["wins"], SEEDS, r["avg_ticks"], r["aura_damage"],
		r["aura_share"] * 100.0, r["channels"], r["ticks_held"],
		r["abom_damage"], r["abom_hits"],
	])

func _aura(cost: int) -> ActionDef:
	var a := ActionDef.new()
	a.id = PROBE_ID
	a.display_name = "Immolate (probe)"
	a.wind_up_ticks = WIND_UP
	a.recover_ticks = 0
	a.cooldown_ticks = 0
	a.resource_cost = 0
	a.range_units = 999.0
	a.damage_type = CG.DamageType.FIRE
	a.power_scale = POWER_SCALE
	a.sustain_cost_per_tick = cost
	a.sustain_radius = RADIUS
	return a

## cost 0 means "run the room exactly as it is today", which is the arm every
## other number is read against.
func _arm(cost: int) -> Dictionary:
	var action := _aura(cost) if cost > 0 else null
	var wins := 0
	var ticks := 0
	var aura_damage := 0
	var party_damage := 0
	var channels := 0
	var ticks_held := 0
	var rage_max := 0
	var abom_damage := 0
	var abom_hits := 0

	for s in range(SEEDS):
		var state := _run(action, s)
		if state.outcome == CombatState.Outcome.PLAYER_WIN:
			wins += 1
		ticks += state.tick
		for u in state.units:
			if u.pawn != null and u.resource_kind == CG.ResourceKind.RAGE:
				rage_max = maxi(rage_max, u.resource_max)
		for e in state.events:
			match e.kind:
				CG.EventKind.DAMAGE:
					var src := state.unit(e.source_id)
					if src != null and src.team == CG.Team.PLAYER:
						party_damage += e.amount
						if e.action_id == PROBE_ID:
							aura_damage += e.amount
						if _is_abomination(src):
							abom_damage += e.amount
							if e.action_id != PROBE_ID:
								abom_hits += 1
				CG.EventKind.SUSTAIN_END:
					channels += 1
					ticks_held += e.amount

	return {
		"wins": wins,
		"avg_ticks": float(ticks) / float(SEEDS),
		"aura_damage": aura_damage,
		"aura_share": (float(aura_damage) / float(party_damage)) if party_damage > 0 else 0.0,
		"channels": float(channels) / float(SEEDS),
		"ticks_held": float(ticks_held) / float(SEEDS),
		"rage_max": rage_max,
		"abom_damage": abom_damage,
		"abom_hits": float(abom_hits) / float(SEEDS),
	}

func _is_abomination(u: CombatUnit) -> bool:
	return u.pawn != null and u.pawn.pawn_class != null and u.pawn.pawn_class.id == &"abomination"

func _run(action: ActionDef, fight_seed: int) -> CombatState:
	var party: Array[PawnData] = []
	for cid in PARTY:
		var c := StringName(cid)
		party.append(PawnFactory.make_starter_pawn(
			c, StringName("%s_%d" % [cid, party.size()]), Registry.get_class_def(c).display_name
		))

	var deps := SimDeps.new()
	if action != null:
		deps.action_lookup = func(id: StringName):
			return action if id == PROBE_ID else Registry.get_action(id)
		## The idealised controller. It writes `focus_id` the way a real
		## targeting block would, then names the aura -- which is also the
		## re-affirmation the channel lives on, so this same branch both starts
		## it and keeps it running, tick after tick, exactly as an authored plan
		## whose condition still holds would.
		deps.plan_decide = func(s: CombatState, u: CombatUnit) -> Intent:
			if u.pawn != null and u.pawn.pawn_class != null and u.pawn.pawn_class.id == &"abomination":
				var near := _nearest_enemy(s, u)
				if near != null and u.position.distance_to(near.position) <= RADIUS \
						and u.resource >= action.sustain_cost_per_tick:
					u.focus_id = near.id
					return Intent.use_action(PROBE_ID, near.id)
			return PlanInterpreter.decide(s, u)

	var state := CombatSim.build(party, Registry.get_encounter(ENCOUNTER), fight_seed, deps)
	if action != null:
		for u in state.units:
			if u.pawn != null and u.pawn.pawn_class != null and u.pawn.pawn_class.id == &"abomination":
				u.actions.append(PROBE_ID)
	CombatSim.run(state, deps)
	return state

func _nearest_enemy(state: CombatState, unit: CombatUnit) -> CombatUnit:
	var best: CombatUnit = null
	var best_d := INF
	for c in state.living(CG.Team.ENEMY if unit.team == CG.Team.PLAYER else CG.Team.PLAYER):
		var d := unit.position.distance_to(c.position)
		if d < best_d:
			best_d = d
			best = c
	return best
