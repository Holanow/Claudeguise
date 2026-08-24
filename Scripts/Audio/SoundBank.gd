extends RefCounted
class_name SoundBank


## The audio hook, for issue #125:

const AUDIO_DIR := "res://Assets/Audio"
const EXTENSIONS := ["ogg", "wav", "mp3"]

static var _cache: Dictionary = {}

## A name in `PLACEHOLDER_VOICES` is voiced; a name absent from it is silent
## until a file is dropped in for it. A dropped-in file also beats the
## placeholder, so a near-silent one is how a name gets turned off.

## Placeholder voices, and they are meant to sound synthetic. Keyed by the name
## `sound_name` resolves to, not by event kind: issue #507 voices one status and
## not the other twelve, which a kind cannot express.
const PLACEHOLDER_VOICES := {
	&"event/action_fire": [440.0, 0.07, 26.0, 0.0],
	&"event/damage": [220.0, 0.12, 20.0, -0.35],
	&"event/heal": [523.0, 0.16, 12.0, 0.45],
	&"event/death": [110.0, 0.45, 6.0, -0.55],
	&"event/miss": [175.0, 0.06, 34.0, -0.2],
	&"event/blocked": [880.0, 0.045, 48.0, 0.0],
	&"event/status_applied/stun": [330.0, 0.22, 9.0, -0.45],
}

const MIX_RATE := 22050

## How loud a placeholder is. Well under unity on purpose: these exist to prove a
## pipeline and the first thing anybody does with an unexpected noise at full
## volume is turn the game off.
const PLACEHOLDER_GAIN := 0.22

## ---------------------------------------------------------------------------

## The name a damage-over-time tick resolves to. Its own name so it is silent by
## default and still addressable; see the header for why it is not just `damage`.
const DOT_NAME := &"event/damage_over_time"

## The name an event resolves to, specific first. `&""` is never returned --
## every event has a name, whether or not a file or a placeholder exists for it.
static func sound_name(event: CombatEvent) -> StringName:
	if event.action_id != &"":
		var specific := StringName("action/%s" % event.action_id)
		if _stream(specific) != null:
			return specific
	elif event.kind == CG.EventKind.DAMAGE:
		# Damage with no action behind it is a status ticking. The simulation
		# does not label these and does not need to: the absence of an
		# `action_id` on a DAMAGE event is exactly the distinction, and it is
		# read here and nowhere below the presentation layer.
		return DOT_NAME
	if event.kind == CG.EventKind.STATUS_APPLIED:
		# Per status, not per kind: the ruling in #507 voices stun and nothing
		# else, and one name for all thirteen cannot say that. Outside the
		# `elif` chain on purpose -- an applied status usually carries the
		# action that applied it, so it reaches here through the first branch.
		return StringName("event/status_applied/%s" % String(CG.Status.keys()[event.status]).to_lower())
	return StringName("event/%s" % String(CG.EventKind.keys()[event.kind]).to_lower())

## The stream dropped in under `name`, or null when there is no file for it.
static func stream_for(name: StringName) -> AudioStream:
	return _stream(name)

static func has_sound(name: StringName) -> bool:
	return _stream(name) != null

## Forget everything loaded so far. Only the tests need this -- they write a file
## into `Assets/Audio` to prove the drop-in end to end, and a cache populated
## before that write would hide it.
static func clear_cache() -> void:
	_cache.clear()

static func _stream(name: StringName) -> AudioStream:
	if _cache.has(name):
		return _cache[name]
	var found: AudioStream = null
	for ext in EXTENSIONS:
		var path := "%s/%s.%s" % [AUDIO_DIR, name, ext]
		if not FileAccess.file_exists(path):
			continue
		found = load_audio(path)
		if found != null:
			break
	_cache[name] = found
	return found

## Reads an audio file off disk into a stream, or null when it cannot be read.
static func load_audio(path: String) -> AudioStream:
	var stream: AudioStream = null
	match path.get_extension().to_lower():
		"ogg":
			stream = AudioStreamOggVorbis.load_from_file(path)
		"wav":
			stream = AudioStreamWAV.load_from_file(path)
		"mp3":
			stream = AudioStreamMP3.load_from_file(path)
	if stream == null:
		push_error("SoundBank: %s exists but could not be read as audio" % path)
	return stream

## ---------------------------------------------------------------------------
## PLACEHOLDER SYNTHESIS
##
## Built in memory rather than committed as files, and that is the same decision
## `UIArtPreview` made about its demo border. Shipping placeholder audio files
## would put them in `Assets/Audio/`, where they would be indistinguishable from
## the player's own and would have to be deleted before their first real sound
## worked. Generated defaults get out of the way by themselves.

static var _placeholders: Dictionary = {}

## A short synthetic blip for `name`, or null when that name has no default
## voice. Cached, because building one is a few thousand samples of arithmetic
## and a fight would otherwise rebuild it hundreds of times.
static func placeholder_for(name: StringName) -> AudioStream:
	if not PLACEHOLDER_VOICES.has(name):
		return null
	if _placeholders.has(name):
		return _placeholders[name]
	var v: Array = PLACEHOLDER_VOICES[name]
	_placeholders[name] = _blip(v[0], v[1], v[2], v[3])
	return _placeholders[name]

## One decaying tone as 16-bit mono PCM.
static func _blip(hz: float, seconds: float, decay: float, sweep: float) -> AudioStreamWAV:
	var count := int(MIX_RATE * seconds)
	var data := PackedByteArray()
	data.resize(count * 2)
	var phase := 0.0
	for i in count:
		var t := float(i) / float(MIX_RATE)
		var progress := float(i) / float(count)
		# Phase accumulated rather than computed from `t * hz`, so a swept pitch
		# stays continuous instead of jumping every sample.
		phase += TAU * (hz * (1.0 + sweep * progress)) / float(MIX_RATE)
		var envelope := exp(-decay * t) * minf(1.0, t / 0.002)
		var sample := int(clampf(sin(phase) * envelope * PLACEHOLDER_GAIN, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, sample)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav

## The stream an event will actually play, dropped-in file first and generated
## placeholder second, or null when it should be silent.
static func stream_for_event(event: CombatEvent) -> AudioStream:
	var name := sound_name(event)
	var dropped := _stream(name)
	if dropped != null:
		return dropped
	return placeholder_for(name)

## ---------------------------------------------------------------------------
## PLAYBACK
##
## An instance, held by whoever attached it. NOT an autoload: `project.godot`

var _voices: Array[AudioStreamPlayer] = []
var _next_voice: int = 0

## Sounds already started this tick, so five simultaneous hits are one noise
## rather than five stacked copies of the same blip six milliseconds apart --
## which is not five times as loud, it is a different and much worse sound.
var _played_this_tick: Dictionary = {}
var _tick: int = -1

## How many sounds can overlap. Eight is enough for a scrum and few enough that
## a runaway cannot drown the fight; past that the oldest voice is taken.
const VOICES := 8

## Adds the players to `parent` and hands back the bank that owns them.
static func attach(parent: Node) -> RefCounted:
	var bank := new()
	for i in VOICES:
		var player := AudioStreamPlayer.new()
		player.name = "SoundVoice%d" % i
		parent.add_child(player)
		bank._voices.append(player)
	return bank

## Plays whatever `event` should sound like, or nothing at all. Safe to call for
## every event in the stream; deciding which ones are audible is this file's job
## and not the caller's, exactly as `UIArt` decides whether a PNG exists.
func play_for(event: CombatEvent) -> void:
	if _voices.is_empty():
		return
	if event.tick != _tick:
		_tick = event.tick
		_played_this_tick.clear()
	var name := sound_name(event)
	if _played_this_tick.has(name):
		return
	var stream := stream_for_event(event)
	if stream == null:
		return
	_played_this_tick[name] = true
	var player := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	player.stream = stream
	player.play()
