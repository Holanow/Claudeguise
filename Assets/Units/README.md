# Replacing the placeholder art

Every unit in the game is currently drawn as coloured polygons defined in
`Scripts/Art/Silhouettes.gd`. They are placeholders and they are meant to be
thrown away.

## The whole procedure

**Drop a PNG in this folder, named after the unit.** That is all.

```
Assets/Units/warrior.png
Assets/Units/dungeon_grunt.png
```

No code change. No scene to edit. No import step, no registration, no restart of
anything but the game. The moment a file with the right name exists, the game
draws it instead of the polygon.

Delete the file and the placeholder comes back, which makes it safe to try one
and change your mind.

## The names

The filename is the unit's id. These are the current ones:

| File | What it draws |
| --- | --- |
| `warrior.png` | Warrior |
| `priest.png` | Priest |
| `geysermancer.png` | Geysermancer |
| `siege_master.png` | Siege Master |
| `abomination.png` | Abomination |
| `goblin.png` | Goblin |
| `goblin_archer.png` | Goblin Archer |
| `ghoul.png` | Ghoul |
| `cultist.png` | Cultist |
| `the_warden.png` | The Warden (floor 1 boss) |
| `dungeon_grunt.png` | Grunt (being retired) |
| `dungeon_archer.png` | Archer (being retired) |
| `dungeon_cultist.png` | Cultist (being retired) |
| `brute.png` | Brute — the heavy that stuns |
| `stalker.png` | Stalker — marks a pawn for everything else to shoot |
| `rat_king.png` | The Rat King (floor 1 miniboss) |
| `rat.png` | Rat — what the Rat King leaves behind |

`grub.png` also exists as a shape but nothing spawns it yet.

**The Stalker is meant to look like it does not matter.** It is the smallest
outline in the game, thinner than a goblin, and that is deliberate rather than a
shortcut: it has 30 health and almost no attack, and it kills parties by marking
one pawn so everything else concentrates on it. If you redraw it, the thing to
keep is the contradiction. Its only heavy cue is that it *points* — a straight
needle held level, clear of the body. It is the one unit in the game aiming at
you, and everything else about it is slight.

**The Warden has to read as a creature and it has to point.** Issue #241, from
the player watching it at true size: *"It reads as an object, not a creature —
horizontal axis, squat mass with a lintel, looks like furniture beside the
pawns."* Two things fixed that and both are worth keeping in a replacement.
**The head is a lobe of its own, standing above the shoulder line and forward**,
with open space between it and the hunched back; inlaid flush in the top edge it
was a moulding, not a head. And **four cues agree on which way it faces** — helm
forward, visor slit breaking the front edge, back hunched behind, front foot
ahead of the rear one — because facing is information the simulation really
keeps (`CombatUnit.facing` gates the Warrior's guard) and one detail carrying it
is one detail a player can miss.

**Its box is square, and that is where its size comes from.** The Warden's
collision radius is 22, exactly a pawn's, so nothing about the fight makes it
big; the only mass available to it is the box, and the file's *longest* side is
what spans the unit's diameter. The old file was 24x19 and threw away a fifth of
the height it was allowed. Replace it with a square one.

**The chain is gone from the sprite and that is a deliberate loss.** It was the
one silhouette detail no other unit had, for the 270-range chain toss. At 24
pixels every version of it came out as two or three cream pixels beside the body
that read as dirt, and in this palette pale is the loudest colour on the unit. It
survives where there is resolution for it: the action icon, the projectile, and
the polygon fallback in `Scripts/Art/Silhouettes.gd`. If you redraw the Warden at
a size that can carry a chain, put it back.

**The Rat King and the rat are a pair and should be replaced as one.** The
README describes the miniboss as *"a big collection of rats joined at the tail"*
whose attacks *"leave behind rats"*, so the fight is a pile of the very thing it
keeps spawning. The generated art carries that relationship in the silhouette —
the pile is three rounded backs with three heads facing three different ways,
and the rat is one of those backs and one of those heads at a third of the size.
If you replace only one of them, the fight stops being about one creature.

`Screenshots/rat_king.png` shows both, at design size and at the size the game
actually draws them, with the Warden beside them for scale.

**This table is checked by a test.** `Tests/test_art.gd` walks the real content
registry and fails if this list drifts from what the game actually asks for, so
if somebody adds an enemy and forgets to update this file, the gate says so
rather than you finding out by dropping in a PNG that never appears.

## If a unit should look different per side

Add `.player` or `.enemy` before the extension:

```
Assets/Units/warrior.player.png
Assets/Units/warrior.enemy.png
```

The side-specific file wins. Without one, the plain `warrior.png` is used for
both. Most units only ever appear on one side, so you will rarely need this.

## Size and shape

- **Any size.** The image is scaled so its longest side spans the unit's
  diameter, currently 44 pixels of world space.
- **Aspect ratio is preserved.** A tall image stays tall rather than being
  squashed into a square.
- **Transparency works.** The arena floor shows through.
- **The centre of the image is the unit's position**, and it is what ranges,
  movement and targeting are measured from. If your art has a lot of empty space
  on one side, the unit will look offset from where it actually is.
- **Facing:** art is mirrored horizontally when a unit faces left. Draw it facing
  right.

## Verified, not assumed

The drop-in path was tested rather than reasoned about: a deliberately garish
magenta PNG was placed here as `abomination.png`, the real game was launched, and
the Abomination rendered as that image in the fight. The file was then deleted
and the polygon came back. `Tools/preview/` no longer contains that render, but
the procedure above is the one that was exercised.

**One place is still catching up.** The party select cards currently draw
placeholders through a different code path and will keep doing so until pike
switches them over — so with art dropped in, you will see it in the fight and not
yet on the class cards. The function they need now exists. If you are reading
this after that has landed, this paragraph should be gone; if it is still here,
it is still true.

## One thing worth knowing

These images are read with `Image.load()` and turned into textures at runtime,
rather than through Godot's normal import pipeline. That is deliberate: the Godot
editor does not currently run on this machine (see the header of
`Scripts/Core/CG.gd`), so anything requiring an import step would be impossible
to add here.

The upshot for you is good: **your PNG works whether or not the editor has ever
seen it.** If the editor becomes usable later, nothing about this changes and
nothing needs migrating.
