extends RefCounted
class_name DisplayOptions

## Every "show less on the screen" preference, in one place.

## `id` is what code asks for. `label` is the checkbox. `help` is the sentence
## under it, and it is required -- the same report that asked for less on screen
## also found that nothing anywhere explains anything, so a control with no
## explanation is the failure mode this project already has.
const OPTIONS := [
	{
		"id": &"damage_numbers",
		"label": "Floating damage numbers",
		"help": "Numbers over each hit. Off by default: most of them are poison and burn ticking rather than hits, and the combat log already carries every one with more detail.",
		"default": false,
	},
	{
		"id": &"name_plates",
		"label": "Name plates on units",
		"help": "The name above each unit. Off by default: with eight units in one scrum the plates collide and the top one wins, so \"Siege Engine\" lands over \"Siege Engine\" over \"Siege Master\". Team colour carries which side a unit is on.",
		"default": false,
	},
]

static var _values := {}

static func _entry(id: StringName) -> Dictionary:
	for option in OPTIONS:
		if option.id == id:
			return option
	return {}

## Unknown ids return `false` rather than pushing an error: this is read from
## drawing code on a hot path, and a mistyped id that silently hides something
## is easier to see on screen than an error spammed once per frame.
static func enabled(id: StringName) -> bool:
	if _values.has(id):
		return _values[id]
	var option := _entry(id)
	return option.get("default", false) if not option.is_empty() else false

static func set_enabled(id: StringName, value: bool) -> void:
	_values[id] = value

## Back to every option's shipped default. Exists for tests, which would
## otherwise leak one test's toggle into the next through the static.
static func reset() -> void:
	_values.clear()
