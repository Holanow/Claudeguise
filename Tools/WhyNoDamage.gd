extends SceneTree

## Where does a fight's damage actually come from, and who never gets to act?
##
##   godot --headless --path . --script res://Tools/WhyNoDamage.gd
##
## MANAGER-OWNED. Not part of the game and not part of the gate.
##
## teal asked for this rather than guessing a fifth lever, and they were right
## to. Issue 31 assumed a party that takes almost no damage must be out of
## reach. teal tested that to destruction: an ambusher in the party's own
## deploy zone, a sniper matching the party's 265 range, and finally
## `siege_shot`'s own range dialled 260 -> 150, below every enemy's melee
## reach. `siege_master x4` stayed 20/20 at 70-85% health through all of it.
##
## **Reach was never the variable.** So the question is no longer "why can
## nothing get to them" but "why does getting to them not matter", and that is
## a question about who is alive long enough to swing.
##
## Per enemy: how long it lived, how many actions it got off, what it did with
## them. Per party member: what it dealt and what it took. The comparison that
## matters is between a party that takes almost nothing and one that nearly
## dies winning, which is why this runs two parties rather than one.

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")

const SEED := 0

## The party that wins without being touched, and the party that wins nearly
## dead. Same room, same seed, so any difference is the party.
const PARTIES := [
	["siege_master", "siege_master", "siege_master", "siege_master"],
	["warrior", "warrior", "warrior", "warrior"],
]

func _init() -> void:
	for ids in PARTIES:
		_trace(ids)
	quit(0)

func _trace(ids: Array) -> void:
	var party: Array[PawnData] = []
	for cid in ids:
		var c := StringName(cid)
		party.append(PawnFactory.make_starter_pawn(
			c, StringName("%s_%d" % [cid, party.size()]), Registry.get_class_def(c).display_name
		))
	var state := CombatSim.build(party, Registry.get_encounter(CG.DEFAULT_ENCOUNTER), SEED)
	CombatSim.run(state)

	print("")
	print("================================================")
	print("party: %s   -- %d ticks" % [", ".join(PackedStringArray(ids)), state.tick])
	print("================================================")

	# Death tick per unit, so "how long did it live" is a real number rather
	# than an inference from the final hp column.
	var died_at := {}
	var fired := {}
	var dealt := {}
	var taken := {}
	for u in state.units:
		fired[u.id] = 0
		dealt[u.id] = 0
		taken[u.id] = 0

	for e in state.events:
		match e.kind:
			CG.EventKind.DEATH:
				if not died_at.has(e.target_id):
					died_at[e.target_id] = e.tick
			CG.EventKind.ACTION_FIRE:
				if fired.has(e.source_id):
					fired[e.source_id] += 1
			CG.EventKind.DAMAGE:
				if dealt.has(e.source_id):
					dealt[e.source_id] += e.amount
				if taken.has(e.target_id):
					taken[e.target_id] += e.amount

	print("  ENEMIES")
	print("    %-16s %6s %7s %7s %7s" % ["unit", "died", "shots", "dealt", "taken"])
	var enemy_shots := 0
	var enemy_dealt := 0
	var never_acted := 0
	for u in state.units:
		if u.team != CG.Team.ENEMY:
			continue
		var d: int = died_at.get(u.id, -1)
		enemy_shots += fired[u.id]
		enemy_dealt += dealt[u.id]
		if fired[u.id] == 0:
			never_acted += 1
		print("    %-16s %6s %7d %7d %7d" % [
			u.display_name,
			"alive" if d < 0 else str(d),
			fired[u.id], dealt[u.id], taken[u.id],
		])

	print("  PARTY")
	print("    %-16s %6s %7s %7s %7s" % ["unit", "died", "shots", "dealt", "taken"])
	for u in state.units:
		if u.team != CG.Team.PLAYER:
			continue
		var d: int = died_at.get(u.id, -1)
		print("    %-16s %6s %7d %7d %7d   ends %d/%d" % [
			u.display_name,
			"alive" if d < 0 else str(d),
			fired[u.id], dealt[u.id], taken[u.id], u.hp, u.hp_max,
		])

	# The summary line the whole tool exists for. If a party takes little
	# damage because the enemy never swings, that is action economy. If the
	# enemy swings plenty and the damage still does not land, it is
	# mitigation or hp, and those are different problems with different fixes.
	var enemy_count := 0
	for u in state.units:
		if u.team == CG.Team.ENEMY:
			enemy_count += 1
	print("  ----")
	print("  enemy actions fired: %d   total enemy damage: %d" % [enemy_shots, enemy_dealt])
	print("  enemies that never fired once: %d of %d" % [never_acted, enemy_count])
	print("  damage per enemy action: %.1f" % (
		0.0 if enemy_shots == 0 else float(enemy_dealt) / float(enemy_shots)
	))
