extends SceneTree

## What a real fight would actually sound like, per second, and the placeholders
## written out as real .wav files somebody can play.
##
##   godot --headless --path . --script res://Tools/SoundProbe.gd
##
## Headless is fine: nothing is drawn and nothing is played. Whether the blips
## are distinguishable by ear is not something this can answer.


const OUT_DIR := "res://Screenshots/sound_placeholders"
const SEEDS := 8

## Both rooms, because they answer different halves. `floor1_room1` is the
## default and has no stun in it at all; the Brute lives on `floor1_hazard` and
## is the only source of hard crowd control in the game.
const ROOMS := [CG.DEFAULT_ENCOUNTER, &"floor1_hazard"]

func _init() -> void:
	_report_shipped()
	_write_placeholders()
	for id in ROOMS:
		_measure_fights(id)
	quit(0)

## The six blips as real files, so a human can play them. Written under
## `Screenshots/` rather than `Assets/Audio/` on purpose: a file in `Assets/Audio`
## would be picked up by the drop-in and would then have to be deleted before the
## player's first real sound worked. Generated defaults get out of the way by
## themselves; committed ones do not.
func _write_placeholders() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	print("PLACEHOLDERS")
	for sound_name in SoundBank.PLACEHOLDER_VOICES.keys():
		var name := String(sound_name).replace("event/", "").replace("/", "_")
		var wav: AudioStreamWAV = SoundBank.placeholder_for(sound_name)
		var path := "%s/%s.wav" % [OUT_DIR, name]
		wav.save_to_wav(path)
		var peak := _peak(wav.data)
		print("  %-22s %5.0f Hz  %5.2f s  peak %.2f  -> %s" % [
			name, SoundBank.PLACEHOLDER_VOICES[sound_name][0],
			float(wav.data.size() / 2) / float(SoundBank.MIX_RATE), peak, path])
		# A placeholder that is silent is worse than none: it looks like the
		# pipeline working and sounds like it failing. Said here rather than only
		# in a test, because this is the tool a human runs.
		if peak < 0.02:
			printerr("  ^ SILENT. A placeholder that cannot be heard proves nothing.")

## What each voiced name actually plays. Issue 550 shipped real files, and a
## download that arrived truncated decodes as null and falls back to the blip
## without saying so, which looks exactly like the pipeline working.
func _report_shipped() -> void:
	print("SHIPPED SOUNDS")
	for sound_name in SoundBank.PLACEHOLDER_VOICES.keys():
		var dropped := SoundBank.stream_for(sound_name)
		if dropped == null:
			printerr("  %-32s NO FILE. The blip is what plays here." % String(sound_name))
			continue
		print("  %-32s %5.2f s  %s" % [String(sound_name), dropped.get_length(), dropped.get_class()])

func _peak(data: PackedByteArray) -> float:
	var peak := 0
	var i := 0
	while i < data.size():
		peak = maxi(peak, absi(data.decode_s16(i)))
		i += 2
	return float(peak) / 32767.0

## The buzz question, answered with the real simulation and real content rather
## than by reasoning about it.
func _measure_fights(room_id: StringName) -> void:
	var encounter := Registry.get_encounter(room_id)
	if encounter == null:
		printerr("no encounter %s; nothing to measure" % room_id)
		return
	var class_ids := ClassLibrary.all_ids()

	var total_events := 0
	var total_played := 0
	var total_ticks := 0
	var per_kind: Dictionary = {}
	var emitted_per_kind: Dictionary = {}
	var busiest := 0
	var per_source: Dictionary = {}
	var layered := 0
	# One entry per (tick, unit) that made any noise, keyed by how many.
	var layer_hist: Dictionary = {}
	# Issue 550. A hit stop is 0.10 s of held picture, started when a DEATH is
	# consumed, so it lands BETWEEN one noisy tick and the next rather than
	# inside either. These count the ticks it can put a gap after.
	var noisy_ticks := 0
	var noisy_ticks_with_a_death := 0
	var tick_made_noise := false
	var tick_had_death := false

	for party_ids in _parties(class_ids):
		for s in SEEDS:
			var party: Array[PawnData] = []
			for cid in party_ids:
				party.append(PawnFactory.make_starter_pawn(cid, StringName("%s_%d" % [cid, party.size()]), String(cid)))
			var state := CombatSim.build(party, encounter, s)
			CombatSim.run(state)
			total_ticks += state.tick
			# The de-duplication `play_for` does, reproduced here rather than
			# guessed at: several hits in one tick collapse to one noise, and
			# counting raw events instead would overstate the volume by a lot.
			var tick := -1
			var this_tick: Dictionary = {}
			var in_tick := 0
			for e in state.events:
				total_events += 1
				var ek := String(CG.EventKind.keys()[e.kind])
				if e.kind == CG.EventKind.STATUS_APPLIED:
					ek = "%s/%s" % [ek, String(CG.Status.keys()[e.status]).to_lower()]
				emitted_per_kind[ek] = int(emitted_per_kind.get(ek, 0)) + 1
				if e.tick != tick:
					tick = e.tick
					for n in per_source.values():
						layer_hist[n] = int(layer_hist.get(n, 0)) + 1
					per_source.clear()
					this_tick.clear()
					in_tick = 0
					if tick_made_noise:
						noisy_ticks += 1
						if tick_had_death:
							noisy_ticks_with_a_death += 1
					tick_made_noise = false
					tick_had_death = false
				if e.kind == CG.EventKind.DEATH:
					tick_had_death = true
				var name := SoundBank.sound_name(e)
				if this_tick.has(name):
					continue
				if SoundBank.stream_for_event(e) == null:
					continue
				this_tick[name] = true
				in_tick += 1
				busiest = maxi(busiest, in_tick)
				total_played += 1
				tick_made_noise = true
				per_kind[ek] = int(per_kind.get(ek, 0)) + 1
				# LAYERING: how often ONE unit's own single hit makes more than one
				# noise in the same tick -- the swing, the landing, and the status it
				# applied are three events and one happening. Counted rather than
				# argued about, because whether that reads as a hit with weight or as
				# a stutter is the question I cannot answer by ear and the player can.
				if e.source_id >= 0:
					var key := "%d/%d" % [e.tick, e.source_id]
					per_source[key] = int(per_source.get(key, 0)) + 1
					layered = maxi(layered, int(per_source[key]))
			if tick_made_noise:
				noisy_ticks += 1
				if tick_had_death:
					noisy_ticks_with_a_death += 1
			tick_made_noise = false
			tick_had_death = false

	var seconds := float(total_ticks) / float(CG.TICKS_PER_SECOND)
	print("")
	print("A REAL FIGHT, %s, %d parties x %d seeds, %s" % [
		room_id, _parties(class_ids).size(), SEEDS, _short(class_ids)])
	print("  events emitted      %d" % total_events)
	print("  sounds played       %d  (%.0f%% of events; the rest are deliberately silent)" % [
		total_played, 100.0 * float(total_played) / maxf(1.0, float(total_events))])
	print("  fight seconds       %.1f" % seconds)
	print("  SOUNDS PER SECOND   %.1f   <- the number that decides whether this is a buzz" % [
		float(total_played) / maxf(0.001, seconds)])
	print("  most in one tick    %d  (voice pool is %d)" % [busiest, SoundBank.VOICES])
	var noisy_source_ticks := 0
	var layered_source_ticks := 0
	for n in layer_hist:
		noisy_source_ticks += int(layer_hist[n])
		if int(n) > 1:
			layered_source_ticks += int(layer_hist[n])
	print("  ONE UNIT, ONE TICK, MORE THAN ONE NOISE:  %d of %d  (%.0f%%), worst %d" % [
		layered_source_ticks, noisy_source_ticks,
		100.0 * float(layered_source_ticks) / maxf(1.0, float(noisy_source_ticks)), layered])
	print("    a swing, its landing and the status it applied are three events and")
	print("    one happening. Whether that reads as weight or as a stutter is the")
	print("    one question here that has to be settled by ear.")
	# Issue 550, against #299's premise that hit stop would separate those three.
	# It cannot: they are one batch in one frame, and the freeze starts when the
	# DEATH in that batch is consumed. It buys a gap AFTER a noisy tick.
	var freeze_seconds := float(noisy_ticks_with_a_death) * BattleView.HIT_STOP_SECONDS
	print("  HIT STOP:  %d of %d noisy ticks carry a death  (%.0f%%)" % [
		noisy_ticks_with_a_death, noisy_ticks,
		100.0 * float(noisy_ticks_with_a_death) / maxf(1.0, float(noisy_ticks))])
	print("    it holds %.1f s in total, so the fight runs %.1f s and plays %.1f/s." % [
		freeze_seconds, seconds + freeze_seconds,
		float(total_played) / maxf(0.001, seconds + freeze_seconds)])
	print("    the gap lands AFTER the tick, not inside it: the three noises of one")
	print("    hit are consumed in one frame before the freeze it starts begins.")
	# Emitted beside played, because the interesting decisions are all in the
	# gap. A kind with a large emitted count and a zero played count is a
	# deliberate silence, and reading only the played column hides every one of
	# them -- which is how the first version of this file shipped a drone.
	print("  by kind, emitted -> played:")
	var keys: Array = emitted_per_kind.keys()
	keys.sort()
	for k in keys:
		print("    %-16s %5d -> %5d" % [k, emitted_per_kind[k], int(per_kind.get(k, 0))])
	print("  voiced by default:  ", ", ".join(_voiced_names()))
	print("  (anything else gets a voice by dropping Assets/Audio/<name>.ogg in)")

## The voiced set, read off the table rather than listed. Issue 507 made these
## sound names rather than event kinds, so a status can be voiced alone.
func _voiced_names() -> Array[String]:
	var out: Array[String] = []
	for name in SoundBank.PLACEHOLDER_VOICES.keys():
		out.append(String(name))
	out.sort()
	return out

## Every party a player can actually assemble, leave-one-out above four classes.
## Taking the first four instead measured a game with no Warrior in it; issue 350.
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
		out.append(class_ids)
	return out

func _short(ids: Array) -> String:
	var out: Array[String] = []
	for i in ids:
		out.append(String(i))
	return "+".join(out)
