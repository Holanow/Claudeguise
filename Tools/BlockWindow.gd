extends SceneTree

## How often does the Warrior's directional block actually stop a shot?
##
##   godot --headless --path . --script res://Tools/BlockWindow.gd
##
## Not part of the game and not part of the gate. swift's, alongside
## Tools/CleanseWindow.gd, which this is shaped after.
##
## `Tools/BlockProbe.gd` (rook's) asked the same question and could not answer
## it: there was no BLOCKED event, so it counted *opportunities* -- SHIELDING
## applications and enemy shots -- and had to reason about the geometry in a
## print statement rather than measure it. Now that an interception emits an
## event, the question is answerable, and this counts the answer.
##
## One room. `floor1_room1` only, named rather than indexed: floors and runs
## are parked, and a floor-run measurement is not evidence about single-room
## combat. Every party a player can actually build, every seed.
##
## Prints the projectile speeds it measured at, because they are being tuned
## while this is being measured and a block rate without a speed beside it is
## not a number anybody can compare against later.

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")

const ROOM := &"floor1_room1"
const SEEDS := 30

func _init() -> void:
	print("room: ", ROOM)
	print("shield width: %.0f units" % CombatSim.SHIELD_WIDTH)
	var speeds := {} # action id -> projectile_speed, of every shot actually fired
	var encounter := Registry.get_encounter(ROOM)
	var class_ids := Registry.all_class_ids()

	var total_fights := 0
	var total_shots := 0
	var total_blocks := 0
	var total_applied := 0

	print("")
	print("-- per party, %d seeds each --" % SEEDS)
	for party_ids in _parties(class_ids):
		var fights := 0
		var shots := 0
		var blocks := 0
		var applied := 0
		var fights_with_a_block := 0
		var wins := 0
		var warrior_deaths := 0
		var party_hp := 0.0
		for s in SEEDS:
			var party: Array[PawnData] = []
			for cid in party_ids:
				party.append(PawnFactory.make_starter_pawn(
					cid, StringName("%s_%d" % [cid, party.size()]), String(cid)))
			var state := CombatSim.build(party, encounter, s)
			var outcome := CombatSim.run(state)
			fights += 1
			if outcome == CombatState.Outcome.PLAYER_WIN:
				wins += 1
			var hp := 0
			var hp_max := 0
			for u in state.units:
				if u.team != CG.Team.PLAYER:
					continue
				hp += maxi(0, u.hp)
				hp_max += u.hp_max
				if not u.alive and u.pawn != null and String(u.pawn.id).begins_with("warrior"):
					warrior_deaths += 1
			if hp_max > 0:
				party_hp += 100.0 * float(hp) / float(hp_max)
			var here := 0
			for e in state.events:
				match e.kind:
					CG.EventKind.BLOCKED:
						blocks += 1
						here += 1
					CG.EventKind.STATUS_APPLIED:
						if e.status == CG.Status.SHIELDING:
							applied += 1
					CG.EventKind.ACTION_FIRE:
						var a := Registry.get_action(e.action_id)
						var src := state.unit(e.source_id)
						if a != null and a.projectile_speed > 0.0:
							speeds[e.action_id] = a.projectile_speed
							if src != null and src.team == CG.Team.ENEMY:
								shots += 1
			if here > 0:
				fights_with_a_block += 1

		print("")
		print("party: ", _short(party_ids))
		print("  SHIELDING applied  %5.1f per fight" % (float(applied) / float(fights)))
		print("  enemy shots        %5.1f per fight" % (float(shots) / float(fights)))
		print("  BLOCKED            %5.1f per fight   (%d of %d shots, %.1f%%)" % [
			float(blocks) / float(fights), blocks, shots,
			0.0 if shots == 0 else 100.0 * float(blocks) / float(shots),
		])
		print("  fights with at least one block: %d of %d" % [fights_with_a_block, fights])
		# The block redirects damage onto the Warrior rather than deleting it, so
		# a wider shield is not free. These three say what it costs.
		print("  wins %d of %d   party finished on %.0f%% hp   warrior died in %d" % [
			wins, fights, party_hp / float(fights), warrior_deaths,
		])

		total_fights += fights
		total_shots += shots
		total_blocks += blocks
		total_applied += applied

	print("")
	print("-- projectile speeds of every shot actually fired --")
	print("   (units per tick, %d ticks per second)" % CG.TICKS_PER_SECOND)
	var fired: Array = speeds.keys()
	fired.sort()
	for action_id in fired:
		print("  %-24s %.1f" % [String(action_id), float(speeds[action_id])])

	print("")
	print("========================================================")
	print("%d fights on %s" % [total_fights, ROOM])
	print("SHIELDING applied  %.1f per fight" % (float(total_applied) / float(total_fights)))
	print("enemy shots        %.1f per fight" % (float(total_shots) / float(total_fights)))
	print("BLOCKED            %.1f per fight   (%d of %d shots, %.1f%%)" % [
		float(total_blocks) / float(total_fights), total_blocks, total_shots,
		0.0 if total_shots == 0 else 100.0 * float(total_blocks) / float(total_shots),
	])
	quit(0)

## The five leave-one-out parties, which are the only full parties a player can
## build (PartySelect allows one card per class). Same rule SampleFights.gd
## documents at length; mono-class parties are not measured here at all.
func _parties(class_ids: Array) -> Array:
	var out := []
	if class_ids.size() > 4:
		for skip in class_ids.size():
			var party := []
			for i in class_ids.size():
				if i != skip:
					party.append(class_ids[i])
			out.append(party)
	else:
		out.append(class_ids.slice(0, mini(4, class_ids.size())))
	return out

func _short(ids: Array) -> String:
	var parts := PackedStringArray()
	for i in ids:
		parts.append(String(i))
	return ", ".join(parts)
