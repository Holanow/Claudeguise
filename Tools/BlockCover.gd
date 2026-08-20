extends SceneTree

## Issue 315. Two questions about the Warrior's block, and neither is a win
## rate: does it ever stop a shot aimed at somebody else, and does anybody ever
## stand behind it.

const SEEDS := 20

## How far behind the shielder still counts as sheltered, for the standing-behind
## count only -- the simulation itself has no depth, it tests the shot's path.
const COVER_DEPTH := 300.0

## Fixed rather than read off `SHIELD_WIDTH`, so the same band is counted on
## both builds and the two runs are comparable.
const COVER_HALF_WIDTH := 110.0

func _init() -> void:
	var class_ids := Registry.all_class_ids()
	var totals := {}
	for encounter_id in Registry.all_encounter_ids():
		var encounter := Registry.get_encounter(encounter_id)
		var c := {
			"fights": 0, "casts": 0, "blocked": 0, "for_ally": 0, "for_self": 0,
			"unmatched": 0, "shielding_ticks": 0,
			"behind_narrow": 0, "behind_wide": 0, "fights_with_behind": 0,
			"wins": 0, "losses": 0, "draws": 0,
		}
		for skip in class_ids.size():
			var party_ids := []
			for i in class_ids.size():
				if i != skip:
					party_ids.append(class_ids[i])
			for s in SEEDS:
				_fight(party_ids, encounter, s, c)
		_print_block(encounter_id, c)
		for k in c:
			totals[k] = int(totals.get(k, 0)) + int(c[k])
	_print_block("ALL ENCOUNTERS", totals)
	quit(0)

func _fight(party_ids: Array, encounter, fight_seed: int, c: Dictionary) -> void:
	var party: Array[PawnData] = []
	for cid in party_ids:
		party.append(PawnFactory.make_starter_pawn(cid, StringName("%s_%d" % [cid, party.size()]), String(cid)))
	var state := CombatSim.build(party, encounter, fight_seed)
	c["fights"] = int(c["fights"]) + 1

	var seen_events := 0
	var behind_this_fight := 0
	while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
		# A BLOCKED event names the shooter and the blocker but never the unit
		# the shot was aimed at, so the intended target has to be read off the
		# projectile it belonged to: the ones that resolve during this tick.
		var was_resolved := {}
		for i in state.projectiles.size():
			if (state.projectiles[i] as Projectile).resolved:
				was_resolved[i] = true

		CombatSim.step(state)

		var aimed_at := {}
		for i in state.projectiles.size():
			var p: Projectile = state.projectiles[i]
			if p.resolved and not was_resolved.has(i):
				aimed_at[i] = p.target_id

		while seen_events < state.events.size():
			var e: CombatEvent = state.events[seen_events]
			seen_events += 1
			if e.kind == CG.EventKind.ACTION_FIRE and e.action_id == &"warrior_block":
				c["casts"] = int(c["casts"]) + 1
			elif e.kind == CG.EventKind.BLOCKED:
				c["blocked"] = int(c["blocked"]) + 1
				var intended := _intended_target(state, aimed_at, e)
				if intended == -1:
					c["unmatched"] = int(c["unmatched"]) + 1
				elif intended == e.target_id:
					c["for_self"] = int(c["for_self"]) + 1
				else:
					c["for_ally"] = int(c["for_ally"]) + 1

		behind_this_fight += _sample_cover(state, c)

	if behind_this_fight > 0:
		c["fights_with_behind"] = int(c["fights_with_behind"]) + 1
	match state.outcome:
		CombatState.Outcome.PLAYER_WIN: c["wins"] = int(c["wins"]) + 1
		CombatState.Outcome.ENEMY_WIN: c["losses"] = int(c["losses"]) + 1
		_: c["draws"] = int(c["draws"]) + 1

## The projectile that resolved into this BLOCKED event, by shooter and action
## among the ones that were in flight when the tick began.
func _intended_target(state: CombatState, aimed_at: Dictionary, e: CombatEvent) -> int:
	var found := -1
	for i in aimed_at:
		var p: Projectile = state.projectiles[i]
		if p.source_id != e.source_id or p.action_id != e.action_id:
			continue
		if found != -1 and found != int(aimed_at[i]):
			return -1 # two candidates disagreeing: refuse to guess
		found = int(aimed_at[i])
	return found

## Ally-ticks spent inside the shield's shadow, at the old frontage and the new
## one, counted from live positions rather than from events.
func _sample_cover(state: CombatState, c: Dictionary) -> int:
	var behind := 0
	for team in [CG.Team.PLAYER, CG.Team.ENEMY]:
		for shielder in state.living(team):
			if not shielder.has_status(CG.Status.SHIELDING) or shielder.facing == Vector2.ZERO:
				continue
			c["shielding_ticks"] = int(c["shielding_ticks"]) + 1
			for ally in state.living(team):
				if ally.id == shielder.id:
					continue
				var d := ally.position - shielder.position
				var depth := d.dot(shielder.facing)
				if depth >= 0.0 or -depth > COVER_DEPTH:
					continue
				var lateral := absf(d.cross(shielder.facing))
				if lateral <= 40.0:
					c["behind_narrow"] = int(c["behind_narrow"]) + 1
				if lateral <= COVER_HALF_WIDTH:
					c["behind_wide"] = int(c["behind_wide"]) + 1
					behind += 1
	return behind

func _print_block(label: String, c: Dictionary) -> void:
	print("")
	print("%s -- %d fights, SHIELD_WIDTH %.1f" % [label, int(c["fights"]), CombatSim.SHIELD_WIDTH])
	print("  warrior_block casts                    %d" % int(c["casts"]))
	print("  BLOCKED events                         %d" % int(c["blocked"]))
	print("    aimed at the shielder itself         %d" % int(c["for_self"]))
	print("    AIMED AT AN ALLY (the cover case)    %d" % int(c["for_ally"]))
	print("    could not be matched to a shot       %d" % int(c["unmatched"]))
	print("  unit-ticks with a shield up            %d" % int(c["shielding_ticks"]))
	print("  ally-ticks behind it, within 80 frontage  %d" % int(c["behind_narrow"]))
	print("  ally-ticks behind it, within 220 frontage %d" % int(c["behind_wide"]))
	print("  fights where anyone stood behind it    %d" % int(c["fights_with_behind"]))
	print("  outcome  W %d  L %d  D %d" % [int(c["wins"]), int(c["losses"]), int(c["draws"])])
