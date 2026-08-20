extends SceneTree

## What a real fight would actually sound like, and what the placeholders
## actually are.
##
##   godot --headless --path . --script res://Tools/SoundProbe.gd
##
## Headless is fine here: nothing is drawn and nothing is played. This measures
## the stream and writes the waveforms out.
##
## OWNED BY sable (`Scripts/Audio/**`, `Assets/Audio/**`).
##
## WHY THIS EXISTS AND WHAT IT CANNOT DO
##
## **I cannot hear anything.** So the one check that would settle whether these
## six placeholders are distinguishable -- listening to them with your eyes shut
## -- is not available to me, and I am not going to let a green test stand in for
## it. What this tool does instead is the honest subset:
##
##   1. Runs a real fight and counts what would have been played, per second.
##      That is the buzz question, and it is a measurement rather than my guess.
##   2. Writes the six placeholders out as real .wav files somebody can play.
##
## The first of those is the one that changes decisions. A sound design that is
## right in principle and fires eleven times a second is wrong in practice, and
## this project has already paid for a signal that fired so often it became
## furniture.
##
## The waveform picture is `Tools/SoundSheet.tscn` and not this file. It was here
## first, drawn straight into an `Image`, and rendering it is what showed why it
## could not stay: an `Image` cannot draw text, so the sheet was six unlabelled
## waveforms and nobody could tell which one was DEATH. That is this project's own
## house rule failing in my own file -- a picture may replace decoration and it
## may not replace information -- and it was invisible until I looked at it.


const OUT_DIR := "res://Screenshots/sound_placeholders"
const SEEDS := 8

func _init() -> void:
	_write_placeholders()
	_measure_fights()
	quit(0)

## The six blips as real files, so a human can play them. Written under
## `Screenshots/` rather than `Assets/Audio/` on purpose: a file in `Assets/Audio`
## would be picked up by the drop-in and would then have to be deleted before the
## player's first real sound worked. Generated defaults get out of the way by
## themselves; committed ones do not.
func _write_placeholders() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	print("PLACEHOLDERS")
	for kind in SoundBank.PLACEHOLDER_VOICES.keys():
		var name := String(CG.EventKind.keys()[kind]).to_lower()
		var wav: AudioStreamWAV = SoundBank.placeholder_for(kind)
		var path := "%s/%s.wav" % [OUT_DIR, name]
		wav.save_to_wav(path)
		var peak := _peak(wav.data)
		print("  %-14s %5.0f Hz  %5.2f s  peak %.2f  -> %s" % [
			name, SoundBank.PLACEHOLDER_VOICES[kind][0],
			float(wav.data.size() / 2) / float(SoundBank.MIX_RATE), peak, path])
		# A placeholder that is silent is worse than none: it looks like the
		# pipeline working and sounds like it failing. Said here rather than only
		# in a test, because this is the tool a human runs.
		if peak < 0.02:
			printerr("  ^ SILENT. A placeholder that cannot be heard proves nothing.")

func _peak(data: PackedByteArray) -> float:
	var peak := 0
	var i := 0
	while i < data.size():
		peak = maxi(peak, absi(data.decode_s16(i)))
		i += 2
	return float(peak) / 32767.0

## The buzz question, answered with the real simulation and real content rather
## than by reasoning about it.
func _measure_fights() -> void:
	var encounter := Registry.get_encounter(CG.DEFAULT_ENCOUNTER)
	if encounter == null:
		printerr("no default encounter; nothing to measure")
		return
	var party_ids := Registry.all_class_ids().slice(0, 4)

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
			emitted_per_kind[ek] = int(emitted_per_kind.get(ek, 0)) + 1
			if e.tick != tick:
				tick = e.tick
				for n in per_source.values():
					layer_hist[n] = int(layer_hist.get(n, 0)) + 1
				per_source.clear()
				this_tick.clear()
				in_tick = 0
			var name := SoundBank.sound_name(e)
			if this_tick.has(name):
				continue
			if SoundBank.stream_for_event(e) == null:
				continue
			this_tick[name] = true
			in_tick += 1
			busiest = maxi(busiest, in_tick)
			total_played += 1
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

	var seconds := float(total_ticks) / float(CG.TICKS_PER_SECOND)
	print("")
	print("A REAL FIGHT, %d seeds of %s, %s" % [SEEDS, CG.DEFAULT_ENCOUNTER, _short(party_ids)])
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
	# Emitted beside played, because the interesting decisions are all in the
	# gap. A kind with a large emitted count and a zero played count is a
	# deliberate silence, and reading only the played column hides every one of
	# them -- which is how the first version of this file shipped a drone.
	print("  by kind, emitted -> played:")
	var keys: Array = emitted_per_kind.keys()
	keys.sort()
	for k in keys:
		print("    %-16s %5d -> %5d" % [k, emitted_per_kind[k], int(per_kind.get(k, 0))])
	var silent: Array[String] = []
	for kind in CG.EventKind.values():
		if not SoundBank.PLACEHOLDER_VOICES.has(kind):
			silent.append(String(CG.EventKind.keys()[kind]).to_lower())
	print("  silent by default:  ", ", ".join(silent))
	print("  (any of those gets a voice by dropping Assets/Audio/event/<name>.ogg in)")

func _short(ids: Array) -> String:
	var out: Array[String] = []
	for i in ids:
		out.append(String(i))
	return "+".join(out)
