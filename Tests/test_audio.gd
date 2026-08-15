extends "res://Tests/TestCase.gd"

const CG := preload("res://Scripts/Core/CG.gd")
const CombatEvent := preload("res://Scripts/Core/CombatEvent.gd")
const SoundBank := preload("res://Scripts/Audio/SoundBank.gd")

## The audio hook, issue #125. The player asked for hooks and placeholders "to
## make sure the pipeline works", so the load-bearing tests here are the ones
## that write a real file onto disk and assert the game finds it. Reasoning about
## a drop-in proves nothing: the whole claim is about files.
##
## OWNED BY sable (`Scripts/Audio/**`, `Assets/Audio/**`).

const SCRATCH := [
	"res://Assets/Audio/event/damage.wav",
	"res://Assets/Audio/event/damage_over_time.wav",
	"res://Assets/Audio/action/scratch_test_action.wav",
	"res://Assets/Audio/event/action_fire.wav",
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


# ---------------------------------------------------------------------------
# The pipeline: a file on disk, found with no code change.
# ---------------------------------------------------------------------------

func test_a_dropped_in_sound_is_found_with_no_registration() -> void:
	# The whole feature, end to end. Same shape as the PNG drop-in test in
	# test_art.gd, and for the same reason: this is a claim about the filesystem.
	var path := "res://Assets/Audio/event/damage.wav"
	assert_false(FileAccess.file_exists(path), "%s already exists; this test would not prove anything" % path)
	assert_eq(SoundBank.stream_for(&"event/damage"), null, "something is already answering to event/damage")

	_write_sound(path)
	assert_not_null(SoundBank.stream_for(&"event/damage"), "a file dropped into Assets/Audio was not picked up")

	DirAccess.remove_absolute(path)
	SoundBank.clear_cache()
	assert_eq(SoundBank.stream_for(&"event/damage"), null, "the override survived its own deletion")


func test_a_dropped_in_sound_beats_the_generated_placeholder() -> void:
	# The placeholder must get out of the way, or replacing one means deleting
	# something first and the drop-in is not a drop-in.
	var event := _event(CG.EventKind.DAMAGE, &"warrior_strike")
	var generated := SoundBank.stream_for_event(event)
	assert_not_null(generated, "DAMAGE has no default voice; the rest of this test is meaningless")

	_write_sound("res://Assets/Audio/event/damage.wav")
	var dropped := SoundBank.stream_for_event(event)
	assert_ne(dropped, generated, "the generated placeholder won over a real file")


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
	for name in ["event/damage", "event/nonsense", "action/not_an_action"]:
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


func test_a_near_silent_file_is_how_a_kind_is_turned_off() -> void:
	# The README tells a player this, so it is checked. The pipeline only adds,
	# and this is the only way to subtract; if it stopped working the README
	# would be quietly false and nothing else would notice.
	var event := _event(CG.EventKind.ACTION_FIRE, &"warrior_strike")
	var before := SoundBank.stream_for_event(event)
	assert_not_null(before)
	_write_sound("res://Assets/Audio/event/action_fire.wav")
	assert_ne(SoundBank.stream_for_event(event), before,
		"a dropped-in file did not displace the placeholder, so a kind cannot be silenced")


func test_the_voiced_kinds_are_exactly_the_six_intended() -> void:
	# Named individually rather than counted. A count passes when one kind
	# quietly replaces another, which is the mistake worth catching here.
	var voiced := [
		CG.EventKind.ACTION_FIRE, CG.EventKind.DAMAGE, CG.EventKind.HEAL,
		CG.EventKind.DEATH, CG.EventKind.MISS, CG.EventKind.BLOCKED,
	]
	for kind in CG.EventKind.values():
		var has := SoundBank.placeholder_for(kind) != null
		assert_eq(has, voiced.has(kind),
			"%s is %s and should not be" % [CG.EventKind.keys()[kind], "voiced" if has else "silent"])


func test_every_event_kind_resolves_to_a_name() -> void:
	# The exhaustiveness guard. `CG.EventKind` has no such guard anywhere else
	# in the project, and swift found the cost of that twice: SUSTAIN_START,
	# SUSTAIN_END and BLOCKED all render as '' in the combat log because a kind
	# was appended and every hand-written match statement stayed as it was.
	# Audio resolves names from the enum itself, so a new kind cannot be missed
	# here -- and this test is what asserts that stays true.
	for kind in CG.EventKind.values():
		var name := SoundBank.sound_name(_event(kind))
		assert_ne(String(name), "", "%s resolves to an empty sound name" % CG.EventKind.keys()[kind])
		assert_true(String(name).begins_with("event/"),
			"%s resolved to '%s', which is not an event name" % [CG.EventKind.keys()[kind], name])


# ---------------------------------------------------------------------------
# The placeholders themselves.
# ---------------------------------------------------------------------------

func test_every_placeholder_is_actually_audible() -> void:
	# A silent placeholder is the worst possible outcome here: it looks exactly
	# like the pipeline working and sounds exactly like it failing, and the
	# player would be the one to find out.
	for kind in CG.EventKind.values():
		var stream: AudioStreamWAV = SoundBank.placeholder_for(kind)
		if stream == null:
			continue
		var peak := 0
		var i := 0
		while i < stream.data.size():
			peak = maxi(peak, absi(stream.data.decode_s16(i)))
			i += 2
		assert_true(float(peak) / 32767.0 > 0.05,
			"the %s placeholder peaks at %.3f and cannot be heard" % [
				CG.EventKind.keys()[kind], float(peak) / 32767.0])


func test_the_placeholders_are_separable_by_ear() -> void:
	# They exist to be told apart. Pitch and length are the two cues that survive
	# a fight, so no two may share both -- checked as a property of the real
	# table rather than against six numbers typed out again here, which would be
	# the same author agreeing with himself.
	var seen: Dictionary = {}
	for kind in SoundBank.PLACEHOLDER_VOICES:
		var v: Array = SoundBank.PLACEHOLDER_VOICES[kind]
		var key := "%.0f/%.3f" % [v[0], v[1]]
		assert_false(seen.has(key),
			"%s and %s are the same pitch and the same length" % [
				CG.EventKind.keys()[kind], seen.get(key, "")])
		seen[key] = CG.EventKind.keys()[kind]


func test_a_placeholder_starts_from_silence() -> void:
	# A raw sine with a hard start clicks, and a click reads as a broken file
	# rather than as a placeholder. The fade is two milliseconds, so the first
	# sample must be effectively zero.
	var stream: AudioStreamWAV = SoundBank.placeholder_for(CG.EventKind.DEATH)
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

func test_the_replacement_instructions_name_every_event_kind() -> void:
	# Assets/Audio/README.md is the file the player uses to drop sounds in. A
	# kind missing from it is a sound they cannot name and therefore cannot
	# replace, and they would find out by dropping a file in that never plays.
	# Walked from the real enum, so appending a kind fails here rather than
	# silently going undocumented.
	var readme := FileAccess.get_file_as_string("res://Assets/Audio/README.md")
	assert_ne(readme, "", "Assets/Audio/README.md is missing")
	for kind in CG.EventKind.values():
		var name := String(CG.EventKind.keys()[kind]).to_lower()
		assert_true(readme.contains("event/%s.ogg" % name),
			"event kind %s exists but Assets/Audio/README.md does not list event/%s.ogg" % [name, name])
	assert_true(readme.contains("event/damage_over_time.ogg"),
		"the damage-over-time name is not in the instructions, and it is the one that needs a warning")


const _VOICED_HEADING := "### With a placeholder today"
const _SILENT_HEADING := "### Silent until you drop a file in"

func test_the_instructions_say_which_kinds_are_voiced() -> void:
	# The test above only asks that a kind is NAMED somewhere in the README, and
	# that is one degree off the question a player asks. They ask "does this one
	# make a noise today", and the README answers it with two tables.
	#
	# It was wrong. `event/interrupted` sat in the table headed "the six with a
	# placeholder today" -- a table of seven rows -- and INTERRUPTED has never
	# been in `PLACEHOLDER_VOICES`. A player replacing that blip would have been
	# adding the first sound that kind ever made, which is a different operation
	# with a different result, and nothing went red.
	#
	# So this splits the README where the player's eye splits it and checks each
	# side against the real dictionary. Both directions: a voiced kind under the
	# silent heading fails too.
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
	for kind in CG.EventKind.values():
		var name := String(CG.EventKind.keys()[kind]).to_lower()
		var row := "`event/%s.ogg`" % name
		# Asked of the function that decides it, not of the dictionary behind it.
		# A test pinned to a constant only holds while the constant is still the
		# answer, and that has cost this project three instruments.
		var is_voiced := SoundBank.placeholder_for(kind) != null
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
