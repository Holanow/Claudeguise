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
		"help": "The name above each unit. On by default: plates take the first row that is free of every other plate, so a fourteen-unit scrum stacks them into a column instead of printing them through each other. Turn it off when you would rather read the shapes.",
		"default": true,
	},
	{
		"id": &"log_hazard_ticks",
		"label": "Ground damage in the log",
		"help": "One line per tick for every pawn standing in fire or acid. On by default, and it is a lot: measured over a Burn Pit fight, 141 of the log's 402 lines. Turn it off when the room is on fire and you want to read what everyone did; turn it back on to find out what killed somebody.",
		"default": true,
	},
	{
		"id": &"log_status_damage",
		"label": "Poison and burn ticks in the log",
		"help": "One line per tick for every burn, poison and bleed. Off by default: a dozen of them can land inside one exchange and bury it. The floating numbers and the status badge still show them either way.",
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
