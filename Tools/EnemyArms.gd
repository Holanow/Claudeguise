extends SceneTree

## Issue 491: what recovers #489's fifteen points, measured one arm at a time.
##
## Every arm is one derived multiplier, applied without editing source, over the
## same 6 pickable rooms x 5 buildable parties x 40 seeds. The base arm runs
## first as a go/no-go against #490's published 72.0 / warden 42.0, and again
## last to prove the registry mutation each enemy arm makes leaks nothing.

const SEEDS := 40

## Player attack power x1.15: the mean of the five starting weapons' percentages
## on their wielder's own attack stat (sword 15, staff 12, orb 18, bow 15,
## sickle 15). `ATTACK_POWER_PER_POINT` 1.9 -> 2.185.
const WEAPON_MEAN := 1.15

## The Warrior's plate used to add 2 CON and 10% CON, so 14 -> 17.6 -> 18, and
## `PawnData.attribute` is an int. +4 on the Warrior and nobody else.
const PLATE_CON := 4

func _init() -> void:
	var arms := [
		{"name": "base (trunk)", "player": 1.0, "ehp": 1.0, "edmg": 1.0, "con": 0},
		{"name": "A  class table absorbs the weapons  (player attack x1.15)", "player": WEAPON_MEAN, "ehp": 1.0, "edmg": 1.0, "con": 0},
		{"name": "B  enemy mirror                     (enemy hp /1.15)", "player": 1.0, "ehp": 1.0 / WEAPON_MEAN, "edmg": 1.0, "con": 0},
		{"name": "C  enemy mirror, damage side        (enemy attack /1.15)", "player": 1.0, "ehp": 1.0, "edmg": 1.0 / WEAPON_MEAN, "con": 0},
		{"name": "D  the plate third                  (Warrior CON 14 -> 18)", "player": 1.0, "ehp": 1.0, "edmg": 1.0, "con": PLATE_CON},
		{"name": "A+D  both halves absorbed by the class table", "player": WEAPON_MEAN, "ehp": 1.0, "edmg": 1.0, "con": PLATE_CON},
		{"name": "base (trunk) AGAIN -- must equal the first row", "player": 1.0, "ehp": 1.0, "edmg": 1.0, "con": 0},
	]
	for arm in arms:
		_run_arm(arm)
	quit(0)

## Every enemy that can appear on the ENEMY side of a pickable room, including
## the ones summoned mid-fight. Derived rather than listed: the content also
## defines a Siege Engine, which fights on the PLAYER team, and scaling
## "all enemies" would nerf the player.
func _hostile_ids() -> Array:
	var ids := {}
	for eid in RoomLibrary.pickable_ids():
		for spawn in RoomLibrary.get_room(eid).enemy_spawns:
			ids[spawn.get("enemy_id", &"")] = true
	for id in ids.keys().duplicate():
		var d: EnemyDef = EnemyLibrary.get_enemy(id)
		if d == null:
			continue
		for aid in d.actions:
			var a: ActionDef = ActionLibrary.get_action(aid)
			if a != null and a.summons_unit_id != &"":
				ids[a.summons_unit_id] = true
	return ids.keys()

func _run_arm(arm: Dictionary) -> void:
	var hostile := _hostile_ids()
	var saved := {}
	for id in hostile:
		var d: EnemyDef = EnemyLibrary.get_enemy(id)
		saved[id] = {"hp": d.hp_max, "atk": d.attack_power.duplicate()}
		d.hp_max = maxi(1, int(round(float(d.hp_max) * float(arm["ehp"]))))
		var scaled := {}
		for k in d.attack_power:
			scaled[k] = int(round(float(d.attack_power[k]) * float(arm["edmg"])))
		d.attack_power = scaled

	var con: int = arm["con"]
	var deps := SimDeps.new()
	var player_scale: float = arm["player"]
	deps.attack_power = func(unit: CombatUnit, action: ActionDef, rng: RandomNumberGenerator = null) -> float:
		var base := SimDeps._default_attack_power(unit, action, rng)
		return base * player_scale if unit.pawn != null else base

	var class_ids := ClassLibrary.all_ids()
	var wins := 0
	var fights := 0
	var per_room := {}
	for eid in RoomLibrary.pickable_ids():
		var encounter := RoomLibrary.get_room(eid)
		var rw := 0
		var rf := 0
		for skip in class_ids.size():
			var party_ids := []
			for i in class_ids.size():
				if i != skip:
					party_ids.append(class_ids[i])
			for s in SEEDS:
				var party: Array[PawnData] = []
				for cid in party_ids:
					var p := PawnFactory.make_starter_pawn(cid, StringName("%s_%d" % [cid, party.size()]), String(cid))
					## Per pawn, never on the shared ClassDef: an arm must not
					## leak into a class def the next arm reads.
					if con != 0 and cid == &"warrior":
						p.attribute_bonus[CG.Attribute.CON] = con
					party.append(p)
				var state := CombatSim.build(party, encounter, s, deps)
				if CombatSim.run(state, deps) == CombatState.Outcome.PLAYER_WIN:
					rw += 1
				rf += 1
		per_room[eid] = [rw, rf]
		wins += rw
		fights += rf

	for id in hostile:
		var d: EnemyDef = EnemyLibrary.get_enemy(id)
		d.hp_max = saved[id]["hp"]
		d.attack_power = saved[id]["atk"]

	print("")
	print("ARM: %s" % arm["name"])
	print("  ALL ROOMS  %5.1f%%   (%d / %d)" % [100.0 * float(wins) / float(fights), wins, fights])
	for eid in per_room:
		var r: Array = per_room[eid]
		print("    %-24s %5.1f%%   (%d / %d)" % [String(eid), 100.0 * float(r[0]) / float(r[1]), r[0], r[1]])
