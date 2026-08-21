extends SceneTree

## Issue 356: why the party choice does not change the outcome. Reads the event
## stream after each fight resolves, so it never asks a unit anything and never
## touches `state.rng`.


const SEEDS := 40

## An enemy carries a MECHANIC if it can do anything to a pawn other than
## subtract health: a status, a taunt, a summon.
const MECHANIC := {
	&"stalker": "MARKED",
	&"brute": "STUN+TAUNT",
	&"rat": "BLEED",
	&"rat_king": "SUMMON",
	&"cultist": "POISON",
}

func _init() -> void:
	var class_ids := Registry.all_class_ids()
	var encounter_ids := Registry.pickable_encounter_ids()

	_roster_census(encounter_ids)

	print("")
	print("======== WHAT EACH ROOM COSTS, AND HOW MUCH THE PARTY CHOICE MOVES IT ========")
	print("end HP%% = party health remaining when the fight resolves, dead pawns counted as 0.")
	print("")
	var room_rows := []
	var hp_points := []
	var sec_points := []
	for encounter_id in encounter_ids:
		var encounter := Registry.get_encounter(encounter_id)
		print("ENCOUNTER: %s  (%s)" % [encounter_id, encounter.display_name])
		print("  %-24s %8s %8s %8s" % ["party (left out)", "end HP%", "secs", "loss%"])
		var per_party := []
		var damage_by_source := {}
		var all_secs := []
		for skip in class_ids.size():
			var party_ids := []
			for i in class_ids.size():
				if i != skip:
					party_ids.append(class_ids[i])
			var r := _sample(party_ids, encounter, damage_by_source)
			per_party.append(float(r["end_hp"]))
			all_secs.append(float(r["secs"]))
			hp_points.append(float(r["end_hp"]))
			sec_points.append(float(r["secs"]))
			print("  %-24s %7.1f%% %8.1f %7.0f%%" % [
				"-" + String(class_ids[skip]), 100.0 * float(r["end_hp"]),
				float(r["secs"]), 100.0 * float(r["losses"]) / float(SEEDS),
			])
		var lo := _min(per_party)
		var hi := _max(per_party)
		print("  SPREAD: end HP %.0f%%..%.0f%%, band %.0f points.  duration %.1f..%.1fs" % [
			100.0 * lo, 100.0 * hi, 100.0 * (hi - lo), _min(all_secs), _max(all_secs),
		])
		print("  damage to the party, by source: %s" % _shares(damage_by_source))
		room_rows.append({"id": encounter_id, "band": hi - lo, "hp": (hi + lo) * 0.5,
			"secs": (_min(all_secs) + _max(all_secs)) * 0.5, "dmg": damage_by_source})
		print("")

	print("======== RANKED BY HOW MUCH THE PARTY CHOICE MOVES THE ROOM ========")
	room_rows.sort_custom(func(a, b): return float(a["band"]) > float(b["band"]))
	for r in room_rows:
		print("  %-22s band %5.0f points   mean end HP %3.0f%%   %5.1fs   mechanic damage %3.0f%%" % [
			String(r["id"]), 100.0 * float(r["band"]), 100.0 * float(r["hp"]),
			float(r["secs"]), 100.0 * _mechanic_share(r["dmg"]),
		])
	print("")
	print("  end HP vs duration across all %d party-by-room combinations: r = %+.2f" % [
		hp_points.size(), _pearson(hp_points, sec_points)])
	quit(0)


func _pearson(xs: Array, ys: Array) -> float:
	var n := float(xs.size())
	var mx := 0.0
	var my := 0.0
	for i in xs.size():
		mx += float(xs[i])
		my += float(ys[i])
	mx /= n
	my /= n
	var num := 0.0
	var dx := 0.0
	var dy := 0.0
	for i in xs.size():
		var a := float(xs[i]) - mx
		var b := float(ys[i]) - my
		num += a * b
		dx += a * a
		dy += b * b
	return num / maxf(sqrt(dx * dy), 0.000001)


## How many DISTINCT threats the pickable rooms field, counted over spawns
## rather than over the bestiary.
func _roster_census(encounter_ids: Array) -> void:
	print("======== WHAT THE PICKABLE ROOMS ACTUALLY FIELD ========")
	var totals := {}
	var signatures := {}
	for encounter_id in encounter_ids:
		var encounter := Registry.get_encounter(encounter_id)
		var counts := {}
		for spawn in encounter.enemy_spawns:
			var eid: StringName = spawn["enemy_id"]
			counts[eid] = int(counts.get(eid, 0)) + 1
			totals[eid] = int(totals.get(eid, 0)) + 1
		var keys := counts.keys()
		keys.sort()
		var parts := PackedStringArray()
		for k in keys:
			parts.append("%dx%s" % [int(counts[k]), String(k)])
		var sig := " ".join(parts)
		print("  %-22s %s" % [String(encounter_id), sig])
		if signatures.has(sig):
			print("    ^^ IDENTICAL ROSTER to %s" % String(signatures[sig]))
		else:
			signatures[sig] = encounter_id
	print("")
	var keys := totals.keys()
	keys.sort()
	var spawns := 0
	var with_mechanic := 0
	for k in keys:
		spawns += int(totals[k])
		if MECHANIC.has(k):
			with_mechanic += int(totals[k])
	for k in keys:
		print("  %-16s %3d spawns (%2.0f%% of all)   %s" % [
			String(k), int(totals[k]), 100.0 * float(totals[k]) / float(spawns),
			MECHANIC.get(k, "-- no mechanic, damage only"),
		])
	print("  %d spawns across %d rooms. %d (%.0f%%) carry a mechanic; %d (%.0f%%) only subtract health." % [
		spawns, encounter_ids.size(), with_mechanic, 100.0 * float(with_mechanic) / float(spawns),
		spawns - with_mechanic, 100.0 * float(spawns - with_mechanic) / float(spawns),
	])


func _sample(party_ids: Array, encounter, damage_by_source: Dictionary) -> Dictionary:
	var losses := 0
	var end_hp := 0.0
	var ticks := 0
	for s in SEEDS:
		var party: Array[PawnData] = []
		for cid in party_ids:
			party.append(PawnFactory.make_starter_pawn(cid, StringName("%s_%d" % [cid, party.size()]), String(cid)))
		var state := CombatSim.build(party, encounter, s)
		var outcome := CombatSim.run(state)
		if outcome == CombatState.Outcome.ENEMY_WIN:
			losses += 1
		ticks += state.tick

		var hp := 0
		var hp_max := 0
		for u in state.units:
			if u.team != CG.Team.PLAYER or u.pawn == null:
				continue
			hp += maxi(u.hp, 0)
			hp_max += u.hp_max
		end_hp += float(hp) / float(maxi(hp_max, 1))

		for e in state.events:
			if e.kind != CG.EventKind.DAMAGE:
				continue
			var target := state.unit(e.target_id)
			if target == null or target.team != CG.Team.PLAYER or target.pawn == null:
				continue
			damage_by_source[_source_key(state, e, target)] = int(damage_by_source.get(_source_key(state, e, target), 0)) + e.amount

	return {
		"losses": losses,
		"end_hp": end_hp / float(SEEDS),
		"secs": float(ticks) / float(SEEDS) / float(CG.TICKS_PER_SECOND),
	}


## Who dealt this hit. A DAMAGE with no source is a hazard or a status tick, and
## a source on the player's own team is friendly fire or self-damage.
func _source_key(state, e, target) -> StringName:
	var source = state.unit(e.source_id)
	if source == null:
		return StringName("unsourced:%s" % _type_name(e.damage_type))
	if source.enemy_id != &"":
		return source.enemy_id
	if source.id == target.id:
		return &"SELF-DAMAGE"
	return &"FRIENDLY-FIRE"


func _type_name(t: CG.DamageType) -> String:
	for k in CG.DamageType.keys():
		if CG.DamageType[k] == t:
			return String(k).to_lower()
	return "?"


func _mechanic_share(damage_by_source: Dictionary) -> float:
	var total := 0
	var mech := 0
	for k in damage_by_source:
		total += int(damage_by_source[k])
		## A POISON or BLEED tick lands unsourced, so counting only direct hits
		## understates the mechanic-carriers that applied it. Fire is terrain.
		if MECHANIC.has(k) or k == &"unsourced:profane" or k == &"unsourced:physical":
			mech += int(damage_by_source[k])
	return float(mech) / float(maxi(total, 1))


func _shares(damage_by_source: Dictionary) -> String:
	var keys := damage_by_source.keys()
	keys.sort_custom(func(a, b): return int(damage_by_source[a]) > int(damage_by_source[b]))
	var total := 0
	for k in keys:
		total += int(damage_by_source[k])
	var parts := PackedStringArray()
	for k in keys:
		parts.append("%s %.0f%%" % [String(k), 100.0 * float(damage_by_source[k]) / float(maxi(total, 1))])
	return ", ".join(parts)


func _min(a: Array) -> float:
	var v := float(a[0])
	for x in a:
		v = minf(v, float(x))
	return v


func _max(a: Array) -> float:
	var v := float(a[0])
	for x in a:
		v = maxf(v, float(x))
	return v
