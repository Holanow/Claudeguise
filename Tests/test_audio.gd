extends "res://Tests/TestCase.gd"


## The audio hook, issue #125. The player asked for hooks and placeholders "to
## make sure the pipeline works", so the load-bearing tests here are the ones
## that write a real file onto disk and assert the game finds it. Reasoning about
## a drop-in proves nothing: the whole claim is about files.

## Issue 550 ships real sounds at the seven voiced names, so a scratch file must
## not be written at one of those: it would either clobber a shipped asset or,
## as a `.wav` beside a shipped `.ogg`, never be reached at all.
const SCRATCH := [
	"res://Assets/Audio/event/fight_start.wav",
	"res://Assets/Audio/event/damage_over_time.wav",
	"res://Assets/Audio/action/scratch_test_action.wav",
	"res://Assets/Audio/event/action_fire.wav",
	"res://Assets/Audio/event/status_applied/burn.wav",
]

func setup() -> void:
	_clear_scratch()

func teardown() -> void:
	_clear_scratch()

func _clear_scratch() -> void:
	for path in SCRATCH:
		DirAccess.remove_absolute(path)
	SoundBank.clear_cache()

## Writes a real, readable audio file. Not an empty file and not a stub: the
## claim under test is that the game reads what a player drops in, and a loader
## that accepts an empty file would pass a test written against one.
func _write_sound(path: String, seconds: float = 0.02) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var count := int(22050 * seconds)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		data.encode_s16(i * 2, int(sin(TAU * 300.0 * float(i) / 22050.0) * 12000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	wav.stereo = false
	wav.data = data
	assert_eq(wav.save_to_wav(path), OK, "could not write the test sound to %s" % path)
	SoundBank.clear_cache()

func _event(kind: CG.EventKind, action_id: StringName = &"") -> CombatEvent:
	var e := CombatEvent.make(kind, 0)
	e.action_id = action_id
	return e

func _status_event(status: CG.Status, action_id: StringName = &"") -> CombatEvent:
	var e := _event(CG.EventKind.STATUS_APPLIED, action_id)
	e.status = status
	return e

## Every name the game can ask for, asked of `sound_name` with a real event
## rather than listed here. A hand-written list would be the second list #299
## refuses, and it would agree with itself while the code moved.
func _all_names() -> Array[String]:
	var names: Array[String] = []
	for kind in CG.EventKind.values():
		if kind == CG.EventKind.STATUS_APPLIED:
			for status in CG.Status.values():
				names.append(String(SoundBank.sound_name(_status_event(status))))
			continue
		names.append(String(SoundBank.sound_name(_event(kind))))
		if kind == CG.EventKind.DAMAGE:
			# The action-less DAMAGE above is the drain; this is the hit.
			names.append(String(SoundBank.sound_name(_event(kind, &"warrior_strike"))))
	return names


# ---------------------------------------------------------------------------
# The pipeline: a file on disk, found with no code change.
# ---------------------------------------------------------------------------

func test_a_dropped_in_sound_is_found_with_no_registration() -> void:
	# The whole feature, end to end. Same shape as the PNG drop-in test in
	# test_art.gd, and for the same reason: this is a claim about the filesystem.
	var path := "res://Assets/Audio/event/fight_start.wav"
	assert_false(FileAccess.file_exists(path), "%s already exists; this test would not prove anything" % path)
	assert_eq(SoundBank.stream_for(&"event/fight_start"), null, "something is already answering to event/fight_start")

	_write_sound(path)
	assert_not_null(SoundBank.stream_for(&"event/fight_start"), "a file dropped into Assets/Audio was not picked up")

	DirAccess.remove_absolute(path)
	SoundBank.clear_cache()
	assert_eq(SoundBank.stream_for(&"event/fight_start"), null, "the override survived its own deletion")


func test_a_file_beats_the_generated_placeholder() -> void:
	# The placeholder must get out of the way, or replacing one means deleting
	# something first. Asserted on the SHIPPED file since #550, which is the
	# same claim with a stronger subject: the sound the player hears today is
	# the one in Assets/Audio, not the blip.
	var event := _event(CG.EventKind.DAMAGE, &"warrior_strike")
	var playing := SoundBank.stream_for_event(event)
	assert_not_null(playing, "DAMAGE resolves to nothing at all")
	assert_eq(playing, SoundBank.stream_for(&"event/damage"),
		"the generated placeholder won over the shipped file")
	assert_not_null(SoundBank.placeholder_for(&"event/damage"),
		"the blip is the documented fallback when the file is deleted; it must still exist")


func test_the_specific_name_wins_over_the_general_one() -> void:
	# The two-level lookup, which is the property that lets one ability have its
	# own sound without the other forty needing one.
	var event := _event(CG.EventKind.ACTION_FIRE, &"scratch_test_action")
	assert_eq(String(SoundBank.sound_name(event)), "event/action_fire",
		"with no specific file present the general name must answer")

	_write_sound("res://Assets/Audio/action/scratch_test_action.wav")
	assert_eq(String(SoundBank.sound_name(event)), "action/scratch_test_action",
		"a file at the specific name did not win")


func test_an_unreadable_name_is_silent_rather_than_an_error() -> void:
	# The negative half. With nothing dropped in, every name answers null, and
	# a test that only checked the found path would pass while this broke.
	for name in ["event/fight_start", "event/nonsense", "action/not_an_action"]:
		assert_eq(SoundBank.stream_for(StringName(name)), null, "%s answered with no file present" % name)
		assert_false(SoundBank.has_sound(StringName(name)))


# ---------------------------------------------------------------------------
# Which events make a noise. The decisions, asserted where they are made.
# ---------------------------------------------------------------------------

func test_damage_over_time_is_silent_and_ordinary_damage_is_not() -> void:
	# The measured split, and the one decision in this file that a number
	# forced: 861 of 1556 damage events in a fight are burn and poison ticking,
	# and giving those the damage sound made a drone. A status tick carries no
	# action_id and that absence is the whole distinction.
	var tick := _event(CG.EventKind.DAMAGE)
	assert_eq(String(SoundBank.sound_name(tick)), "event/damage_over_time")
	assert_eq(SoundBank.stream_for_event(tick), null, "a damage-over-time tick made a noise")

	var hit := _event(CG.EventKind.DAMAGE, &"warrior_strike")
	assert_ne(String(SoundBank.sound_name(hit)), "event/damage_over_time",
		"a real hit was mistaken for a status tick")
	assert_not_null(SoundBank.stream_for_event(hit), "an ordinary hit was silent")


func test_damage_over_time_is_silent_by_default_and_not_by_construction() -> void:
	# It is silent because nobody has filled it in, NOT because something
	# refuses to play it. Without this, a bug that made the name unplayable
	# would look identical to the deliberate silence.
	var tick := _event(CG.EventKind.DAMAGE)
	_write_sound("res://Assets/Audio/event/damage_over_time.wav")
	assert_not_null(SoundBank.stream_for_event(tick),
		"a file dropped in for damage_over_time did not make it audible")


func test_changing_a_shipped_sound_means_replacing_its_file() -> void:
	# The README tells a player this and it is the one instruction #550 changed:
	# `EXTENSIONS` prefers .ogg, so a .wav dropped BESIDE a shipped .ogg is never
	# reached. Turning a voiced kind off is still one file operation -- it is
	# overwriting the file rather than adding one next to it.
	var event := _event(CG.EventKind.ACTION_FIRE, &"warrior_strike")
	assert_true(SoundBank.stream_for_event(event) is AudioStreamOggVorbis,
		"event/action_fire ships no .ogg; the rest of this test is meaningless")
	_write_sound("res://Assets/Audio/event/action_fire.wav")
	assert_true(SoundBank.stream_for_event(event) is AudioStreamOggVorbis,
		"a .wav beside the shipped .ogg was played; the README's instruction is then wrong")


func test_the_voiced_names_are_exactly_the_seven_intended() -> void:
	# Named individually rather than counted. A count passes when one name
	# quietly replaces another, which is the mistake worth catching here.
	var voiced := [
		"event/action_fire", "event/damage", "event/heal", "event/death",
		"event/miss", "event/blocked", "event/status_applied/stun",
	]
	for name in _all_names():
		var has := SoundBank.placeholder_for(StringName(name)) != null
		assert_eq(has, voiced.has(name),
			"%s is %s and should not be" % [name, "voiced" if has else "silent"])


func test_only_stun_is_voiced_and_the_other_twelve_statuses_are_not() -> void:
	# The ruling in #507: hard crowd control gets a sound, the rest do not. Asked
	# through `stream_for_event` rather than of the table, so it covers the
	# resolution as well as the voicing.
	for status in CG.Status.values():
		var event := _status_event(status, &"warrior_strike")
		var audible := SoundBank.stream_for_event(event) != null
		assert_eq(audible, status == CG.Status.STUN,
			"%s is %s and should not be" % [CG.Status.keys()[status], "voiced" if audible else "silent"])


func test_a_status_that_is_silent_is_silent_by_default_and_not_by_construction() -> void:
	# The escape hatch #507 promises: a player who wants to hear their poison
	# land drops one file in. Without this a bug that made the per-status names
	# unplayable would look identical to the deliberate silence.
	var event := _status_event(CG.Status.BURN, &"warrior_strike")
	assert_eq(String(SoundBank.sound_name(event)), "event/status_applied/burn")
	assert_eq(SoundBank.stream_for_event(event), null, "burn is already audible")
	_write_sound("res://Assets/Audio/event/status_applied/burn.wav")
	assert_not_null(SoundBank.stream_for_event(event),
		"a file dropped in for one status did not make it audible")
	assert_eq(SoundBank.stream_for_event(_status_event(CG.Status.POISON, &"warrior_strike")), null,
		"a file dropped in for burn voiced poison as well")


func test_every_event_kind_resolves_to_a_name() -> void:
	# The exhaustiveness guard. `CG.EventKind` has no such guard anywhere else
	# in the project, and swift found the cost of that twice: SUSTAIN_START,
	# SUSTAIN_END and BLOCKED all render as '' in the combat log because a kind
	# was appended and every hand-written match statement stayed as it was.
	for name in _all_names():
		assert_ne(name, "", "an event resolves to an empty sound name")
		assert_true(name.begins_with("event/"),
			"an event resolved to '%s', which is not an event name" % name)
	var seen: Dictionary = {}
	for name in _all_names():
		assert_false(seen.has(name), "%s is the name of two different events" % name)
		seen[name] = true


# ---------------------------------------------------------------------------
# The placeholders themselves.
# ---------------------------------------------------------------------------

func test_every_placeholder_is_actually_audible() -> void:
	# A silent placeholder is the worst possible outcome here: it looks exactly
	# like the pipeline working and sounds exactly like it failing, and the
	# player would be the one to find out.
	for name in SoundBank.PLACEHOLDER_VOICES:
		var stream: AudioStreamWAV = SoundBank.placeholder_for(name)
		var peak := 0
		var i := 0
		while i < stream.data.size():
			peak = maxi(peak, absi(stream.data.decode_s16(i)))
			i += 2
		assert_true(float(peak) / 32767.0 > 0.05,
			"the %s placeholder peaks at %.3f and cannot be heard" % [name, float(peak) / 32767.0])


func test_the_placeholders_are_separable_by_ear() -> void:
	# They exist to be told apart. Pitch and length are the two cues that survive
	# a fight, so no two may share both -- checked as a property of the real
	# table rather than against six numbers typed out again here, which would be
	# the same author agreeing with himself.
	var seen: Dictionary = {}
	for name in SoundBank.PLACEHOLDER_VOICES:
		var v: Array = SoundBank.PLACEHOLDER_VOICES[name]
		var key := "%.0f/%.3f" % [v[0], v[1]]
		assert_false(seen.has(key),
			"%s and %s are the same pitch and the same length" % [name, seen.get(key, "")])
		seen[key] = String(name)


func test_a_placeholder_starts_from_silence() -> void:
	# A raw sine with a hard start clicks, and a click reads as a broken file
	# rather than as a placeholder. The fade is two milliseconds, so the first
	# sample must be effectively zero.
	var stream: AudioStreamWAV = SoundBank.placeholder_for(&"event/death")
	assert_true(absi(stream.data.decode_s16(0)) < 200,
		"the placeholder opens on a click at amplitude %d" % absi(stream.data.decode_s16(0)))


func test_placeholders_are_not_written_into_the_assets_folder() -> void:
	# Generated in memory on purpose. A committed placeholder would sit in
	# Assets/Audio looking exactly like the player's own file, and would have to
	# be deleted before their first real sound worked.
	var dir := DirAccess.open("res://Assets/Audio")
	assert_not_null(dir, "Assets/Audio is missing")
	for f in dir.get_files():
		assert_true(f.get_extension().to_lower() == "md",
			"Assets/Audio ships %s; generated placeholders must not be committed there" % f)


# ---------------------------------------------------------------------------
# Playback policy.
# ---------------------------------------------------------------------------

func test_one_tick_makes_one_noise_per_sound() -> void:
	# Five units landing a hit on the same tick is one noise, not five copies of
	# the same blip a few milliseconds apart -- which is not five times as loud,
	# it is a different and much worse sound.
	var parent := Node.new()
	var bank = SoundBank.attach(parent)
	assert_eq(parent.get_child_count(), SoundBank.VOICES)

	for i in 5:
		bank.play_for(_event(CG.EventKind.DAMAGE, &"warrior_strike"))
	assert_eq(bank._played_this_tick.size(), 1, "the same sound was started more than once in a tick")

	var later := _event(CG.EventKind.DAMAGE, &"warrior_strike")
	later.tick = 1
	bank.play_for(later)
	assert_eq(bank._played_this_tick.size(), 1, "the next tick did not clear the set")

	parent.free()


func test_a_bank_with_no_voices_is_harmless() -> void:
	# `attach` is the supported path, but a bank made directly must not explode:
	# a hook that breaks when set up wrong is a hook that breaks in the one
	# screen nobody tested.
	var bank = SoundBank.new()
	bank.play_for(_event(CG.EventKind.DEATH))
	assert_true(true, "playing into an unattached bank did not raise")


# ---------------------------------------------------------------------------
# The instructions the player reads.
# ---------------------------------------------------------------------------

func test_the_replacement_instructions_name_every_sound() -> void:
	# Assets/Audio/README.md is the file the player uses to drop sounds in. A
	# name missing from it is a sound they cannot name and therefore cannot
	# replace, and they would find out by dropping a file in that never plays.
	var readme := FileAccess.get_file_as_string("res://Assets/Audio/README.md")
	assert_ne(readme, "", "Assets/Audio/README.md is missing")
	for name in _all_names():
		assert_true(readme.contains("%s.ogg" % name),
			"%s is a name the game asks for but Assets/Audio/README.md does not list %s.ogg" % [name, name])
	assert_false(readme.contains("`event/status_applied.ogg`"),
		"event/status_applied.ogg is a dead name since #507; a file dropped there never plays")


const _VOICED_HEADING := "### With a placeholder today"
const _SILENT_HEADING := "### Silent until you drop a file in"

func test_the_instructions_say_which_names_are_voiced() -> void:
	# The test above only asks that a kind is NAMED somewhere in the README, and
	# that is one degree off the question a player asks. They ask "does this one
	# make a noise today", and the README answers it with two tables.
	var readme := FileAccess.get_file_as_string("res://Assets/Audio/README.md")
	assert_ne(readme, "", "Assets/Audio/README.md is missing")
	var voiced_at := readme.find(_VOICED_HEADING)
	var silent_at := readme.find(_SILENT_HEADING)
	assert_true(voiced_at >= 0, "Assets/Audio/README.md has no '%s' heading" % _VOICED_HEADING)
	assert_true(silent_at > voiced_at, "'%s' must come after '%s'" % [_SILENT_HEADING, _VOICED_HEADING])
	var voiced_section := readme.substr(voiced_at, silent_at - voiced_at)
	# Bounded at the next top-level heading rather than running to the end of the
	# file. Read to the end it swept up "Turning a sound off", which names
	# `event/action_fire.ogg` as the example of a kind you silence with a quiet
	# file -- and this test failed on its first run saying action_fire was listed
	# as silent. The prose was right and the slice was wrong.
	var silent_end := readme.find("\n## ", silent_at)
	assert_true(silent_end > silent_at, "no heading closes the silent table; the slice would run to EOF")
	var silent_section := readme.substr(silent_at, silent_end - silent_at)
	for name in _all_names():
		var row := "`%s.ogg`" % name
		# Asked of the function that decides it, not of the dictionary behind it.
		# A test pinned to a constant only holds while the constant is still the
		# answer, and that has cost this project three instruments.
		var is_voiced := SoundBank.placeholder_for(StringName(name)) != null
		if is_voiced:
			assert_true(voiced_section.contains(row),
				"%s has a placeholder but is not in the README's voiced table" % name)
			assert_false(silent_section.contains(row),
				"%s has a placeholder and the README lists it as silent" % name)
		else:
			assert_true(silent_section.contains(row),
				"%s has no placeholder but is not in the README's silent table" % name)
			assert_false(voiced_section.contains(row),
				"%s has no placeholder and the README promises the player a blip to replace" % name)
	# No count is asserted here and neither document states one any more. A
	# hand-typed total is the thing that went stale -- "fourteen kinds" in
	# SoundBank's header, "the six" over a table of seven rows -- and the tables
	# above say the same thing without anybody having to keep a number current.
	assert_false(voiced_section.contains("damage_over_time"),
		"damage_over_time is a name, not a voiced kind, and must not sit in the voiced table")


# ---------------------------------------------------------------------------
# The sounds the game ships, issue 550.
# ---------------------------------------------------------------------------

## Every audio file committed under Assets/Audio, found by walking the folder
## rather than listed here. A list would be the second list #299 refuses.
func _shipped_files() -> Array[String]:
	var out: Array[String] = []
	var pending: Array[String] = ["res://Assets/Audio"]
	while not pending.is_empty():
		var dir_path: String = pending.pop_back()
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for sub in dir.get_directories():
			pending.append("%s/%s" % [dir_path, sub])
		for f in dir.get_files():
			if SoundBank.EXTENSIONS.has(f.get_extension().to_lower()):
				out.append("%s/%s" % [dir_path, f])
	out.sort()
	return out


func test_every_voiced_name_ships_a_real_sound() -> void:
	# The whole point of #550: the game had never made a sound. Asked of the
	# file lookup alone, not of `stream_for_event`, so a placeholder cannot
	# stand in for a missing file and make this pass.
	for name in SoundBank.PLACEHOLDER_VOICES:
		assert_not_null(SoundBank.stream_for(name),
			"%s is a voiced name and no file ships for it; the game plays a blip there" % name)


func test_every_shipped_sound_decodes_and_is_audible() -> void:
	# A truncated or mis-encoded download loads as null and falls silently back
	# to the blip, which looks exactly like the pipeline working. Length is
	# read because a zero-length stream decodes fine and cannot be heard.
	var files := _shipped_files()
	assert_true(files.size() >= SoundBank.PLACEHOLDER_VOICES.size(),
		"only %d audio files ship; the voiced set has %d names" % [files.size(), SoundBank.PLACEHOLDER_VOICES.size()])
	for path in files:
		var stream := SoundBank.load_audio(path)
		assert_not_null(stream, "%s ships but does not decode as audio" % path)
		assert_true(stream.get_length() > 0.02, "%s decodes to %.3f s and cannot be heard" % [path, stream.get_length()])


func test_no_shipped_sound_is_long_enough_to_drone() -> void:
	# The README's own selection rule, enforced rather than written down: a
	# fight plays 6 to 8 sounds a second, so anything approaching a second
	# overlaps itself several times over and stops marking a moment.
	for path in _shipped_files():
		var stream := SoundBank.load_audio(path)
		assert_true(stream.get_length() <= 0.75,
			"%s is %.2f s; at 8 sounds a second that is a drone, not a mark" % [path, stream.get_length()])


func test_a_per_action_file_does_not_swallow_the_stun_cue() -> void:
	# Issue 550's trap, and the reason `sound_name` resolves STATUS_APPLIED
	# above the action branch. A slam's fire, its damage and its stun arrive in
	# one tick; if all three resolved to `action/<id>` the per-tick dedup would
	# collapse them and the stun would go silent for that one action.
	var fire := _event(CG.EventKind.ACTION_FIRE, &"scratch_test_action")
	var stun := _status_event(CG.Status.STUN, &"scratch_test_action")
	_write_sound("res://Assets/Audio/action/scratch_test_action.wav")

	assert_eq(String(SoundBank.sound_name(fire)), "action/scratch_test_action",
		"a per-action file must still claim the action's own fire")
	assert_eq(String(SoundBank.sound_name(stun)), "event/status_applied/stun",
		"the per-action file swallowed the stun cue")
	assert_ne(SoundBank.sound_name(fire), SoundBank.sound_name(stun),
		"one name for both means one noise for both once the tick de-duplicates")


func test_a_per_action_file_still_covers_that_action_s_damage() -> void:
	# The negative half of the fix: only STATUS_APPLIED was moved out of the
	# action branch, so everything else that carries an action_id still resolves
	# to it. Without this, over-correcting would look identical to the fix.
	var hit := _event(CG.EventKind.DAMAGE, &"scratch_test_action")
	assert_eq(String(SoundBank.sound_name(hit)), "event/damage",
		"with no file present the general name must answer")
	_write_sound("res://Assets/Audio/action/scratch_test_action.wav")
	assert_eq(String(SoundBank.sound_name(hit)), "action/scratch_test_action",
		"a per-action file stopped covering its own damage")


func test_the_readme_records_a_licence_and_a_source_for_every_shipped_file() -> void:
	# `Assets/UI/README.md` documents where art came from; audio downloaded from
	# somebody else needs the same, and a file with no recorded licence is a
	# file nobody can tell is safe to ship.
	var readme := FileAccess.get_file_as_string("res://Assets/Audio/README.md")
	assert_ne(readme, "", "Assets/Audio/README.md is missing")
	for path in _shipped_files():
		var name := path.replace("res://Assets/Audio/", "")
		assert_true(readme.contains(name),
			"%s ships but Assets/Audio/README.md does not record where it came from" % name)
	assert_true(readme.contains("CC0"), "no licence is recorded for the shipped sounds")
