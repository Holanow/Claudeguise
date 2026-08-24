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
		"help": "The name above each unit, joined to it by a leader line when it has to move out of the way of another plate. Off by default: a plate is 140x24 over a 30px body, so in a nine-unit scrum the names cover the fight. Turn it on when you want to know who is who and can spare the room.",
		"default": false,
	},
	{
		"id": &"hit_stop",
		## Named so `DisplayOptionsPanel.row_text` reads: the panel appends
		## "showing" or "hidden" to every label and nothing here can change that.
		"label": "Freeze frame on a death",
		"help": "The picture stops for a tenth of a second each time something dies, so the blow reads as a blow rather than as a number changing. On by default: it holds on deaths only, roughly eleven a fight, and the fight never runs fast afterwards to catch up. Turn it off if you would rather nothing ever stopped.",
		"default": true,
	},
	{
		"id": &"impact_squash",
		"label": "Bodies react to hits",
		"help": "A struck body squashes for a fifth of a second and springs back, whoever landed a melee blow rocks backward off it, and an archer or a caster kicks back at the moment it looses its shot. On by default. It moves the body only, never a bar, a name or the fight itself. Turn it off if you want every silhouette to hold perfectly still.",
		"default": true,
	},
	{
		"id": &"impact_particles",
		"label": "Debris on every hit",
		"help": "A short burst of chips thrown off whatever was hit, in that damage type's colour, so a blow that lands looks different from one that misses. On by default: it lasts under half a second, it is smaller than a body and it never covers one, and the freeze frame it goes with is on for the same reason. Turn it off if you would rather the screen stayed still.",
		"default": true,
	},
	{
		"id": &"log_hazard_ticks",
		"label": "Ground damage in the log",
		"help": "One line per tick for every pawn standing in fire or acid. Off by default: measured over a Burn Pit fight it is 141 of the log's 402 lines, and it scrolls the deaths away. Turn it on to find out what killed somebody.",
		"default": false,
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
