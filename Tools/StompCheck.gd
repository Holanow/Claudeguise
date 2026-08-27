extends SceneTree

## Issue 667. One fight per room, on a fixed seed, with the preset party --
## #596: a starter pawn carries no plan rows, so `SampleFights`' starter pawns
## measure only the fallback. A stomp check has to look at authored behaviour,
## so this uses `PawnFactory.make_preset_pawn` instead.
##
## STOMP means either side ended above 80% of its own starting health: the
## player winning untouched, the enemy winning untouched, or both sides
## sitting high in a stall. All three mean the fight was not a contest.

const SEED := 1

## Five classes and a four-slot party: issue 667 says "the default party" and
## there is no single one that contains all five. Runs every leave-one-out
## party `SampleFights._parties` already treats as buildable, same rule,
## rather than choosing one class to drop unasked. Posted to rook on the
## board (linnet's block, 2026-08-27); not yet answered.

func _say(line: String = "") -> void:
	print(line)

func _init() -> void:
	var class_ids := ClassLibrary.all_ids()
	var encounter_ids := Registry.all_encounter_ids()
	if class_ids.is_empty() or encounter_ids.is_empty():
		printerr("no content registered; nothing to check")
		quit(1)
		return

	var contests := 0
	var total := 0
	for encounter_id in encounter_ids:
		var encounter := Registry.get_encounter(encounter_id)
		for party_ids in _parties(class_ids):
			total += 1
			if _check(encounter_id, encounter, party_ids):
				contests += 1

	_say("")
	_say("%d / %d rooms were a contest" % [contests, total])
	quit(0 if contests == total else 1)

## The same leave-one-out rule `SampleFights._parties` uses for "parties a
## player can build" when there are more than four classes.
func _parties(class_ids: Array) -> Array:
	var out := []
	if class_ids.size() > 4:
		for skip in class_ids.size():
			var party := []
			for i in class_ids.size():
				if i != skip:
					party.append(class_ids[i])
			out.append(party)
	elif class_ids.size() >= 1:
		## Four or fewer classes: the whole roster is one legal party and
		## there is no prefix to pick, so nothing here selects by position.
		out.append(class_ids)
	return out

## Runs one fight and prints its verdict. Returns true when it was a contest.
func _check(encounter_id: StringName, encounter: Encounter, party_ids: Array) -> bool:
	var party: Array[PawnData] = []
	for cid in party_ids:
		party.append(PawnFactory.make_preset_pawn(cid, StringName("%s_%d" % [cid, party.size()]), String(cid)))
	var state := CombatSim.build(party, encounter, SEED)
	CombatSim.run(state)

	var player_pct := _team_hp_percent(state, CG.Team.PLAYER)
	var enemy_pct := _team_hp_percent(state, CG.Team.ENEMY)
	var stomp := player_pct > 80 or enemy_pct > 80
	_say("%-24s %-40s player %3d%%  enemy %3d%%  %s" % [
		String(encounter_id), _short(party_ids), player_pct, enemy_pct,
		"STOMP" if stomp else "PASS",
	])
	return not stomp

func _short(ids: Array) -> String:
	var parts := PackedStringArray()
	for i in ids:
		parts.append(String(i))
	return ", ".join(parts)

## What a side has left, as a percentage of its starting hp. Dead units count
## as zero rather than being dropped, matching `SampleFights._team_hp_percent`.
func _team_hp_percent(state: CombatState, team: int) -> int:
	var hp := 0
	var hp_max := 0
	for u in state.units:
		if u.team != team:
			continue
		hp += maxi(0, u.hp)
		hp_max += u.hp_max
	if hp_max <= 0:
		return 0
	return int(round(100.0 * float(hp) / float(hp_max)))
