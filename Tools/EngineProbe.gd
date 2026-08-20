extends SceneTree

## Measures what Siege Engines actually do in a single room.
##
## **Originally rook's, rewritten by finch on issue 93, and the rewrite is not a
## matter of taste.** Two things had to change and one was a defect:
##
## 1. It reported "distance from each engine to the nearest live enemy, at
##    build" and measured neither. The loop ran over `state.units` *after*
##    `CombatSim.run` had finished, so it used end-of-fight positions, and it had
##    no `alive` check, so it counted corpses as live enemies. That is where the
##    224-unit figure in issue 93 comes from; measured at the tick each engine
##    actually appears, against enemies that are actually alive, it is 381.
##    Doing that requires stepping the fight rather than running it, which is
##    most of the shape change here.
## 2. It could not see the marking window at all, and marked-only firing makes
##    that the number the whole rebuild depends on.
##
## Also widened from one hardcoded party to every buildable party carrying a
## Siege Master, for the reason `SampleFights.gd` already documents at length.
##
##   godot --headless --path . --script res://Tools/EngineProbe.gd
##
## Not part of the game and not part of the gate.
##
## ISSUE 93. The player watched a real fight and said engines never fire and get
## built too fast. This is the instrument for both halves of that, plus the one
## number the artillery rebuild lives or dies by: **how often anything is
## marked at all.** An engine that only fires at marked enemies is exactly as
## useful as marking is frequent, and "engines now hold fire because nothing is
## marked" looks identical, in a never-fired count, to "engines are out of
## range" -- which is the bug being fixed. So the marking window is measured
## directly rather than inferred.
##
## SINGLE ROOM ONLY, per the player: every `Registry` encounter is one room, and
## nothing here composes them into a floor. No `FloorRuns`.
##
## Every party sampled contains a Siege Master, because a party without one
## builds nothing and would only dilute the averages with zeroes.
##
## Determinism: the fight seed is the only randomness. `CombatSim.build(.., s)`
## seeds `state.rng`; this file never calls `randi()` or makes a generator.


const SEEDS := 5
const ENGINE_ID := &"siege_engine"
const ENGINE_ACTION := &"siege_engine_bolt"
const MARK_ACTION := &"spotter_mark"

var _engines_total := 0
var _engines_never_fired := 0
var _engine_shots := 0
var _spawn_distances: Array[float] = []
var _fights := 0
var _peak_engines: Array[int] = []

## Marking is counted two ways on purpose.
##
## `_marked_ticks / _fight_ticks` answers "how much of a fight is something
## marked", which is the ambient number. `_engine_marked_ticks /
## _engine_alive_ticks` answers the question that actually decides whether the
## rebuild worked: **while an engine was standing there, could it have shot at
## anything?** Those two diverge whenever engines exist for a different slice of
## the fight than marks do, and the second is the one to believe.
var _fight_ticks := 0
var _marked_ticks := 0
var _engine_alive_ticks := 0
var _engine_marked_ticks := 0
var _mark_applications := 0
var _build_ticks: Array[int] = []
## Kept from rook's version: how many engines could have shot *without* the
## unlimited range, so the before/after says how much of the change is reach.
var _built_in_old_range := 0
const OLD_BOLT_RANGE := 200.0

func _init() -> void:
	var class_ids := Registry.all_class_ids()
	var encounter_ids := Registry.all_encounter_ids()
	if class_ids.is_empty() or encounter_ids.is_empty():
		printerr("no content registered; nothing to probe")
		quit(1)
		return

	for encounter_id in encounter_ids:
		var encounter := Registry.get_encounter(encounter_id)
		for party_ids in _siege_parties(class_ids):
			for s in SEEDS:
				_probe(party_ids, encounter, s)

	_report()
	quit(0)

## Every party a player can build that contains a Siege Master. `PartySelect`
## allows one card per class and MAX_PARTY_SIZE is 4, so with five classes the
## real parties are the five leave-one-out combinations -- four of which carry a
## Siege Master. Mono-class parties are deliberately absent: `SampleFights.gd`
## already records that balance was steered by `siege_master x4`, a party nobody
## can assemble.
func _siege_parties(class_ids: Array) -> Array:
	var out := []
	if class_ids.size() <= 4:
		if class_ids.has(&"siege_master"):
			out.append(class_ids.duplicate())
		return out
	for skip in class_ids.size():
		var party := []
		for i in class_ids.size():
			if i != skip:
				party.append(class_ids[i])
		if party.has(&"siege_master"):
			out.append(party)
	return out

func _probe(party_ids: Array, encounter, seed_value: int) -> void:
	var party: Array[PawnData] = []
	for cid in party_ids:
		party.append(PawnFactory.make_starter_pawn(cid, StringName("%s_%d" % [cid, party.size()]), String(cid)))
	var state := CombatSim.build(party, encounter, seed_value)

	# Ids of engines seen so far, so a unit appended mid-fight is counted once,
	# on the tick it appears. `state.units` only ever grows by append and ids are
	# stable forever (CombatSim._spawn_summon's own contract), so tracking a
	# high-water mark over the array is enough and needs no event.
	var known := state.units.size()
	var engine_ids := {}
	var peak := 0

	while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
		CombatSim.step(state)

		while known < state.units.size():
			var u: CombatUnit = state.units[known]
			if u.enemy_id == ENGINE_ID:
				engine_ids[u.id] = true
				_engines_total += 1
				var d := _distance_to_nearest_enemy(state, u)
				_spawn_distances.append(d)
				_build_ticks.append(state.tick)
				if d <= OLD_BOLT_RANGE:
					_built_in_old_range += 1
			known += 1

		_fight_ticks += 1
		var any_marked := _any_living_enemy_marked(state)
		if any_marked:
			_marked_ticks += 1
		var live_engines := _living_engine_count(state, engine_ids)
		peak = maxi(peak, live_engines)
		if live_engines > 0:
			_engine_alive_ticks += 1
			if any_marked:
				_engine_marked_ticks += 1

	_fights += 1
	_peak_engines.append(peak)

	# Fired, not hit: "never fired once" is the number the player reported and
	# ACTION_FIRE is emitted the moment the wind-up completes, before any range,
	# line-of-sight or projectile resolution. An engine that fires and misses has
	# still done the thing engines were said never to do.
	var fired := {}
	for e in state.events:
		if e.kind == CG.EventKind.ACTION_FIRE and e.action_id == ENGINE_ACTION:
			fired[e.source_id] = true
			_engine_shots += 1
		elif e.kind == CG.EventKind.STATUS_APPLIED and e.status == CG.Status.MARKED:
			_mark_applications += 1
	for id in engine_ids:
		if not fired.has(id):
			_engines_never_fired += 1

func _distance_to_nearest_enemy(state, unit: CombatUnit) -> float:
	var enemy_team := CG.Team.ENEMY if unit.team == CG.Team.PLAYER else CG.Team.PLAYER
	var best := INF
	for o in state.living(enemy_team):
		best = minf(best, unit.position.distance_to(o.position))
	return 0.0 if best == INF else best

func _any_living_enemy_marked(state) -> bool:
	for u in state.living(CG.Team.ENEMY):
		if u.has_status(CG.Status.MARKED):
			return true
	return false

func _living_engine_count(state, engine_ids: Dictionary) -> int:
	var n := 0
	for id in engine_ids:
		var u: CombatUnit = state.unit(id)
		if u != null and u.alive:
			n += 1
	return n

func _report() -> void:
	print("")
	print("=== EngineProbe: %d fights, single room, Siege Master parties only ===" % _fights)
	print("")
	print("engines built            %d  (%.2f per fight)" % [
		_engines_total, _per_fight(_engines_total)])
	print("peak engines alive at once   mean %.2f  max %d" % [
		_mean_int(_peak_engines), _max_int(_peak_engines)])
	if _engines_total > 0:
		print("engines that never fired %d  (%d%%)" % [
			_engines_never_fired,
			int(round(100.0 * float(_engines_never_fired) / float(_engines_total)))])
		print("shots fired              %d  (%.2f per engine)" % [
			_engine_shots, float(_engine_shots) / float(_engines_total)])
		print("distance to nearest enemy at build   mean %.0f  min %.0f  max %.0f" % [
			_mean(_spawn_distances), _min(_spawn_distances), _max(_spawn_distances)])
		print("within the old 200-unit bolt range at build   %d of %d  (%d%%)" % [
			_built_in_old_range, _engines_total, _percent(_built_in_old_range, _engines_total)])
		print("mean build tick   %.0f  (%.1fs at %d tps)" % [
			_mean_int(_build_ticks), _mean_int(_build_ticks) / float(CG.TICKS_PER_SECOND), CG.TICKS_PER_SECOND])
	print("")
	print("-- the marking window ----------------------------------")
	print("spotter_mark applications      %d  (%.2f per fight)" % [
		_mark_applications, _per_fight(_mark_applications)])
	print("ticks with >=1 enemy MARKED    %d of %d  (%d%% of all fight ticks)" % [
		_marked_ticks, _fight_ticks, _percent(_marked_ticks, _fight_ticks)])
	print("of ticks an engine was alive   %d of %d had a marked enemy  (%d%%)" % [
		_engine_marked_ticks, _engine_alive_ticks, _percent(_engine_marked_ticks, _engine_alive_ticks)])
	print("")

func _per_fight(n: int) -> float:
	return 0.0 if _fights == 0 else float(n) / float(_fights)

func _percent(n: int, of: int) -> int:
	return 0 if of == 0 else int(round(100.0 * float(n) / float(of)))

func _mean(a: Array[float]) -> float:
	if a.is_empty():
		return 0.0
	var t := 0.0
	for x in a:
		t += x
	return t / float(a.size())

func _min(a: Array[float]) -> float:
	var v := a[0]
	for x in a:
		v = minf(v, x)
	return v

func _max(a: Array[float]) -> float:
	var v := a[0]
	for x in a:
		v = maxf(v, x)
	return v

func _mean_int(a: Array[int]) -> float:
	if a.is_empty():
		return 0.0
	var t := 0
	for x in a:
		t += x
	return float(t) / float(a.size())

func _max_int(a: Array[int]) -> int:
	var v := 0
	for x in a:
		v = maxi(v, x)
	return v
