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
	var ok := await _run()
	get_tree().quit(0 if ok else 1)

func _party(party_ids: Array) -> Array[PawnData]:
	var party: Array[PawnData] = []
	for i in party_ids.size():
		party.append(PawnFactory.make_starter_pawn(
			party_ids[i], StringName("p%d" % i), String(party_ids[i])))
	return party

func _encounter():
	return RoomLibrary.get_room(CG.DEFAULT_ENCOUNTER)

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

## A run that spent its whole frame budget and barely moved is not a short
## fight, it is a view that stopped stepping, and its sound counts are not a
## measurement. Seen once at tick 17 of a possible 450 and never reproduced
## (#571). Static and pure so the guard's fire path can be proven without
## driving a real fight -- see `Tests/test_sound_in_fight_stall_guard.gd`.
static func is_stalled(outcome: int, frames_spent: int, frame_budget: int, tick: int, frames_per_tick: int) -> bool:
	return outcome == CombatState.Outcome.UNRESOLVED \
		and frames_spent >= frame_budget and tick < frame_budget / frames_per_tick / 2

## `SOUND_IN_FIGHT_FRAMES` overrides the frame budget per party. Only the
## stall-guard tests use it, to make a stall happen on demand instead of
## waiting for the one-run-in-three it was filed against (#571).
func _frame_budget() -> int:
	var raw := OS.get_environment("SOUND_IN_FIGHT_FRAMES")
	if raw == "":
		return FRAMES
	return int(raw)

## Runs every swept party and returns whether the result is trustworthy.
## A stalled party's counts are kept OUT of the totals below -- #571 was
## filed because a stalled run used to blend into them and print a normal-
## looking table with no visible sign anything had gone wrong.
func _run() -> bool:
	var played: Dictionary = {}
	var busiest := 0
	var frames_with_sound := 0
	var voice_count := 0
	var stalled_parties: Array[String] = []
	var total_steals := 0
	var frame_budget := _frame_budget()
	var parties := ScreenSweepScript.sweep_parties(ClassLibrary.all_ids())
	for party_ids in parties:
		await _build_view(party_ids)
		var voices := _voices()
		voice_count = voices.size()
		print("SoundInFight: %s, %d voices" % [", ".join(PackedStringArray(party_ids)), voices.size()])
		if voices.is_empty():
			printerr("SoundInFight: NO VOICES. The game is silent; that is the defect in #514.")
			return false
		var was_playing: Array[bool] = []
		for v in voices:
			was_playing.append(false)

		var frames_spent := 0
		var party_played: Dictionary = {}
		var party_busiest := 0
		var party_frames_with_sound := 0
		for f in frame_budget:
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
						party_played[n] = int(party_played.get(n, 0)) + 1
				was_playing[i] = playing
			party_busiest = maxi(party_busiest, live)
			if live > 0:
				party_frames_with_sound += 1
		print("  reached tick %d, outcome %d, %d frames spent" % [
			_view.state.tick, _view.state.outcome, frames_spent])
		var stalled := is_stalled(_view.state.outcome, frames_spent, frame_budget, _view.state.tick, FRAMES_PER_TICK)
		if stalled:
			printerr("SoundInFight: STALLED at tick %d after %d frames. NOT A MEASUREMENT -- excluded from the totals below." % [
				_view.state.tick, frames_spent])
			stalled_parties.append(", ".join(PackedStringArray(party_ids)))
		else:
			busiest = maxi(busiest, party_busiest)
			frames_with_sound += party_frames_with_sound
			for n in party_played:
				played[n] = int(played.get(n, 0)) + int(party_played[n])
			var bank = _view.sound_bank()
			if bank != null:
				total_steals += bank.steals()
		await _shot(party_ids[0])
		_view.queue_free()
		_view = null
		await get_tree().process_frame

	print("  frames with something audible   %d" % frames_with_sound)
	print("  most voices sounding at once    %d of %d" % [busiest, voice_count])
	print("  sounds cut off mid-play (#569)  %d" % total_steals)
	var names: Array = played.keys()
	names.sort()
	print("  SOUNDS ACTUALLY HEARD:")
	for n in names:
		print("    %-40s %d" % [n, played[n]])
	if played.is_empty():
		printerr("SoundInFight: NOT ONE SOUND STARTED. The wiring does not work.")
	if played.has("unknown"):
		printerr("SoundInFight: a voice played a stream no name resolves to.")
	if not stalled_parties.is_empty():
		printerr("SoundInFight: %d of %d part(ies) STALLED and are NOT in the table above: %s" % [
			stalled_parties.size(), parties.size(), ", ".join(PackedStringArray(stalled_parties))])
		printerr("SoundInFight: NOT A FULL MEASUREMENT. Re-run.")
	return stalled_parties.is_empty()

func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := "%s/wren_550_sound_in_fight_%s.png" % [OUT_DIR, tag]
	get_viewport().get_texture().get_image().save_png(path)
	print("SoundInFight: %s" % path)
