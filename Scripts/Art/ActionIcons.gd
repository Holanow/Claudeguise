extends RefCounted

const CG := preload("res://Scripts/Core/CG.gd")
const Palette := preload("res://Scripts/Core/Palette.gd")
const UIArt := preload("res://Scripts/Art/UIArt.gd")
const StatusIcons := preload("res://Scripts/Art/StatusIcons.gd")

## One icon per action, for PLAYTEST-NOTES-2 item 3:
##
##   "Countdowns should be progress bars, with an icon at the end showing what
##    is coming."
##
## and the note's own reading of it: "the icon is the better half -- a ring says
## something is coming, an icon says what."
##
## MANAGER-OWNED (`Scripts/Art/**`). Nothing here draws itself into a fight:
## the progress bar is `Scripts/UI/UnitView.gd`, wren's.
##
## ---------------------------------------------------------------------------
## THE RULES
##
## 1. THE GLYPH IS THE VERB, THE COLOUR IS THE DAMAGE TYPE. Colour already means
##    damage type everywhere else on screen -- the floating numbers, the
##    projectile shapes, the wind-up ring -- so an icon that also coloured by
##    class or by team would be the one thing on screen using the channel
##    differently. `Palette.damage_color`, same call all three of those make.
##
## 2. AN ACTION WHOSE WHOLE EFFECT IS A STATUS DRAWS THAT STATUS'S GLYPH.
##    Guard shows the BLOCK wall, Ward shows the SHIELD, Haste shows the
##    chevrons, Taunt shows the horn, Mark shows the crosshair, Grapple shows
##    the weight. Learning one glyph teaches both halves, and the player sees
##    the thing that is coming and then sees the same thing land.
##
## 3. ABILITY ICONS ARE SQUARE PLATES; STATUS BADGES ARE WEDGES. Two systems on
##    screen at once, one pointing up or down and one not pointing at all, so a
##    glance never has to work out which system it is reading before it can read
##    it. The plate is dark on purpose -- it guarantees contrast for all eight
##    damage colours without each glyph carrying its own outline.
##
## 4. SILHOUETTE OVER DETAIL. These draw at 16px. Same finding as the unit
##    roster: what survives is the outline. Every glyph below is one recognisable
##    outline and no interior decoration, and no two share an outline.

## Reusable motifs. Several actions are honestly the same verb -- two bows, two
## siege bolts -- and giving each a private shape would be inventing differences
## the fight does not have.
## Tilted, and that is not decoration. Drawn upright on the first sheet this
## came out as a plus sign -- a vertical blade and a horizontal guard of similar
## weight is a cross -- and it was indistinguishable from `priest_heal`. Thirty
## degrees off vertical destroys the read completely. Pommel added for the same
## reason: it gives the bottom of the shape an end, where the bare grip just
## stopped.
const _SWORD := [
	{"poly": [[0.0, -0.92], [0.13, -0.62], [0.13, 0.2], [-0.13, 0.2], [-0.13, -0.62]], "rot": 0.55},
	{"poly": [[-0.46, 0.2], [0.46, 0.2], [0.4, 0.38], [-0.4, 0.38]], "rot": 0.55},
	{"poly": [[-0.09, 0.38], [0.09, 0.38], [0.09, 0.78], [-0.09, 0.78]], "rot": 0.55},
	{"dot": [0.0, 0.85, 0.13], "rot": 0.55},
]

## A finishing blow comes down, and it is broad where the Strike is thin. Two
## cues, not one: a merely rotated Strike would be the same icon twice.
const _SWORD_DOWN := [
	{"poly": [[0.0, 0.95], [0.32, 0.44], [0.32, -0.22], [-0.32, -0.22], [-0.32, 0.44]]},
	{"poly": [[-0.68, -0.22], [0.68, -0.22], [0.68, -0.42], [-0.68, -0.42]]},
	{"poly": [[-0.12, -0.42], [0.12, -0.42], [0.12, -0.92], [-0.12, -0.92]]},
]

## The head has a concave inner edge, which is the whole difference between an
## axe and a flag -- the first sheet had a convex blob on a pole and read as a
## flag at every size.
## A rotated part has to stay inside the unit CIRCLE, not just the unit square,
## or it leaves the icon's box at some angles. `test_glyph_geometry_stays_inside
## _its_own_rect` caught this one at 0.67 of a pixel, which is exactly the size
## of defect that ships.
const _AXE := [
	{"poly": [[-0.1, -0.94], [0.1, -0.94], [0.1, 0.94], [-0.1, 0.94]], "rot": 0.35},
	{"poly": [[0.02, -0.9], [0.5, -0.8], [0.86, -0.44], [0.6, 0.0], [0.08, -0.06], [0.34, -0.46]], "rot": 0.35},
	{"poly": [[-0.02, -0.9], [-0.5, -0.8], [-0.86, -0.44], [-0.6, 0.0], [-0.08, -0.06], [-0.34, -0.46]], "rot": 0.35},
]

## A spiked club: the taper plus the side spikes are the outline, and neither
## the axe's crescent nor the hammer's block has either.
const _CLUB := [
	{"poly": [
		[-0.2, 0.92], [0.2, 0.92], [0.28, 0.2], [0.5, 0.02], [0.28, -0.15],
		[0.44, -0.5], [0.2, -0.6], [0.26, -0.9], [-0.26, -0.9], [-0.2, -0.6],
		[-0.44, -0.5], [-0.28, -0.15], [-0.5, 0.02], [-0.28, 0.2],
	]},
]

## Tilted for the same reason the sword is: upright it rendered as a letter T.
const _HAMMER := [
	{"poly": [[-0.12, -0.16], [0.12, -0.16], [0.12, 0.92], [-0.12, 0.92]], "rot": -0.4},
	{"poly": [[-0.64, -0.74], [0.64, -0.74], [0.72, -0.45], [0.64, -0.16], [-0.64, -0.16], [-0.72, -0.45]], "rot": -0.4},
]

## Diagonal, which is the entire reason it does not read as a small sword.
const _DAGGER := [
	{"poly": [[-0.9, -0.88], [-0.46, -0.82], [0.34, 0.28], [0.14, 0.46]]},
	{"poly": [[0.06, 0.18], [0.62, 0.72], [0.44, 0.88], [-0.1, 0.36]]},
	{"line": [[0.0, 0.66], [0.6, 0.1]], "w": 0.16},
]

const _CLAWS := [
	{"line": [[-0.78, -0.7], [-0.34, 0.75]], "w": 0.2},
	{"line": [[-0.12, -0.85], [0.18, 0.8]], "w": 0.2},
	{"line": [[0.56, -0.72], [0.86, 0.68]], "w": 0.2},
]

## A solid head, a thin shaft and two swept feathers. The first version notched
## the tail into a V and read as an arrow with a head at each end -- a dumbbell.
## Feathers that sweep back past the tail cannot do that.
const _ARROW := [
	{"poly": [[0.95, 0.0], [0.22, 0.5], [0.22, -0.5]]},
	{"poly": [[-0.9, 0.09], [0.3, 0.09], [0.3, -0.09], [-0.9, -0.09]]},
	{"poly": [[-0.86, -0.08], [-0.44, -0.08], [-0.62, -0.52], [-0.95, -0.44]]},
	{"poly": [[-0.86, 0.08], [-0.44, 0.08], [-0.62, 0.52], [-0.95, 0.44]]},
]

## Siege ammunition: a heavier head and no fletching at all, which is what tells
## it apart from the arrow when both are 16px wide.
const _BOLT_HEAVY := [
	{"poly": [
		[0.95, 0.0], [0.1, 0.6], [0.1, 0.22], [-0.85, 0.22],
		[-0.85, -0.22], [0.1, -0.22], [0.1, -0.6],
	]},
]

const _ORB := [
	{"dot": [0.28, 0.0, 0.5]},
	{"poly": [[-0.12, -0.34], [-0.95, -0.12], [-0.95, 0.12], [-0.12, 0.34]]},
]

## A spiked orb. The Cultist's bolt is the same verb as the Priest's and a
## different school, and the barbs are the same idea as PROFANE's projectile.
const _HEX := [
	{"poly": [
		[0.85, 0.0], [0.32, 0.22], [0.5, 0.75], [0.0, 0.42], [-0.5, 0.75],
		[-0.32, 0.22], [-0.85, 0.0], [-0.32, -0.22], [-0.5, -0.75],
		[0.0, -0.42], [0.5, -0.75], [0.32, -0.22],
	]},
]

## A beam striking downward with a splash at its foot. Smite comes from above,
## and this is the only glyph here that reads as arriving rather than as being
## swung or thrown.
## A column of light widening as it comes down, onto a struck plate. The first
## version tapered the wrong way and put three separate strokes under it, which
## rendered as a figure with legs.
const _BEAM := [
	{"poly": [[-0.26, -0.95], [0.26, -0.95], [0.5, 0.34], [-0.5, 0.34]]},
	{"poly": [[-0.75, 0.5], [0.75, 0.5], [0.75, 0.78], [-0.75, 0.78]]},
]

## A fountain crown: a narrow base flaring into a spray. The first version was a
## straight column with dots beside it and read as a lit candle.
const _JET := [
	{"poly": [
		[-0.24, 0.95], [0.24, 0.95], [0.3, -0.05], [0.62, -0.72],
		[0.0, -0.3], [-0.62, -0.72], [-0.3, -0.05],
	]},
	{"dot": [-0.78, -0.3, 0.16]},
	{"dot": [0.78, -0.36, 0.16]},
]

const _STEAM := [
	{"line": [[-0.52, 0.85], [-0.72, 0.35], [-0.36, -0.05], [-0.56, -0.62]], "w": 0.16},
	{"line": [[0.04, 0.9], [-0.16, 0.35], [0.2, -0.1], [0.0, -0.78]], "w": 0.16},
	{"line": [[0.6, 0.85], [0.4, 0.35], [0.76, -0.05], [0.56, -0.62]], "w": 0.16},
]

const _CROSS := [
	{"poly": [
		[-0.22, -0.85], [0.22, -0.85], [0.22, -0.22], [0.85, -0.22],
		[0.85, 0.22], [0.22, 0.22], [0.22, 0.85], [-0.22, 0.85],
		[-0.22, 0.22], [-0.85, 0.22], [-0.85, -0.22], [-0.22, -0.22],
	]},
]

const _HOOK := [
	{"line": [[-0.92, -0.85], [0.1, -0.22]], "w": 0.2},
	{"arc": [0.1, 0.28, 0.5, -PI * 0.5, PI * 0.9], "w": 0.2},
]

## A ball on a line: the same "reaches out and pulls" family as the hook, told
## apart by a solid mass where the hook has an open curve.
const _CHAIN := [
	{"line": [[-0.92, 0.78], [0.18, -0.18]], "w": 0.18},
	{"dot": [0.48, -0.48, 0.42]},
]

const _ENGINE := [
	{"poly": [[-0.78, 0.9], [0.78, 0.9], [0.5, 0.35], [-0.5, 0.35]]},
	{"poly": [[-0.32, 0.42], [-0.06, 0.2], [0.62, -0.68], [0.36, -0.88]]},
	{"dot": [0.52, -0.72, 0.26]},
]

## Every action id in the content registry. `Tests/test_art.gd` asserts this
## covers the registry exactly, so an action added in `Scripts/Content` fails
## the gate here rather than shipping with no icon and nobody noticing -- which
## is how a shape that exists in a registry ends up never drawn.
const GLYPHS := {
	# Warrior. Guard, Taunt and Directional Block are pure-status actions, so
	# they borrow their own status glyph (rule 2).
	&"warrior_strike": _SWORD,
	&"warrior_execute": _SWORD_DOWN,
	&"warrior_guard": CG.Status.BLOCK,
	&"warrior_taunt": CG.Status.TAUNTING,
	&"warrior_block": CG.Status.SHIELDING,

	# Priest.
	&"priest_heal": _CROSS,
	&"priest_bolt": _ORB,
	&"priest_smite": _BEAM,
	&"priest_haste": CG.Status.HASTE,
	&"priest_ward": CG.Status.SHIELD,

	# Goblins and the archer.
	&"goblin_stab": _DAGGER,
	&"goblin_arrow": _ARROW,
	&"archer_shot": _ARROW,

	# The rest of the bestiary.
	&"ghoul_maul": _CLUB,
	&"grunt_smash": _HAMMER,
	&"cultist_bolt": _HEX,
	&"geyser_blast": _JET,
	&"geyser_scald": _STEAM,

	# Siege. The master and the engine fire the same ammunition, so they draw
	# the same bolt -- inventing a difference the fight does not have would be
	# worse than the repetition.
	&"siege_master_shot": _BOLT_HEAVY,
	&"siege_engine_bolt": _BOLT_HEAVY,
	&"build_siege_engine": _ENGINE,
	&"spotter_mark": CG.Status.MARKED,

	# Abomination and the Warden.
	&"abomination_claw": _CLAWS,
	&"abomination_hook": _HOOK,
	&"abomination_grapple": CG.Status.SLOWED,
	&"warden_axe": _AXE,
	&"warden_chain_toss": _CHAIN,
}

## Drawn when an id has no entry. Never reached today and asserted against, but
## a missing icon must be a visible placeholder rather than a crash or a blank:
## a blank looks like the feature failing, and this looks like a missing icon.
const _UNKNOWN := [
	{"arc": [0.0, 0.0, 0.6], "w": 0.2},
	{"dot": [0.0, 0.55, 0.16]},
]

## The clipped-corner square every ability icon sits on. Rule 3: not a wedge,
## so it is never mistaken for a status badge.
const PLATE := [
	[-1.0, -0.7], [-0.7, -1.0], [0.7, -1.0], [1.0, -0.7],
	[1.0, 0.7], [0.7, 1.0], [-0.7, 1.0], [-1.0, 0.7],
]

## The parts for one action. A `CG.Status` value in the table above means "use
## that status's glyph", resolved here so the table stays readable.
static func glyph_for(action_id: StringName) -> Array:
	var entry: Variant = GLYPHS.get(action_id, _UNKNOWN)
	if entry is int:
		return StatusIcons.GLYPHS[entry]
	return entry

static func has_glyph(action_id: StringName) -> bool:
	return GLYPHS.has(action_id)

## The override a dropped-in PNG lives under:
## `Assets/UI/action/warrior_execute.png`. The action id, unchanged, for the
## same guessability as `Assets/Units/warrior.png`.
static func art_name(action_id: StringName) -> StringName:
	return StringName("action/%s" % action_id)

## One ability icon filling `rect`. Sized for roughly 16px squares -- the end of
## a wind-up progress bar.
##
## `damage_type` is the one `UnitView._accent()` already resolves for the class
## accent colour, so this costs no new Registry lookup at the call site.
##
## Draws a dropped-in PNG if one exists and the generated icon otherwise. The
## caller never asks which.
static func draw_action(canvas: CanvasItem, action_id: StringName, damage_type: CG.DamageType, rect: Rect2) -> void:
	var tex := UIArt.texture_for(art_name(action_id))
	if tex != null:
		UIArt.draw_fit(canvas, tex, rect)
		return
	var plate := UIArt.glyph_points({"poly": PLATE}, rect)
	canvas.draw_colored_polygon(plate, Palette.HP_BACK)
	var closed := plate.duplicate()
	closed.append(plate[0])
	canvas.draw_polyline(closed, Palette.ARENA_EDGE, 1.0, true)
	var inner := Rect2(rect.position + rect.size * 0.16, rect.size * 0.68)
	UIArt.draw_glyph(canvas, glyph_for(action_id), inner, Palette.damage_color(damage_type))
