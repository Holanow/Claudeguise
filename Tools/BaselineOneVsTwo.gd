extends SceneTree

## Issue 543: one ungeared pawn of each class against two base enemies, across
## seeds, reporting whether it wins and how much health it finishes on.
##
## Ungeared means armour stripped and the weapon kept: every basic attack in the
## game is granted by a weapon, so a weaponless pawn has nothing to attack with.
##
## The encounter is built here and NEVER registered. A registered encounter
## would change `Registry.all_encounter_ids()`, which is what `SampleFights`
## iterates, and move the #540 simulation fingerprint.

const SEEDS := 20

## The base enemy, and the count. See the issue for why the Goblin: floor 1's
## first room is built out of them, it carries exactly one action, and it is
## melee so no class gets a free approach.
##
## #542 proposes a base monster profile with per-monster multipliers. It has not
## landed. When it does, this should read the base profile rather than an id.
const BASE_ENEMY := &"goblin"
const BASE_ENEMY_COUNT := 2

## Remaining-health ceiling per class, as a fraction. The player's, 2026-08-24:
## squishier pawns end at 30% or less, tankier ones at 60%.
const STOMP_CEILING := {
	&"warrior": 0.60,
	&"abomination": 0.60,
	&"siege_master": 0.30,
	&"priest": 0.30,
	&"geysermancer": 0.30,
}

var _lines := PackedStringArray()

func _say(line: String = "") -> void:
	_lines.append(line)
	print(line)

func _fingerprint() -> void:
	var body := "\n".join(_lines) + "\n"
	print("lines: %d" % _lines.size())
	print("fingerprint: %s" % body.sha256_text())

func _init() -> void:
	var class_ids := Registry.all_class_ids()
	_say("classes: " + str(class_ids))
	_say("base enemy: %s x%d, seeds: %d" % [BASE_ENEMY, BASE_ENEMY_COUNT, SEEDS])
	if class_ids.is_empty() or Registry.get_enemy(BASE_ENEMY) == null:
		printerr("no content registered; nothing to sample")
		quit(1)
		return

	# Both plan arms, because they are different games and the issue's premise
	# does not say which one it means.
	for use_presets in [false, true]:
		_say("")
		_say("========================================================")
		_say("ARM: " + ("preset plans (the authored library)" if use_presets else "no plans (what PartySelect deploys)"))
		_say("========================================================")
		for class_id in class_ids:
			_sample(class_id, use_presets)

	_fingerprint()
	quit(0)

## Armour off, weapon kept.
func _ungeared(class_id: StringName, use_presets: bool) -> PawnData:
	var pawn := PawnFactory.make_preset_pawn(class_id, class_id, String(class_id)) if use_presets \
		else PawnFactory.make_starter_pawn(class_id, class_id, String(class_id))
	pawn.armor = null
	pawn.accessory = null
	return pawn

func _encounter() -> Encounter:
	var e := Encounter.new()
	e.id = &"baseline_1v2"
	e.display_name = "Baseline, one pawn against two base enemies"
	var spawns: Array[Dictionary] = []
	for i in BASE_ENEMY_COUNT:
		spawns.append({
			"enemy_id": BASE_ENEMY,
			"position": Vector2(150.0, -50.0 + 100.0 * float(i)),
		})
	e.enemy_spawns = spawns
	e.party_spawns = [Vector2(-350.0, 0.0)]
	return e

func _sample(class_id: StringName, use_presets: bool) -> void:
	var encounter := _encounter()
	var wins := 0
	var losses := 0
	var draws := 0
	var ticks: Array[int] = []
	var hp_percent: Array[int] = []
	var win_hp_percent: Array[int] = []
	var minions: Array[int] = []
	var stomps := 0

	var ceiling := float(STOMP_CEILING.get(class_id, 0.30))
	for s in SEEDS:
		var party: Array[PawnData] = [_ungeared(class_id, use_presets)]
		var state := CombatSim.build(party, encounter, s)
		var outcome := CombatSim.run(state)
		var pct := _pawn_hp_percent(state)
		ticks.append(state.tick)
		hp_percent.append(pct)
		minions.append(_minions_built(state))
		match outcome:
			CombatState.Outcome.PLAYER_WIN:
				wins += 1
				win_hp_percent.append(pct)
				if float(pct) > ceiling * 100.0:
					stomps += 1
			CombatState.Outcome.ENEMY_WIN:
				losses += 1
			_:
				draws += 1

	_say("")
	_say("%s   (ceiling %d%% of %d hp)" % [String(class_id), int(round(ceiling * 100.0)), _max_hp(class_id, use_presets)])
	_say("  win %d / lose %d / draw %d  of %d%s" % [
		wins, losses, draws, SEEDS,
		"" if wins == SEEDS else "   <- DOES NOT WIN RELIABLY",
	])
	if wins == 0:
		_say("  pawn hp   no wins to measure")
	else:
		_say("  pawn hp   won on median %d%%  (min %d%%, max %d%%)   %s" % [
			_median(win_hp_percent), _min(win_hp_percent), _max(win_hp_percent),
			_stomp_note(stomps, wins),
		])
	_say("  ticks     min %d  median %d  max %d   (%.1fs .. %.1fs)" % [
		_min(ticks), _median(ticks), _max(ticks),
		float(_min(ticks)) / float(CG.TICKS_PER_SECOND),
		float(_max(ticks)) / float(CG.TICKS_PER_SECOND),
	])
	# Allied minions use the enemy stat path, and a Siege Engine has more health
	# than the Siege Master. A pawn that finishes untouched behind two turrets
	# passes a remaining-health ceiling for the wrong reason.
	if _max(minions) > 0:
		_say("  minions   built in %d of %d fights, up to %d at once" % [
			_nonzero(minions), SEEDS, _max(minions),
		])

func _stomp_note(stomps: int, wins: int) -> String:
	if stomps == wins:
		return "<- STOMP, every win above the ceiling"
	if stomps == 0:
		return "<- inside the ceiling on every win"
	return "<- %d of %d wins above the ceiling" % [stomps, wins]

## The one pawn's health as a percentage of its own maximum. Dead reads 0.
func _pawn_hp_percent(state: CombatState) -> int:
	for u in state.units:
		if u.team == CG.Team.PLAYER and u.pawn != null:
			if u.hp_max <= 0:
				return 0
			return int(round(100.0 * float(maxi(0, u.hp)) / float(u.hp_max)))
	return 0

## Player-team units with no pawn behind them: summons.
func _minions_built(state: CombatState) -> int:
	var n := 0
	for u in state.units:
		if u.team == CG.Team.PLAYER and u.pawn == null:
			n += 1
	return n

func _max_hp(class_id: StringName, use_presets: bool) -> int:
	return Balance.max_hp(_ungeared(class_id, use_presets))

func _min(a: Array[int]) -> int:
	var v := a[0]
	for x in a:
		v = mini(v, x)
	return v

func _max(a: Array[int]) -> int:
	var v := a[0]
	for x in a:
		v = maxi(v, x)
	return v

func _median(a: Array[int]) -> int:
	var c := a.duplicate()
	c.sort()
	return c[c.size() / 2]

func _nonzero(a: Array[int]) -> int:
	var n := 0
	for x in a:
		if x > 0:
			n += 1
	return n
