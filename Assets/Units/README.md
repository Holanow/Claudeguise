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
| `dungeon_grunt.png` | Grunt |
| `dungeon_archer.png` | Archer |
| `dungeon_cultist.png` | Cultist |

`rat.png`, `grub.png` and `brute.png` also exist as shapes but nothing spawns
them yet.

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
