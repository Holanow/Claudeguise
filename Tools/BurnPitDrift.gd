extends SceneTree

## Where did the burn pit's health effect go? Four builds, one measurement.
##
##     godot --headless --path . --script res://Tools/BurnPitDrift.gd
##
## Issue #225 records the burn pit's `total` health aggregate falling 117 -> 90
## -> 52 across three merges and asks whether that is erosion across three
## changes or one change taking most of it. Neither `BurnPitSize` nor
## `FireOutput` answers that, because both only run on the build they ship with.
##
## This one is written to be **copied into a detached checkout of an old commit
## and run there**, so it uses nothing newer than `CombatSim`, `Registry` and
## `state.events`. Its output is one block per build and the blocks are meant to
## be read side by side.
##
## It prints three quantities at one fixed sample, because mixing sample sizes
## into a cross-build comparison is how you attribute noise to a commit:
##
##   - **the per-party health deltas, and the two aggregates over them.** This
##     is the quantity #225 is about, and it is a difference of two arms, so
##     anything that moves the bare arm moves it.
##   - **the health the fire itself dealt, per team, per fight.** Not a
##     difference of two arms at all, so a fire that is genuinely doing less
##     work shows here and a party that merely got better at the bare room does
##     not.
##   - **fight length in both arms.** The stated mechanism for every step of the
##     drift is "the fight got shorter, so less of it is spent burning". That is
##     checkable rather than assertable, and this is the number that checks it.
##
## Measurement only, never gated.
##
## **The answer it gave, at 40 seeds on five builds (issue #225):**
##
##     build                          total  largest   fire dealt per fight     ticks
##                                                     party  enemy   both   fire  bare
##     5a37a6a  before #163              82      42    368.7  754.6 1123.3    238   555
##     14085bb  #163 step around fire   123      46     25.4  157.5  182.8    378   555
##     75df176  #172 rage starts at 0    73      40     50.0  259.8  309.8    466   478
##     b20284e  #222, twelve merges on   73      40     49.4  259.5  308.9    462   473
##     beabec6  #214 usable actions      54      27     52.4  139.3  191.7    377   432
##     0fcfaf8  trunk today              67      30     93.3  183.5  276.8    386   423
##
## Not erosion. #214 is the only bite, the twelve merges before it took
## nothing, and the fire's own output is higher today than on the build that
## scored the record `total`. #163 cut the burning sixfold and `total` went
## **up**, which is the clearest thing in the table: the aggregate and the
## mechanic it is supposed to measure disagree about direction.

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const Encounter := preload("res://Scripts/Core/Encounter.gd")

const SEEDS := 40


func _class_ids_in_a_stable_order() -> Array[StringName]:
	var names := PackedStringArray()
	for id in Registry.all_class_ids():
		names.append(String(id))
	names.sort()
	var out: Array[StringName] = []
	for n in names:
		out.append(StringName(n))
	return out


func _buildable_parties() -> Array:
	var class_ids := _class_ids_in_a_stable_order()
	var out := []
	for skip in class_ids.size():
		var party: Array[StringName] = []
		for i in class_ids.size():
			if i != skip:
				party.append(class_ids[i])
		out.append(party)
	return out


func _pawns(ids: Array, seed: int) -> Array[PawnData]:
	var out: Array[PawnData] = []
	for i in ids.size():
		out.append(PawnFactory.make_starter_pawn(ids[i], StringName("%s_%d_%d" % [ids[i], seed, i]), String(ids[i])))
	return out


func _without_terrain(enc: Encounter) -> Encounter:
	var e := Encounter.new()
	e.id = enc.id
	e.display_name = enc.display_name
	e.enemy_spawns = enc.enemy_spawns
	e.party_spawns = enc.party_spawns
	e.terrain = []
	return e


## Pawns only. A summon carries an `enemy_id` and a pawn never does.
func _party_hp_percent(state: CombatState) -> int:
	var hp := 0
	var hp_max := 0
	for u in state.units:
		if u.team != CG.Team.PLAYER or u.enemy_id != &"":
			continue
		hp += maxi(0, u.hp)
		hp_max += u.hp_max
	if hp_max <= 0:
		return 0
	return int(round(100.0 * float(hp) / float(hp_max)))


## Health taken from terrain, as [party, enemy]. `_tick_hazards` emits DAMAGE
## with `source_id == -1`, an empty `action_id` and `status` left at its default
## SHIELD; a damage-over-time tick sets BURN, POISON or BLEED, so SHIELD
## separates the two and cannot collide.
func _fire_damage(state: CombatState) -> Array:
	var mine := 0
	var theirs := 0
	for e in state.events:
		if e.kind != CG.EventKind.DAMAGE or e.source_id != -1 or e.action_id != &"":
			continue
		if e.status != CG.Status.SHIELD:
			continue
		var u := state.unit(e.target_id)
		if u == null:
			continue
		if u.team == CG.Team.PLAYER:
			mine += e.amount
		else:
			theirs += e.amount
	return [mine, theirs]


func _init() -> void:
	var enc := Registry.get_encounter(&"floor1_hazard")
	var bare := _without_terrain(enc)
	var parties := _buildable_parties()

	var largest := 0
	var total := 0
	var deltas := []
	var fire_party := 0
	var fire_enemy := 0
	var fights := 0
	var ticks_fire := 0
	var ticks_bare := 0

	print("floor1_hazard at %d seeds x %d buildable parties" % [SEEDS, parties.size()])
	print("%-56s %6s %6s %8s %8s" % ["party", "delta", "fire", "hp fire", "hp bare"])
	for ids in parties:
		var burnt := 0
		var plain := 0
		var pf := 0
		var ef := 0
		for seed in SEEDS:
			var a := CombatSim.build(_pawns(ids, seed), enc, seed)
			CombatSim.run(a)
			var b := CombatSim.build(_pawns(ids, seed), bare, seed)
			CombatSim.run(b)
			burnt += _party_hp_percent(a)
			plain += _party_hp_percent(b)
			ticks_fire += a.tick
			ticks_bare += b.tick
			var d := _fire_damage(a)
			pf += d[0]
			ef += d[1]
			fights += 1
		var delta := (burnt - plain) / SEEDS
		deltas.append(delta)
		largest = maxi(largest, absi(delta))
		total += absi(delta)
		fire_party += pf
		fire_enemy += ef
		print("%-56s %+6d %6.1f %8d %8d" % [
			str(ids), delta, float(pf + ef) / SEEDS, burnt / SEEDS, plain / SEEDS,
		])

	print("deltas      %s" % str(deltas))
	print("largest     %d" % largest)
	print("total       %d" % total)
	print("fire party  %.1f per fight" % (float(fire_party) / fights))
	print("fire enemy  %.1f per fight" % (float(fire_enemy) / fights))
	print("fire both   %.1f per fight" % (float(fire_party + fire_enemy) / fights))
	print("ticks fire  %.1f per fight" % (float(ticks_fire) / fights))
	print("ticks bare  %.1f per fight" % (float(ticks_bare) / fights))

	# The control that stops this being the sixteen-passing-tests failure: with
	# the terrain stripped the fire columns must read exactly zero, and the two
	# arms of an identical pair must differ by nothing at all.
	var c := 0
	for ids in parties:
		for seed in 4:
			var s := CombatSim.build(_pawns(ids, seed), bare, seed)
			CombatSim.run(s)
			var d := _fire_damage(s)
			c += d[0] + d[1]
	var x := CombatSim.build(_pawns(parties[0], 0), enc, 0)
	CombatSim.run(x)
	var y := CombatSim.build(_pawns(parties[0], 0), enc, 0)
	CombatSim.run(y)
	print("CONTROL     hazard of paint burnt %d (must be 0); identical arms differ by %d hp, %d ticks (must be 0, 0)" % [
		c, _party_hp_percent(x) - _party_hp_percent(y), x.tick - y.tick,
	])
	quit()
