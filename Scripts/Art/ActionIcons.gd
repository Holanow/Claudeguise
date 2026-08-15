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
## it apart from the arrow when both are 16px wide. The Siege Master's own shot
## -- flat, direct, aimed by the unit firing it.
const _BOLT_HEAVY := [
	{"poly": [
		[0.95, 0.0], [0.1, 0.6], [0.1, 0.22], [-0.85, 0.22],
		[-0.85, -0.22], [0.1, -0.22], [0.1, -0.6],
	]},
]

## The Siege Engine's shot: the same ammunition on a lobbed path instead of a
## flat one, so the trajectory carries the read and the head does not have to.
##
## This one is a fix, not a new ability. Both siege actions drew `_BOLT_HEAVY`
## on the reasoning that the master and its engine "fire the same ammunition",
## and that was wrong for the only reason that matters here: **a Siege Master
## fights alongside the engine it builds**, so the two icons appear over two
## units in the same fight, on two bars, at the same instant. Rule 4 says no two
## glyphs share an outline; these shared one exactly where sharing costs the
## most. Found by rendering `Screenshots/ui_icons_sheet.png`, same as the six
## collisions the first sheet caught.
##
## The arc is also what the engine is becoming rather than only what it is: an
## artillery piece -- immobile, slow, unlimited range, firing only at marked
## targets. An indirect-fire weapon and a shoulder-aimed one are not the same
## shot, and once the rebuild lands "the same ammunition" is no longer true.
## The first version of this drew the trajectory as a thin arc with a small bolt
## on it, and rendering it settled the matter in one look: at 16px the arc is the
## only thing left and the icon reads as `abomination_hook`, a curl. A thin line
## describing where something went cannot compete with the thing itself.
##
## So the shot carries it, on two cues at once -- the same pair `_SWORD_DOWN`
## uses to stay clear of `_SWORD`, because a merely rotated copy is the same icon
## twice:
##
##   ANGLE. Nose-down at about 55 degrees, where the master's is flat. Plunging
##   fire is what an artillery piece does and a shoulder-aimed shot does not.
##   THIRTY degrees off is enough to destroy a read; this is nearly twice that.
##   WEIGHT. Fatter shaft, broader barbs, blunt tail. A shell, not a dart.
const _BOLT_LOBBED := [
	# Authored along +X and rotated about the glyph centre, the same technique
	# the sword and the axe use -- hand-computing rotated vertices is how you get
	# them slightly wrong. Every point is inside the unit CIRCLE, not just the
	# unit square, because rotation is what carries a corner out of the box.
	{"poly": [
		[0.98, 0.0], [0.14, 0.72], [0.14, 0.3], [-0.7, 0.3],
		[-0.7, -0.3], [0.14, -0.3], [0.14, -0.72],
	], "rot": 0.95},
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

## Cleanse: a wave sweeping across, and two short diagonals leaving upward --
## the thing being washed off, going away. Not a variant of `_STEAM`.
##
## The second collision this pass fixes, and the one that was actually wrong
## rather than merely repeated: `geyser_cleanse` drew `_STEAM`, the glyph of the
## Geysermancer's damage-over-time attack, on the same unit's bar. Same class,
## same colour, same 16px square, opposite meanings -- an icon that says "damage
## incoming" for an ability that strips harmful statuses off an ally. It was a
## one-line placeholder added under time pressure and explicitly offered for
## repointing (TEAM_LOG.md, finch), which is what this is.
## The first version drew a wave with a scalloped top and a flat bottom, and it
## rendered as a mountain range with two ski tracks on it -- which is the exact
## defect `StatusIcons`' TAUNTED glyph (drawn while it was named ENRAGE)
## already documented and fixed, and I walked into
## it again. A flat bottom edge is what makes a jagged top edge read as
## landscape. There is no baseline here at all.
const _RINSE := [
	# One heavy drop, in flight, leaning the way it is travelling.
	{"poly": [
		[0.3, -0.9], [0.74, -0.14], [0.72, 0.3], [0.36, 0.72],
		[-0.04, 0.56], [-0.16, 0.14], [0.0, -0.3],
	]},
	# Two streaks behind it. The Geysermancer's other two glyphs are a standing
	# fountain and a rising steam column; a drop being thrown across is neither,
	# and the streaks are what stop it reading as a fourth stationary shape.
	{"line": [[-0.34, -0.86], [-0.62, 0.1]], "w": 0.16},
	{"line": [[-0.78, -0.62], [-0.96, 0.0]], "w": 0.13},
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
	# sable: one data line, no new art, same disclosed shape as issue 79's own
	# `geyser_spout` entry below. `warrior_second_wind` (issue 99) replaces
	# Directional Block in the Warrior's kit, so it is reachable and
	# `test_every_reachable_action_has_an_icon` goes red the moment it lands.
	# Reusing `_CROSS`, the existing heal glyph -- this is a heal and the rule
	# in this file is that a glyph names what an action does. Repoint it freely
	# if you would rather Second Wind read differently from priest_heal.
	# `warrior_block` stays: it is still reachable, now via plate_mail.
	&"warrior_second_wind": _CROSS,

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
	# sable: one data line, no new art, and the only edit issue 79 makes in
	# your files. `geyser_spout` is the Geysermancer's new zero-cost basic
	# attack and `test_every_reachable_action_has_an_icon` -- doing exactly the
	# job this table's own comment describes -- went red the moment it landed.
	# Pointed at the existing `_JET` rather than inventing a third water shape:
	# Spout and Blast are the same jet of water, one splashing and one not.
	# Repoint it if you would rather they read apart; nothing here depends on
	# which glyph it is.
	&"geyser_spout": _JET,
	# finch pointed this at `_STEAM` as a placeholder when the ability landed,
	# and said to repoint it freely. Repointed in issue #85: sharing Scald's
	# glyph made a debuff-strip on an ally look like a damage-over-time attack.
	&"geyser_cleanse": _RINSE,

	# Siege. Direct fire for the master, a lobbed path for the engine. These two
	# drew the same bolt until issue #85, on the reasoning that the difference
	# was invented -- but the master builds the engine and then fights beside it,
	# so it is the one repetition on the sheet that a player is guaranteed to see
	# twice at once. See `_BOLT_LOBBED`.
	&"siege_master_shot": _BOLT_HEAVY,
	&"siege_engine_bolt": _BOLT_LOBBED,
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
	UIArt.draw_outlined_polygon(canvas, plate, Palette.HP_BACK, Palette.ARENA_EDGE, 1.0)
	var inner := Rect2(rect.position + rect.size * 0.16, rect.size * 0.68)
	UIArt.draw_glyph(canvas, glyph_for(action_id), inner, Palette.damage_color(damage_type))
