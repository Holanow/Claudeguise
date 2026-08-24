extends Node

## Issue 517. Two questions, and the first one decides the second: how many
## bursts does a real scrum want alive at once, and what does the pool cost a
## whole rendered frame at 14 and at 100 units?
##
## SAMPLING MOMENT: the demand half reads `state.events` after `step()` and
## nothing else -- the same events `BattleView.consume_events` drains.
##
## The cost half copies `Tools/AttachDriftShot._cost` deliberately, so the two
## numbers can be compared: a whole rendered frame, wall clock, vsync off, 240
## frames, bodies cloned up to the count.

const ScreenSweepScript := preload("res://Tools/ScreenSweep.gd")
const ImpactBurstScript := preload("res://Scripts/UI/ImpactBurst.gd")
const SEED := 7
const COST_FRAMES := 240
const FRAMES_PER_TICK := 4

var _view: Node2D = null

func _ready() -> void:
	Offscreen.hide_window(self)
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("ParticleCost: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	var demand := _demand()
	await _cost_all(demand)
	get_tree().quit(0)

func _party(ids: Array) -> Array[PawnData]:
	var out: Array[PawnData] = []
	for i in ids.size():
		out.append(PawnFactory.make_starter_pawn(
			ids[i], StringName("p%d" % i), String(ids[i])))
	return out

## How many bursts would be alive at once. A burst lives `ImpactBurst.LIFETIME`,
## so the answer at any tick is how many DAMAGE events landed in the window of
## ticks that long ending there.
func _demand() -> Dictionary:
	var window := int(ceil(ImpactBurstScript.LIFETIME / CG.TICK_SECONDS))
	var worst := 0
	var worst_where := ""
	var samples: Array[int] = []
	var most_in_a_tick := 0
	for encounter_id in Registry.pickable_encounter_ids():
		var encounter = Registry.get_encounter(encounter_id)
		for party_ids in ScreenSweepScript.sweep_parties(Registry.all_class_ids()):
			var state := CombatSim.build(_party(party_ids), encounter, SEED)
			var per_tick: Array[int] = []
			var cursor := 0
			while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
				CombatSim.step(state)
				var n := 0
				for i in range(cursor, state.events.size()):
					if state.events[i].kind == CG.EventKind.DAMAGE:
						n += 1
				cursor = state.events.size()
				per_tick.append(n)
				most_in_a_tick = maxi(most_in_a_tick, n)
				var alive := 0
				for j in range(maxi(0, per_tick.size() - window), per_tick.size()):
					alive += per_tick[j]
				samples.append(alive)
				if alive > worst:
					worst = alive
					worst_where = "%s / %s tick %d" % [
						encounter_id, "-".join(PackedStringArray(party_ids)), state.tick]
	samples.sort()
	var p99: int = 0 if samples.is_empty() else samples[int(samples.size() * 0.99)]
	var mean := 0.0
	for s in samples:
		mean += float(s)
	mean = 0.0 if samples.is_empty() else mean / float(samples.size())
	print("ParticleCost demand: %d ticks sampled over %d rooms, window %d ticks (%.2fs)" % [
		samples.size(), Registry.pickable_encounter_ids().size(), window, ImpactBurstScript.LIFETIME])
	print("  bursts alive at once: worst %d (%s), 99th %d, mean %.2f" % [
		worst, worst_where, p99, mean])
	print("  most DAMAGE events in one tick: %d" % most_in_a_tick)
	print("  pool is %d bursts x %d particles = %d live particles at the cap" % [
		ImpactBurstScript.POOL, ImpactBurstScript.PER_BURST,
		ImpactBurstScript.POOL * ImpactBurstScript.PER_BURST])
	if worst > ImpactBurstScript.POOL:
		print("  ^ the pool recycles: %d of the worst tick's bursts are cut short" % [
			worst - ImpactBurstScript.POOL])
	return {"worst": worst, "p99": p99, "per_tick": most_in_a_tick}

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

## Copies every script variable, so a field added to CombatUnit later is carried
## without this list rotting. Fabricated bodies for a cost measurement only.
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

func _cost_all(demand: Dictionary) -> void:
	for units in [14, 100]:
		# Scaled with the crowd: fourteen bodies produce the measured rate, and
		# a hundred of the same bodies would produce that many times seven.
		var rate := int(round(float(demand["per_tick"]) * float(units) / 14.0))
		await _cost(units, false, rate)
		await _cost(units, true, rate)

func _cost(units: int, particles: bool, per_tick: int) -> void:
	seed(SEED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayOptions.reset()
	DisplayOptions.set_enabled(&"impact_particles", particles)
	var party_ids: Array = ScreenSweepScript.sweep_parties(Registry.all_class_ids())[0]
	await _build_view(party_ids)
	var state: CombatState = _view.state
	var source: Array = state.units.duplicate()
	while state.units.size() < units:
		state.units.append(_clone(source[state.units.size() % source.size()], state.units.size()))
	_view._ensure_unit_views()
	await RenderingServer.frame_post_draw

	var bursts := 0
	var peak := 0
	var frames := 0
	var t0 := Time.get_ticks_usec()
	for i in COST_FRAMES:
		_view._process(CG.TICK_SECONDS / float(FRAMES_PER_TICK))
		if particles and i % FRAMES_PER_TICK == 0:
			for n in per_tick:
				var u: CombatUnit = state.units[(bursts + n) % state.units.size()]
				_view._bursts.burst(u.position, CG.DamageType.PHYSICAL)
				bursts += 1
			peak = maxi(peak, _view._bursts.live_bursts())
		await RenderingServer.frame_post_draw
		frames += 1
	var spent := Time.get_ticks_usec() - t0
	print("ParticleCost: %d units, particles %s, %d bursts a tick: %d us per rendered frame (n=%d, peak live %d)" % [
		state.units.size(), "on" if particles else "off", per_tick,
		0 if frames == 0 else spent / frames, frames, peak])
	DisplayOptions.reset()
	_view.queue_free()
	_view = null
	await get_tree().process_frame
