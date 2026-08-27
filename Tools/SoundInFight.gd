extends Node

## Issue 550: does the shipping game actually make a noise, and which ones?
##
## A windowed run with a real audio driver, driving `Battle.tscn` frame by frame
## and reading the voices `SoundBank` owns. Headless cannot answer this -- it has
## a dummy audio driver -- and neither can the suite, which never runs a fight
## through `_process`. This is the instrument that would have caught #514.

const OUT_DIR := "res://Screenshots"
const SEED := 7
const FRAMES_PER_TICK := 4
const FRAMES := 1800
const ScreenSweepScript := preload("res://Tools/ScreenSweep.gd")

var _view: Node2D = null

func _ready() -> void:
	Offscreen.hide_window(self)
	await _run()
	get_tree().quit(0)

func _party(party_ids: Array) -> Array[PawnData]:
	var party: Array[PawnData] = []
	for i in party_ids.size():
		party.append(PawnFactory.make_starter_pawn(
			party_ids[i], StringName("p%d" % i), String(party_ids[i])))
	return party

func _encounter():
	return Registry.get_encounter(CG.DEFAULT_ENCOUNTER)

func _build_view(party_ids: Array) -> void:
	var cfg := RunConfig.new()
	cfg.party = _party(party_ids)
	cfg.encounter_id = CG.DEFAULT_ENCOUNTER
	cfg.seed = SEED
	var packed: PackedScene = load("res://Scenes/Battle.tscn")
	_view = packed.instantiate()
	add_child(_view)
	await get_tree().process_frame
	_view.begin_with_encounter(cfg, _encounter())
	_view.set_process(false)

## Every voice the battle screen owns, found through the tree rather than through
## the view's own field: the claim under test is that the SCENE makes a noise.
func _voices() -> Array:
	var out: Array = []
	var holder := _view.get_node_or_null("Sound")
	if holder == null:
		return out
	for child in holder.get_children():
		if child is AudioStreamPlayer:
			out.append(child)
	return out

## Which name a stream belongs to, by identity. `SoundBank` caches one stream per
## name, so the object on the voice IS the object the name resolves to -- no
## filename is read back and nothing is guessed at.
func _name_of(stream: AudioStream) -> String:
	for name in SoundBank.PLACEHOLDER_VOICES:
		if SoundBank.stream_for(name) == stream:
			return String(name)
		if SoundBank.placeholder_for(name) == stream:
			return "%s (BLIP, no file)" % String(name)
	return "unknown"

func _run() -> void:
	var played: Dictionary = {}
	var busiest := 0
	var frames_with_sound := 0
	var voice_count := 0
	for party_ids in ScreenSweepScript.sweep_parties(ClassLibrary.all_ids()):
		await _build_view(party_ids)
		var voices := _voices()
		voice_count = voices.size()
		print("SoundInFight: %s, %d voices" % [", ".join(PackedStringArray(party_ids)), voices.size()])
		if voices.is_empty():
			printerr("SoundInFight: NO VOICES. The game is silent; that is the defect in #514.")
			return
		var was_playing: Array[bool] = []
		for v in voices:
			was_playing.append(false)

		var frames_spent := 0
		for f in FRAMES:
			if _view.state.outcome != CombatState.Outcome.UNRESOLVED:
				break
			frames_spent += 1
			_view._process(CG.TICK_SECONDS / float(FRAMES_PER_TICK))
			await get_tree().process_frame
			var live := 0
			for i in voices.size():
				var v: AudioStreamPlayer = voices[i]
				var playing: bool = v.playing
				if playing:
					live += 1
					# A start, not a continuation: the voice was idle last frame,
					# or the round robin swapped a stream under it.
					if not was_playing[i]:
						var n := _name_of(v.stream)
						played[n] = int(played.get(n, 0)) + 1
				was_playing[i] = playing
			busiest = maxi(busiest, live)
			if live > 0:
				frames_with_sound += 1
		print("  reached tick %d, outcome %d, %d frames spent" % [
			_view.state.tick, _view.state.outcome, frames_spent])
		# A run that spent every frame and barely moved is not a short fight, it
		# is a view that stopped stepping, and its sound counts are not a
		# measurement. Seen once at tick 17 of a possible 450 and never
		# reproduced; without this it reports as an ordinary quiet fight.
		var stalled: bool = _view.state.outcome == CombatState.Outcome.UNRESOLVED \
			and frames_spent >= FRAMES and _view.state.tick < FRAMES / FRAMES_PER_TICK / 2
		if stalled:
			printerr("SoundInFight: STALLED at tick %d after %d frames. NOT A MEASUREMENT." % [
				_view.state.tick, frames_spent])
		await _shot(party_ids[0])
		_view.queue_free()
		_view = null
		await get_tree().process_frame

	print("  frames with something audible   %d" % frames_with_sound)
	print("  most voices sounding at once    %d of %d" % [busiest, voice_count])
	var names: Array = played.keys()
	names.sort()
	print("  SOUNDS ACTUALLY HEARD:")
	for n in names:
		print("    %-40s %d" % [n, played[n]])
	if played.is_empty():
		printerr("SoundInFight: NOT ONE SOUND STARTED. The wiring does not work.")
	if played.has("unknown"):
		printerr("SoundInFight: a voice played a stream no name resolves to.")

func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := "%s/wren_550_sound_in_fight_%s.png" % [OUT_DIR, tag]
	get_viewport().get_texture().get_image().save_png(path)
	print("SoundInFight: %s" % path)
