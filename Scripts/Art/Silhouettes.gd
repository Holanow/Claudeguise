extends RefCounted

const CG := preload("res://Scripts/Core/CG.gd")
const Palette := preload("res://Scripts/Core/Palette.gd")
const UnitArt := preload("res://Scripts/Art/UnitArt.gd")
const UIArt := preload("res://Scripts/Art/UIArt.gd")

## Placeholder art, as polygons in code.
##
## MANAGER-OWNED (`Scripts/Art/**`). pike calls `draw_unit` from `UnitView` and
## does not need to edit this; ask for a shape and I add it.
##
## Why polygons and not image files: Godot imports `.svg` and `.png` through the
## editor, and the editor does not run on this machine — `--import`,
## `--editor --quit` and the windowed editor all hang with no output, on the
## Steam build and the official one alike. Anything needing an import step is
## therefore unavailable to us. Points in an array need no import, no `.import`
## sidecar and no `.godot/imported/` directory, so this works from a fresh
## worktree with nothing set up.
##
## It is also the honest kind of placeholder. Nobody will mistake these for
## final art, and each class is recognisable at a glance from across the arena,
## which is the only thing the slice actually needs from art: telling four
## pawns and six enemies apart while they move.
##
## Coordinates are in a unit square from -1 to 1, with -Y up. `draw_unit` scales
## by the unit's radius, so a shape drawn here is the right size everywhere.

## One drawable shape: a polygon and how to colour it.
##
## `tint` picks the colour at draw time rather than baking one in, so the same
## silhouette reads as a player pawn or an enemy without a second copy.
enum Tint {
	TEAM,      ## the unit's team colour
	TEAM_DARK, ## the team colour, darkened: shadow and underside
	ACCENT,    ## the class's damage-type colour: weapons, magic, glow
	OUTLINE,   ## the arena edge colour: keeps a shape readable on any ground
}

## Two things these were redrawn for after looking at them rendered, and both
## are worth keeping if you add a shape:
##
##   - **Silhouette over detail.** At the size a pawn actually occupies, colour
##     and interior shapes vanish and only the outline survives. So the
##     classes differ in outline first: the Warrior is a wide arc, the Priest a
##     narrow spire, the Siege Master a low wedge, the Abomination lopsided.
##     Squint at the preview; if two are the same blob, the difference is
##     decoration.
##   - **Axis-aligned edges read as boxes.** The first pass was all horizontal
##     and vertical edges and looked exactly like the squares it was meant to
##     replace. Almost every edge here is on a diagonal now.
const _PARTS := {
	# --- classes -----------------------------------------------------------
	# Warrior: the widest player outline. Heavy pauldrons sloping outward, a
	# kite shield past the left edge, a blade past the right.
	&"warrior": [
		{"tint": Tint.ACCENT, "poly": [[-0.66, -0.62], [-0.98, -0.34], [-0.94, 0.32], [-0.7, 0.72], [-0.5, 0.28], [-0.5, -0.44]]},
		{"tint": Tint.ACCENT, "poly": [[0.56, 0.44], [0.66, -0.72], [0.74, -0.96], [0.82, -0.72], [0.88, 0.44], [0.72, 0.56]]},
		{"tint": Tint.ACCENT, "poly": [[0.5, 0.4], [0.94, 0.4], [0.9, 0.56], [0.54, 0.56]]},
		{"tint": Tint.TEAM_DARK, "poly": [[-0.62, 1.0], [-0.44, 0.34], [0.44, 0.34], [0.62, 1.0], [0.3, 0.94], [0.16, 0.52], [-0.16, 0.52], [-0.3, 0.94]]},
		{"tint": Tint.TEAM, "poly": [[-0.78, -0.3], [-0.52, -0.66], [-0.24, -0.78], [0.24, -0.78], [0.52, -0.66], [0.78, -0.3], [0.5, 0.4], [-0.5, 0.4]]},
		{"tint": Tint.TEAM, "poly": [[-0.24, -0.8], [-0.16, -1.0], [0.16, -1.0], [0.24, -0.8]]},
	],
	# Priest: the narrowest and tallest outline, a spire. Pointed hood, robe
	# flaring to a wide hem, halo floating clear of the head.
	&"priest": [
		{"tint": Tint.ACCENT, "poly": [[-0.44, -0.9], [0.0, -1.0], [0.44, -0.9], [0.0, -0.8]]},
		{"tint": Tint.ACCENT, "poly": [[0.34, -0.5], [0.46, -0.56], [0.6, 0.86], [0.44, 0.9]]},
		{"tint": Tint.TEAM_DARK, "poly": [[-0.72, 1.0], [-0.34, 0.1], [0.34, 0.1], [0.72, 1.0], [0.0, 0.9]]},
		{"tint": Tint.TEAM, "poly": [[0.0, -0.74], [0.3, -0.2], [0.44, 0.62], [-0.44, 0.62], [-0.3, -0.2]]},
		{"tint": Tint.TEAM, "poly": [[0.0, -0.78], [0.2, -0.48], [0.0, -0.34], [-0.2, -0.48]]},
	],
	# Geysermancer: bottom-heavy with three jets of unequal height. The only
	# outline here that is taller than it is wide at the top and the reverse at
	# the bottom.
	&"geysermancer": [
		{"tint": Tint.ACCENT, "poly": [[-0.78, 0.2], [-0.62, -0.34], [-0.5, -0.62], [-0.42, -0.3], [-0.34, 0.2]]},
		{"tint": Tint.ACCENT, "poly": [[-0.12, -0.6], [0.0, -1.0], [0.12, -0.6], [0.0, -0.46]]},
		{"tint": Tint.ACCENT, "poly": [[0.34, 0.2], [0.44, -0.42], [0.56, -0.76], [0.66, -0.28], [0.78, 0.2]]},
		{"tint": Tint.TEAM_DARK, "poly": [[-0.86, 1.0], [-0.56, 0.24], [0.56, 0.24], [0.86, 1.0], [0.0, 0.86]]},
		{"tint": Tint.TEAM, "poly": [[-0.5, 0.3], [-0.36, -0.28], [0.0, -0.5], [0.36, -0.28], [0.5, 0.3]]},
		{"tint": Tint.TEAM, "poly": [[-0.18, -0.44], [0.0, -0.7], [0.18, -0.44], [0.0, -0.3]]},
	],
	# Siege Master: a low wedge on a wheel, with a long arm slung over the top.
	# The one player shape that is wider than it is tall.
	&"siege_master": [
		{"tint": Tint.ACCENT, "poly": [[-0.3, -0.5], [0.72, -0.98], [0.9, -0.72], [-0.1, -0.24]]},
		{"tint": Tint.ACCENT, "poly": [[0.66, -1.0], [0.98, -0.86], [0.86, -0.6], [0.58, -0.76]]},
		{"tint": Tint.TEAM_DARK, "poly": [[-0.96, 1.0], [-0.78, 0.5], [0.78, 0.5], [0.96, 1.0], [0.0, 0.9]]},
		{"tint": Tint.TEAM, "poly": [[-0.82, 0.56], [-0.66, -0.16], [-0.2, -0.44], [0.44, -0.4], [0.72, -0.04], [0.8, 0.56]]},
		{"tint": Tint.TEAM, "poly": [[-0.5, -0.42], [-0.36, -0.68], [-0.08, -0.68], [0.02, -0.42]]},
		{"tint": Tint.ACCENT, "poly": [[-0.86, 0.42], [-0.5, 0.42], [-0.44, 0.98], [-0.92, 0.98]]},
	],
	# Abomination: no symmetry anywhere. One oversized claw on the right, a
	# hunched mass leaning left, spines along the back.
	&"abomination": [
		{"tint": Tint.ACCENT, "poly": [[0.36, -0.22], [0.78, -0.34], [1.0, 0.1], [0.86, 0.62], [0.52, 0.44], [0.3, 0.14]]},
		{"tint": Tint.ACCENT, "poly": [[0.58, -0.3], [0.72, -0.66], [0.8, -0.28]]},
		{"tint": Tint.ACCENT, "poly": [[-0.56, -0.62], [-0.44, -0.98], [-0.3, -0.6]]},
		{"tint": Tint.ACCENT, "poly": [[-0.78, -0.3], [-0.98, -0.06], [-0.82, 0.34], [-0.62, 0.06]]},
		{"tint": Tint.TEAM_DARK, "poly": [[-0.9, 1.0], [-0.62, 0.22], [0.46, 0.14], [0.82, 1.0], [0.0, 0.86]]},
		{"tint": Tint.TEAM, "poly": [[-0.72, 0.3], [-0.66, -0.3], [-0.4, -0.66], [0.06, -0.82], [0.36, -0.5], [0.44, 0.02], [0.24, 0.4], [-0.4, 0.44]]},
		{"tint": Tint.TEAM, "poly": [[-0.34, -0.7], [-0.42, -0.94], [-0.06, -0.98], [0.04, -0.8]]},
	],

	# --- floor 1 enemies, matching the ids in Content/Modules/floor1_enemies --
	#
	# These three were added after looking at a rendered fight in which every
	# enemy drew the unknown-shape diamond, because I invented rat/grub/brute
	# before any content existed and teal named their enemies something else.
	# The fallback did its job — they were visible and obviously unfinished —
	# but the lesson is that art ids and content ids are one contract and
	# nothing checks it. Tests/test_art.gd now does.
	#
	# Grunt: squat, wide, shield forward. The shape a melee line-holder should
	# have: hard to see past and clearly not fast.
	&"dungeon_grunt": [
		{"tint": Tint.ACCENT, "poly": [[-0.62, -0.5], [-0.94, -0.26], [-0.9, 0.36], [-0.6, 0.6], [-0.48, 0.2], [-0.5, -0.32]]},
		{"tint": Tint.ACCENT, "poly": [[0.5, 0.3], [0.62, -0.4], [0.8, -0.36], [0.7, 0.34]]},
		{"tint": Tint.TEAM_DARK, "poly": [[-0.86, 1.0], [-0.6, 0.44], [0.6, 0.44], [0.86, 1.0], [0.0, 0.9]]},
		{"tint": Tint.TEAM, "poly": [[-0.72, 0.5], [-0.62, -0.22], [-0.3, -0.56], [0.3, -0.56], [0.62, -0.22], [0.72, 0.5]]},
		{"tint": Tint.TEAM_DARK, "poly": [[-0.22, -0.56], [-0.26, -0.84], [0.26, -0.84], [0.22, -0.56]]},
		{"tint": Tint.ACCENT, "poly": [[-0.14, -0.78], [-0.04, -0.82], [-0.02, -0.7]]},
		{"tint": Tint.ACCENT, "poly": [[0.04, -0.8], [0.14, -0.82], [0.14, -0.7]]},
	],
	# Archer: the leanest enemy outline, with a bow arc standing clear of the
	# body so the silhouette says "range" before the health bar does.
	&"dungeon_archer": [
		{"tint": Tint.ACCENT, "poly": [[-0.5, -0.86], [-0.72, -0.4], [-0.72, 0.3], [-0.5, 0.74], [-0.58, 0.36], [-0.58, -0.42]]},
		{"tint": Tint.ACCENT, "poly": [[-0.54, -0.84], [0.24, -0.06], [0.2, 0.02], [-0.56, 0.72]]},
		{"tint": Tint.TEAM_DARK, "poly": [[-0.62, 1.0], [-0.32, 0.4], [0.44, 0.4], [0.72, 1.0], [0.05, 0.88]]},
		{"tint": Tint.TEAM, "poly": [[-0.3, 0.46], [-0.22, -0.3], [0.06, -0.62], [0.34, -0.3], [0.42, 0.46]]},
		{"tint": Tint.TEAM, "poly": [[0.0, -0.62], [0.12, -0.9], [0.32, -0.78], [0.28, -0.56]]},
		{"tint": Tint.ACCENT, "poly": [[0.3, -0.92], [0.5, -1.0], [0.42, -0.78]]},
	],
	# Cultist: a hood and a robe and no legs at all. Reads as a caster from the
	# outline alone, and reads as nothing like the Priest, whose halo sits
	# clear above the head while this one has a beak of a hood.
	&"dungeon_cultist": [
		{"tint": Tint.TEAM_DARK, "poly": [[-0.76, 1.0], [-0.44, 0.3], [0.44, 0.3], [0.76, 1.0], [0.0, 0.92]]},
		{"tint": Tint.TEAM, "poly": [[0.0, -0.92], [0.34, -0.42], [0.5, 0.5], [-0.5, 0.5], [-0.34, -0.42]]},
		{"tint": Tint.TEAM_DARK, "poly": [[0.0, -0.9], [0.26, -0.4], [0.0, -0.24], [-0.26, -0.4]]},
		{"tint": Tint.ACCENT, "poly": [[-0.06, -0.66], [0.1, -0.58], [-0.06, -0.5]]},
		{"tint": Tint.ACCENT, "poly": [[0.32, -0.12], [0.62, 0.02], [0.54, 0.26], [0.28, 0.14]]},
		{"tint": Tint.ACCENT, "poly": [[-0.3, -0.06], [-0.6, 0.08], [-0.52, 0.32], [-0.26, 0.2]]},
	],

	# --- floor 1 bestiary, ids from teal's issue 12 --------------------------
	#
	# Drawn to the roster's own logic rather than to look like small pawns: these
	# are meant to be read as "many weak", "ranged", "slow and tanky" and "caster"
	# from the outline alone, at the size a crowd of them will actually be.
	#
	# Goblin: the smallest silhouette in the game and the only one that reads as
	# hunched. Deliberately does not fill its radius — a goblin should look like
	# a thing you can kill, because eight of them are the threat, not one.
	&"goblin": [
		{"tint": Tint.ACCENT, "poly": [[0.34, 0.1], [0.5, -0.36], [0.62, -0.3], [0.48, 0.16]]},
		{"tint": Tint.TEAM_DARK, "poly": [[-0.5, 1.0], [-0.34, 0.5], [0.42, 0.5], [0.58, 1.0], [0.04, 0.9]]},
		{"tint": Tint.TEAM, "poly": [[-0.44, 0.56], [-0.3, 0.0], [0.0, -0.2], [0.34, 0.02], [0.44, 0.56]]},
		{"tint": Tint.TEAM, "poly": [[-0.12, -0.18], [-0.06, -0.5], [0.22, -0.5], [0.26, -0.16]]},
		{"tint": Tint.ACCENT, "poly": [[-0.06, -0.44], [-0.42, -0.62], [-0.1, -0.28]]},
		{"tint": Tint.ACCENT, "poly": [[0.22, -0.44], [0.56, -0.64], [0.26, -0.28]]},
	],
	# Goblin archer: the same small hunch with a bow arc standing clear of it, so
	# a player can pick the ranged ones out of a crowd of goblins at a glance.
	&"goblin_archer": [
		{"tint": Tint.ACCENT, "poly": [[-0.36, -0.7], [-0.56, -0.34], [-0.56, 0.28], [-0.36, 0.62], [-0.44, 0.3], [-0.44, -0.36]]},
		{"tint": Tint.ACCENT, "poly": [[-0.4, -0.68], [0.2, -0.04], [0.16, 0.02], [-0.42, 0.6]]},
		{"tint": Tint.TEAM_DARK, "poly": [[-0.44, 1.0], [-0.28, 0.52], [0.44, 0.52], [0.6, 1.0], [0.08, 0.9]]},
		{"tint": Tint.TEAM, "poly": [[-0.26, 0.58], [-0.16, 0.02], [0.1, -0.18], [0.4, 0.04], [0.46, 0.58]]},
		{"tint": Tint.TEAM, "poly": [[0.0, -0.16], [0.06, -0.48], [0.32, -0.48], [0.36, -0.14]]},
		{"tint": Tint.ACCENT, "poly": [[0.32, -0.42], [0.62, -0.6], [0.36, -0.26]]},
	],
	# Ghoul: tall, gaunt, arms past the knees, no weapon. The only outline here
	# that is narrow at the shoulders and wide at the hands, which is what should
	# read as "this one walks at you and does not stop".
	&"ghoul": [
		{"tint": Tint.TEAM_DARK, "poly": [[-0.56, 1.0], [-0.3, 0.36], [0.3, 0.36], [0.56, 1.0], [0.0, 0.9]]},
		{"tint": Tint.TEAM, "poly": [[-0.28, 0.42], [-0.22, -0.34], [0.0, -0.54], [0.22, -0.34], [0.28, 0.42]]},
		{"tint": Tint.TEAM, "poly": [[-0.34, -0.28], [-0.6, 0.2], [-0.7, 0.66], [-0.5, 0.7], [-0.42, 0.24], [-0.2, -0.14]]},
		{"tint": Tint.TEAM, "poly": [[0.34, -0.28], [0.6, 0.2], [0.7, 0.66], [0.5, 0.7], [0.42, 0.24], [0.2, -0.14]]},
		{"tint": Tint.TEAM, "poly": [[0.0, -0.56], [0.2, -0.74], [0.12, -0.98], [-0.12, -0.98], [-0.2, -0.74]]},
		{"tint": Tint.ACCENT, "poly": [[-0.7, 0.62], [-0.86, 0.86], [-0.64, 0.82]]},
		{"tint": Tint.ACCENT, "poly": [[0.7, 0.62], [0.86, 0.86], [0.64, 0.82]]},
	],
	# Cultist: teal is renaming dungeon_cultist to cultist. Same silhouette,
	# because it was already right — a hood and a robe and no legs, reading as a
	# caster from the outline and as nothing like the Priest, whose halo sits
	# clear above the head while this one has a beak of a hood.
	&"cultist": [
		{"tint": Tint.TEAM_DARK, "poly": [[-0.76, 1.0], [-0.44, 0.3], [0.44, 0.3], [0.76, 1.0], [0.0, 0.92]]},
		{"tint": Tint.TEAM, "poly": [[0.0, -0.92], [0.34, -0.42], [0.5, 0.5], [-0.5, 0.5], [-0.34, -0.42]]},
		{"tint": Tint.TEAM_DARK, "poly": [[0.0, -0.9], [0.26, -0.4], [0.0, -0.24], [-0.26, -0.4]]},
		{"tint": Tint.ACCENT, "poly": [[-0.06, -0.66], [0.1, -0.58], [-0.06, -0.5]]},
		{"tint": Tint.ACCENT, "poly": [[0.32, -0.12], [0.62, 0.02], [0.54, 0.26], [0.28, 0.14]]},
		{"tint": Tint.ACCENT, "poly": [[-0.3, -0.06], [-0.6, 0.08], [-0.52, 0.32], [-0.26, 0.2]]},
	],

	# --- the Rat King fight (floor 1 miniboss) ------------------------------
	#
	# README: "Big collection of rats joined at the tail. Ranged attacker, all
	# attacks leave behind rats which are close range melee attackers."
	#
	# So this is TWO shapes and one relationship, and the relationship is the
	# hard part: the miniboss has to read as a pile of the very thing it keeps
	# spawning. They are drawn as a pair on purpose and should be edited as one.
	#
	# Rat: redrawn. The first version was a mound with a spike, and rendered
	# beside `grub` and `brute` it was a third mound -- the exact "squint and two
	# are the same blob" failure this file warns about, sitting in the file
	# underneath the warning. It is now the longest and lowest outline in the
	# game, which is a silhouette nothing else here competes for: snout forward
	# and clear, one ear breaking the skull line, tail lifted off the ground with
	# real space under it. A tail lying along the floor merges into the shadow
	# and stops being a tail.
	&"rat": [
		# Tail: long, thick at the root, sweeping up and back well clear of the
		# body. Drawn in TEAM rather than ACCENT and that is deliberate -- ACCENT
		# is near-white and the first version put the loudest colour in the game
		# on a thin curl, which rendered as a bright hook stuck to a mound.
		{"tint": Tint.TEAM, "poly": [[-0.56, 0.34], [-0.80, 0.16], [-0.96, -0.30], [-0.78, -0.36], [-0.66, 0.02], [-0.46, 0.16]]},
		# Ground shadow. Narrower than the body on purpose: the first pass had it
		# as wide as the animal and the two merged into one blob.
		{"tint": Tint.TEAM_DARK, "poly": [[-0.62, 1.00], [-0.50, 0.66], [0.62, 0.66], [0.74, 1.00], [0.06, 0.94]]},
		# Back: LOW. This is the whole identity -- the longest, flattest outline
		# in the game, against a roster of mounds and spires. The peak is barely
		# above the shoulder and the line runs almost flat to the hips.
		{"tint": Tint.TEAM, "poly": [[-0.62, 0.70], [-0.60, 0.10], [-0.34, -0.14], [0.16, -0.20], [0.40, -0.10], [0.46, 0.70]]},
		# Head and snout: one wedge tapering to a point on the right edge, well
		# outside the body outline so the animal has a front end.
		{"tint": Tint.TEAM, "poly": [[0.30, -0.16], [0.56, -0.20], [1.00, 0.24], [0.62, 0.46], [0.34, 0.36]]},
		# Ear, standing clear above the skull line and reading against the sky.
		{"tint": Tint.TEAM_DARK, "poly": [[0.34, -0.18], [0.34, -0.62], [0.64, -0.30], [0.58, -0.14]]},
		# Foot, so the body is not resting flat on its own shadow.
		{"tint": Tint.TEAM_DARK, "poly": [[-0.30, 0.62], [-0.16, 0.62], [-0.12, 0.86], [-0.30, 0.86]]},
		# Eye. The only ACCENT on the shape, and it is two pixels at true size --
		# which is correct: at 22 across, the outline is the whole read.
		{"tint": Tint.ACCENT, "poly": [[0.62, 0.06], [0.74, 0.12], [0.62, 0.18]]},
	],
	# The Rat King. Everything else in this game reads as ONE creature; this has
	# to read as MANY, and that is its whole visual identity rather than being
	# large. A miniboss that arrives as a big goblin is a reskin.
	#
	# Three devices carry it, and they are listed in the order they survive
	# shrinking, because at 55 pixels across only the first two do any work:
	#
	#   1. A SCALLOPED top edge. Three overlapping backs, not one dome. A dome is
	#      one animal at any size.
	#   2. Heads pointing three DIFFERENT WAYS, each with clear space around it.
	#      One creature cannot look left and right at once, so this is the cue
	#      that does not need resolution to land.
	#   3. The tail knot, which is the literal reading of "joined at the tail"
	#      and the one detail no other silhouette in the game carries -- the same
	#      job the Warden's chain does. It is the identity at inspect size and it
	#      is mostly gone at true size, which is the right way round.
	&"rat_king": [
		# THE KNOT, and it is drawn in TEAM_DARK rather than ACCENT after looking
		# at it. Five near-white strands radiating from one point did not read as
		# tails: it read as a crown, or an explosion, and at true size it was a
		# white starburst sitting on top of the fight -- the loudest thing on the
		# screen spent on the detail that matters least at that size. Three short
		# HOOKED strands in the body's own dark now, so it reads as matted tails
		# from close up and quietly disappears into the mass from far away.
		# In TEAM, not TEAM_DARK: the strands rise ABOVE the pile and are read
		# against the background, and the dark version was invisible there. Thin
		# enough that they are two or three pixels at true size, which is the
		# right way round -- this detail is for the inspect panel.
		{"tint": Tint.TEAM, "poly": [[-0.12, -0.40], [-0.34, -0.68], [-0.54, -0.74], [-0.50, -0.62], [-0.30, -0.56], [-0.16, -0.34]]},
		{"tint": Tint.TEAM, "poly": [[-0.04, -0.46], [-0.10, -0.76], [0.04, -0.94], [0.14, -0.84], [0.04, -0.70], [0.08, -0.44]]},
		{"tint": Tint.TEAM, "poly": [[0.12, -0.38], [0.36, -0.62], [0.56, -0.64], [0.52, -0.50], [0.32, -0.48], [0.18, -0.30]]},
		# The braid itself, where the three meet: dark, so the strands read as
		# separate above it and matted together at the root.
		{"tint": Tint.TEAM_DARK, "poly": [[-0.16, -0.34], [0.0, -0.48], [0.18, -0.34], [0.08, -0.14], [-0.10, -0.16]]},

		# Ground shadow, the widest in the game. This is a pile, not a body.
		{"tint": Tint.TEAM_DARK, "poly": [[-1.00, 1.00], [-0.88, 0.56], [0.88, 0.56], [1.00, 1.00], [0.0, 0.90]]},

		# THREE BACKS WITH REAL VALLEYS BETWEEN THEM, and every one of them
		# ROUNDED. Two passes were needed and both failures are worth keeping:
		# the first overlapped the humps so heavily they fused into one dome,
		# which is one animal at any size; the second separated them but left
		# them as five-point wedges, and three sharp peaks over a dark base read
		# as a MOUNTAIN RANGE, which is the third time a shape of mine has come
		# out as a picture of something else. A back is a dome. The extra
		# vertices are what make the valleys U-shaped instead of V-shaped, and a
		# V-notch is what makes a row of humps look like terrain.
		{"tint": Tint.TEAM, "poly": [[-0.96, 0.62], [-0.94, 0.16], [-0.86, -0.08], [-0.70, -0.24], [-0.52, -0.22], [-0.40, -0.02], [-0.36, 0.20], [-0.34, 0.62]]},
		{"tint": Tint.TEAM, "poly": [[-0.32, 0.62], [-0.30, 0.14], [-0.22, -0.18], [-0.08, -0.40], [0.08, -0.40], [0.22, -0.18], [0.30, 0.14], [0.32, 0.62]]},
		{"tint": Tint.TEAM, "poly": [[0.34, 0.62], [0.36, 0.20], [0.40, -0.02], [0.52, -0.22], [0.70, -0.24], [0.86, -0.08], [0.94, 0.16], [0.96, 0.62]]},

		# THREE HEADS, THREE DIRECTIONS. One creature cannot look left and right
		# at once, so this is the cue that needs no resolution to land. Each is a
		# wedge tapering to a snout OUTSIDE the pile's outline, with an ear above
		# it -- the first pass kept them inside the mass and they read as
		# arrowheads stuck to the sides.
		# Left, looking out and slightly down.
		{"tint": Tint.TEAM, "poly": [[-0.44, 0.12], [-0.64, 0.0], [-0.86, 0.16], [-1.00, 0.40], [-0.80, 0.52], [-0.56, 0.48], [-0.44, 0.32]]},
		{"tint": Tint.TEAM_DARK, "poly": [[-0.70, 0.02], [-0.78, -0.26], [-0.54, -0.14], [-0.56, 0.04]]},
		{"tint": Tint.ACCENT, "poly": [[-0.74, 0.24], [-0.80, 0.26], [-0.80, 0.32], [-0.74, 0.30]]},
		# Right, looking out and slightly down.
		{"tint": Tint.TEAM, "poly": [[0.44, 0.12], [0.64, 0.0], [0.86, 0.16], [1.00, 0.40], [0.80, 0.52], [0.56, 0.48], [0.44, 0.32]]},
		{"tint": Tint.TEAM_DARK, "poly": [[0.70, 0.02], [0.78, -0.26], [0.54, -0.14], [0.56, 0.04]]},
		{"tint": Tint.ACCENT, "poly": [[0.74, 0.24], [0.80, 0.26], [0.80, 0.32], [0.74, 0.30]]},
		# Front and low, over the shadow, so the BOTTOM edge is broken too. A
		# pile with a clean floor line still reads as one object sitting down.
		{"tint": Tint.TEAM, "poly": [[0.06, 0.44], [-0.16, 0.46], [-0.34, 0.62], [-0.36, 0.86], [-0.14, 0.96], [0.06, 0.86], [0.14, 0.64]]},
		{"tint": Tint.TEAM_DARK, "poly": [[0.02, 0.44], [0.14, 0.22], [0.24, 0.44], [0.14, 0.54]]},
		{"tint": Tint.ACCENT, "poly": [[-0.18, 0.66], [-0.24, 0.70], [-0.22, 0.76], [-0.16, 0.72]]},
	],
	# Grub: one soft segmented arc, no limbs and no weapon. The only shape here
	# with no straight vertical edge at all.
	&"grub": [
		{"tint": Tint.TEAM_DARK, "poly": [[-0.84, 1.0], [-0.92, 0.52], [0.92, 0.52], [0.84, 1.0], [0.0, 0.9]]},
		{"tint": Tint.TEAM, "poly": [[-0.9, 0.58], [-0.72, 0.0], [-0.4, -0.34], [0.0, -0.46], [0.4, -0.34], [0.72, 0.0], [0.9, 0.58]]},
		{"tint": Tint.TEAM_DARK, "poly": [[-0.5, -0.24], [-0.34, -0.5], [-0.16, -0.36], [-0.3, -0.14]]},
		{"tint": Tint.TEAM_DARK, "poly": [[0.16, -0.36], [0.34, -0.5], [0.5, -0.24], [0.3, -0.14]]},
		{"tint": Tint.ACCENT, "poly": [[-0.26, -0.44], [-0.16, -0.6], [-0.06, -0.44], [-0.16, -0.32]]},
		{"tint": Tint.ACCENT, "poly": [[0.06, -0.44], [0.16, -0.6], [0.26, -0.44], [0.16, -0.32]]},
	],
	# Brute: the largest outline of all, hunched forward, tiny head set low
	# between the shoulders, club head heavier than the arm holding it.
	&"brute": [
		{"tint": Tint.ACCENT, "poly": [[0.44, -0.36], [0.66, -0.98], [0.98, -0.86], [0.9, -0.28], [0.6, -0.14]]},
		{"tint": Tint.ACCENT, "poly": [[0.34, 0.28], [0.5, -0.28], [0.68, -0.22], [0.52, 0.34]]},
		{"tint": Tint.TEAM_DARK, "poly": [[-1.0, 1.0], [-0.74, 0.34], [0.74, 0.34], [1.0, 1.0], [0.0, 0.88]]},
		{"tint": Tint.TEAM, "poly": [[-0.94, 0.4], [-0.88, -0.3], [-0.56, -0.68], [0.2, -0.72], [0.66, -0.4], [0.76, 0.4]]},
		{"tint": Tint.TEAM_DARK, "poly": [[-0.2, -0.62], [-0.24, -0.88], [0.14, -0.9], [0.2, -0.64]]},
		{"tint": Tint.ACCENT, "poly": [[-0.16, -0.8], [-0.06, -0.86], [-0.02, -0.74]]},
		{"tint": Tint.ACCENT, "poly": [[0.02, -0.82], [0.12, -0.86], [0.14, -0.72]]},
	],
	# Siege engine: the Siege Master's summon. Built to read as a machine rather
	# than a creature -- a wide low frame on legs with a long throwing arm held
	# clear of the body, following sable's rule that a feature only counts if
	# negative space separates it from the mass.
	#
	# It had no shape at all until the player said "siege master engines are
	# currently invisible" while playing. It was drawing the unknown-shape
	# fallback, and the test below never caught it because that test walks
	# encounter spawn lists and a summoned unit appears in none.
	&"siege_engine": [
		# Throwing arm, detached along its length, raised back and to the right.
		{"tint": Tint.ACCENT, "poly": [[0.16, -0.30], [0.62, -0.86], [0.78, -0.72], [0.32, -0.16]]},
		{"tint": Tint.ACCENT, "poly": [[0.58, -0.98], [0.86, -0.84], [0.74, -0.60], [0.50, -0.74]]},
		# Low wide frame.
		{"tint": Tint.TEAM_DARK, "poly": [[-0.94, 0.72], [-0.72, 0.18], [0.72, 0.18], [0.94, 0.72], [0.0, 0.62]]},
		{"tint": Tint.TEAM, "poly": [[-0.80, 0.24], [-0.66, -0.28], [0.30, -0.34], [0.56, 0.10], [0.62, 0.24]]},
		# Legs, with real gaps between them and the frame.
		{"tint": Tint.TEAM_DARK, "poly": [[-0.66, 0.74], [-0.52, 0.74], [-0.44, 1.0], [-0.60, 1.0]]},
		{"tint": Tint.TEAM_DARK, "poly": [[0.48, 0.74], [0.62, 0.74], [0.70, 1.0], [0.54, 1.0]]},
		# Bolt already nocked, pointing left, clear of the frame.
		{"tint": Tint.ACCENT, "poly": [[-0.98, -0.12], [-0.60, -0.20], [-0.58, -0.06], [-0.96, 0.02]]},
	],
	# Floor 1's boss. Built to read as a boss at a glance and at phone size:
	# it fills more of its radius than anything else here, stands squarer, and
	# carries the one silhouette detail no other unit has -- a chain, for the
	# 270-range toss that stops a party declining the fight from out of reach.
	# Bosses should be recognisable before the health bar is read.
	&"the_warden": [
		# Chain, trailing to the unit's left, drawn first so the body sits on it.
		{"tint": Tint.ACCENT, "poly": [[-1.0, 0.18], [-0.82, 0.06], [-0.72, 0.2], [-0.9, 0.32]]},
		{"tint": Tint.ACCENT, "poly": [[-0.72, 0.02], [-0.54, -0.1], [-0.44, 0.04], [-0.62, 0.16]]},
		{"tint": Tint.ACCENT, "poly": [[-0.44, -0.14], [-0.26, -0.26], [-0.16, -0.12], [-0.34, 0.0]]},
		# Heavy square stance.
		{"tint": Tint.TEAM_DARK, "poly": [[-0.86, 1.0], [-0.7, 0.42], [0.7, 0.42], [0.86, 1.0], [0.0, 0.9]]},
		# Bulk: wider and taller than any other silhouette in this file.
		{"tint": Tint.TEAM, "poly": [[-0.82, 0.46], [-0.9, -0.44], [-0.5, -0.86], [0.5, -0.86], [0.9, -0.44], [0.82, 0.46]]},
		# Helm, closed, with a single visor slit rather than eyes.
		{"tint": Tint.TEAM_DARK, "poly": [[-0.44, -0.86], [-0.36, -1.0], [0.36, -1.0], [0.44, -0.86]]},
		{"tint": Tint.ACCENT, "poly": [[-0.3, -0.94], [0.3, -0.94], [0.3, -0.86], [-0.3, -0.86]]},
		# Pauldrons, to break the outline at the shoulders so it is not a slab.
		{"tint": Tint.TEAM_DARK, "poly": [[-0.98, -0.5], [-0.72, -0.72], [-0.5, -0.5], [-0.76, -0.34]]},
		{"tint": Tint.TEAM_DARK, "poly": [[0.98, -0.5], [0.72, -0.72], [0.5, -0.5], [0.76, -0.34]]},
	],
}

## Every shape id this file knows, sorted. Sorted because anything iterating
## content has to be deterministic, and a Dictionary's order is not something to
## rely on.
static func shape_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for k in _PARTS.keys():
		ids.append(k)
	ids.sort()
	return ids

static func has_shape(id: StringName) -> bool:
	return _PARTS.has(id)

## Draws one unit's silhouette centred on the origin of `canvas`, sized so it
## fits a circle of `radius`.
##
## `shape_id` falls back to a plain marker rather than drawing nothing, because
## an invisible unit is a far worse failure than an ugly one: a fight where a
## combatant cannot be seen looks like a simulation bug and is not.
static func draw_unit(
	canvas: CanvasItem,
	shape_id: StringName,
	radius: float,
	team: CG.Team,
	accent: CG.DamageType,
	facing_left: bool = false,
	center: Vector2 = Vector2.ZERO
) -> void:
	# Real art wins if somebody has dropped a file in for this shape. This is the
	# single seam that makes the placeholders replaceable without touching any
	# caller: put Assets/Units/<shape_id>.png on disk and it appears. See the
	# header of UnitArt.gd for the whole procedure.
	#
	# `center` exists so a caller that needs the shape somewhere other than the
	# origin — a card, a roster row, a tooltip — can still come through here and
	# get the art. Anything that reaches for build_parts to move the shape
	# instead will silently keep drawing placeholders forever after somebody
	# replaces the art, which is a nasty thing to discover.
	var tex := UnitArt.texture_for(shape_id, team)
	if tex != null:
		# `center` is an additive offset here, not a transform reset -- see the
		# comment on UnitArt.draw for why that distinction is load-bearing.
		UnitArt.draw(canvas, tex, radius, facing_left, center)
		return

	for part in build_parts(shape_id, radius, team, accent, facing_left, center):
		# A darker edge under every part. Without it the accent shapes bleed into
		# the body at the sizes these actually get drawn at. `draw_outlined_
		# polygon` is the one closed-polyline helper the art files share; a
		# transparent fill is how an outline-only part asks for no fill.
		var fill: Color = part["fill"] if part["filled"] else Color(0.0, 0.0, 0.0, 0.0)
		UIArt.draw_outlined_polygon(canvas, part["points"], fill, part["outline"], part["outline_width"])

## Every polygon of a shape, resolved to world-space points and final colours.
##
## Split out from `draw_unit` so it can be tested. Godot refuses `draw_*` calls
## outside `_draw()`, so a test that calls `draw_unit` directly logs a wall of
## errors and asserts nothing — which is exactly what the first version of the
## test for this file did, and it "passed". Geometry and colour are the parts
## that can be wrong silently; the drawing itself is four engine calls.
## NOTE: this returns polygons and therefore never returns replacement art. If
## you are drawing a unit, call `draw_unit` — it takes a `center` for exactly
## the case that makes people reach for this function instead, and it is the
## only path that honours Assets/Units/.
static func build_parts(
	shape_id: StringName,
	radius: float,
	team: CG.Team,
	accent: CG.DamageType,
	facing_left: bool = false,
	center: Vector2 = Vector2.ZERO
) -> Array[Dictionary]:
	var team_color := Palette.team_color(team)
	var colors := {
		Tint.TEAM: team_color,
		Tint.TEAM_DARK: team_color.darkened(0.45),
		Tint.ACCENT: Palette.damage_color(accent),
		Tint.OUTLINE: Palette.ARENA_EDGE,
	}

	var parts: Array = _PARTS.get(shape_id, [])
	if parts.is_empty():
		return _unknown_parts(radius, team_color, center)

	var flip := -1.0 if facing_left else 1.0
	var out: Array[Dictionary] = []
	for part in parts:
		var points := PackedVector2Array()
		for p in part["poly"]:
			points.append(Vector2(float(p[0]) * flip, float(p[1])) * radius + center)
		out.append({
			"points": points,
			"fill": colors[part["tint"]],
			"outline": colors[Tint.OUTLINE],
			"outline_width": 1.0,
			"filled": true,
		})
	return out

## The fallback. Deliberately unlike every real shape: a hollow diamond reads
## instantly as "this one has no art yet" rather than as a new enemy type.
static func _unknown_parts(radius: float, team_color: Color, center: Vector2 = Vector2.ZERO) -> Array[Dictionary]:
	return [{
		"points": PackedVector2Array([
			Vector2(0.0, -radius) + center, Vector2(radius, 0.0) + center,
			Vector2(0.0, radius) + center, Vector2(-radius, 0.0) + center,
		]),
		"fill": team_color,
		"outline": team_color,
		"outline_width": 2.0,
		"filled": false,
	}]
