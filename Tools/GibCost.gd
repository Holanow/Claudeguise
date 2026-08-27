extends Node

## Issue 589. Two questions, and the first one decides the second: how many
## explosions does a real fight want alive at once, and what does throwing a
## body apart cost a whole rendered frame at 14 and at 100 units?
##
## SAMPLING MOMENT: the demand half reads `state.events` after `step()` and
## nothing else -- the same events `BattleView.consume_events` drains.
##
## The cost half copies `Tools/HandCost._cost` deliberately, so the numbers can
## be compared: a whole rendered frame, wall clock, vsync off, 240 frames,
## bodies cloned up to the count, one variable.

const ScreenSweepScript := preload("res://Tools/ScreenSweep.gd")
const DeathExplosionScript := preload("res://Scripts/UI/DeathExplosion.gd")
const ImpactBurstScript := preload("res://Scripts/UI/ImpactBurst.gd")
const SEED := 7
const COST_FRAMES := 240
const FRAMES_PER_TICK := 4

var _view: Node2D = null

func _ready() -> void:
	Offscreen.hide_window(self)
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("GibCost: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	var demand := _demand()
	for units in [14, 100]:
		await _cost(units, false, demand)
		await _cost(units, true, demand)
	get_tree().quit(0)

func _party(ids: Array) -> Array[PawnData]:
	var out: Array[PawnData] = []
	for i in ids.size():
		out.append(PawnFactory.make_starter_pawn(
			ids[i], StringName("p%d" % i), String(ids[i])))
	return out

## How many explosions would be in the air at once. One lives
## `DeathExplosion.LIFETIME`, so the answer at any tick is how many DEATH events
## landed in the window of ticks that long ending there.
##
## Pool pressure on `ImpactBurst` is counted here as well, because a death now
## spends slots in BOTH pools: the killing blow's own debris, plus
## `DEATH_BURSTS` more from `death_burst`.
func _demand() -> Dictionary:
	var window := int(ceil(DeathExplosionScript.LIFETIME / CG.TICK_SECONDS))
	var burst_window := int(ceil(ImpactBurstScript.LIFETIME / CG.TICK_SECONDS))
	var worst := 0
	var worst_where := ""
	var worst_bursts := 0
	var most_in_a_tick := 0
	var deaths_per_fight: Array[int] = []
	var samples: Array[int] = []
	for encounter_id in Registry.pickable_encounter_ids():
		var encounter = Registry.get_encounter(encounter_id)
		for party_ids in ScreenSweepScript.sweep_parties(ClassLibrary.all_ids()):
			var state := CombatSim.build(_party(party_ids), encounter, SEED)
			var deaths: Array[int] = []
			var hits: Array[int] = []
			var cursor := 0
			var total_deaths := 0
			while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
				CombatSim.step(state)
				var n := 0
				var h := 0
				for i in range(cursor, state.events.size()):
					var e := state.events[i]
					if e.kind == CG.EventKind.DEATH:
						n += 1
					elif e.kind == CG.EventKind.DAMAGE and e.action_id != &"":
						h += 1
				cursor = state.events.size()
				deaths.append(n)
				hits.append(h)
				total_deaths += n
				most_in_a_tick = maxi(most_in_a_tick, n)
				var alive := 0
				for j in range(maxi(0, deaths.size() - window), deaths.size()):
					alive += deaths[j]
				samples.append(alive)
				# Both pools, in the burst's own shorter window: the hit that
				# killed throws debris, and the death throws DEATH_BURSTS more.
				var slots := 0
				for j in range(maxi(0, hits.size() - burst_window), hits.size()):
					slots += hits[j] + deaths[j] * ImpactBurstScript.DEATH_BURSTS
				worst_bursts = maxi(worst_bursts, slots)
				if alive > worst:
					worst = alive
					worst_where = "%s / %s tick %d" % [
						encounter_id, "-".join(PackedStringArray(party_ids)), state.tick]
			deaths_per_fight.append(total_deaths)
	samples.sort()
	var p99: int = 0 if samples.is_empty() else samples[int(samples.size() * 0.99)]
	var mean_deaths := 0.0
	for d in deaths_per_fight:
		mean_deaths += float(d)
	mean_deaths = 0.0 if deaths_per_fight.is_empty() else mean_deaths / float(deaths_per_fight.size())
	print("GibCost demand: %d fights over %d rooms, %d ticks sampled, window %d ticks (%.2fs)" % [
		deaths_per_fight.size(), Registry.pickable_encounter_ids().size(),
		samples.size(), window, DeathExplosionScript.LIFETIME])
	print("  explosions alive at once: worst %d (%s), 99th %d, mean deaths a fight %.1f" % [
		worst, worst_where, p99, mean_deaths])
	print("  most DEATH events in one tick: %d" % most_in_a_tick)
	print("  pool is %d explosions; %s" % [DeathExplosionScript.POOL,
		"the worst case fits" if worst <= DeathExplosionScript.POOL
		else "THE WORST CASE RECYCLES %d" % (worst - DeathExplosionScript.POOL)])
	print("  ImpactBurst slots wanted at once, hits AND deaths: worst %d of %d" % [
		worst_bursts, ImpactBurstScript.POOL])
	return {"worst": worst, "per_tick": most_in_a_tick}

func _build_view(party_ids: Array) -> void:
	var cfg := RunConfig.new()
	cfg.party = _party(party_ids)
	cfg.encounter_id = Registry.all_encounter_ids()[0]
	cfg.seed = SEED
	var packed: PackedScene = load("res://Scenes/Battle.tscn")
	_view = packed.instantiate()
	add_child(_view)
	await get_tree().process_frame
	_view.begin_with_encounter(cfg, Registry.get_encounter(Registry.all_encounter_ids()[0]))
	_view.set_process(false)

func _clone(src: CombatUnit, id: int) -> CombatUnit:
	var out := CombatUnit.new()
	for p in src.get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			out.set(p.name, src.get(p.name))
	out.id = id
	out.position = Vector2(
		randf_range(-CG.ARENA_HALF_WIDTH, CG.ARENA_HALF_WIDTH),
		randf_range(-CG.ARENA_HALF_HEIGHT, CG.ARENA_HALF_HEIGHT))
	return out

## The pool is kept FULL for the whole run rather than fed at the measured rate:
## the question a cost number has to answer is what the worst frame costs, and
## the worst frame is the one where every slot is drawing.
func _cost(units: int, explode: bool, demand: Dictionary) -> void:
	seed(SEED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayOptions.reset()
	DisplayOptions.set_enabled(DeathExplosionScript.OPTION, explode)
	var party_ids: Array = ScreenSweepScript.sweep_parties(ClassLibrary.all_ids())[0]
	await _build_view(party_ids)
	var state: CombatState = _view.state
	var source: Array = state.units.duplicate()
	while state.units.size() < units:
		state.units.append(_clone(source[state.units.size() % source.size()], state.units.size()))
	_view._ensure_unit_views()
	await RenderingServer.frame_post_draw

	var peak := 0
	var frames := 0
	var thrown := 0
	var t0 := Time.get_ticks_usec()
	for i in COST_FRAMES:
		_view._process(CG.TICK_SECONDS / float(FRAMES_PER_TICK))
		if explode and i % FRAMES_PER_TICK == 0:
			var u: CombatUnit = state.units[thrown % state.units.size()]
			var shape := UnitView.shape_id(u)
			_view._gibs.explode(u.position, UnitView.display_radius(u),
				UnitView.facing_left(u), UnitArt.fragments_for(shape, u.team), u.id)
			_view._bursts.death_burst(u.position, Palette.team_color(u.team))
			thrown += 1
			peak = maxi(peak, _view._gibs.live_explosions())
		await RenderingServer.frame_post_draw
		frames += 1
	var spent := Time.get_ticks_usec() - t0
	print("GibCost: %d units, explosions %-3s: %d us per rendered frame (n=%d, peak %d alive, %d chunks drawn)" % [
		state.units.size(), "on" if explode else "off",
		0 if frames == 0 else spent / frames, frames, peak, _view._gibs.live_pieces()])
	DisplayOptions.reset()
	_view.queue_free()
	_view = null
	await get_tree().process_frame
