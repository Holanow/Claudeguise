# Unit art

A unit is a **recipe**, not a drawing, and it is never flattened into one.
`Scripts/Art/UnitRecipes.gd` names the parts it is made of and sorts them into
fixed slots; `Scripts/UI/UnitVisual.gd` builds a `Sprite2D` per part under a node
per slot. **Everything in this folder is a part.** There is no per-unit file.

Issue 566 replaced twenty-six hand drawings with recipes. The fixed-slot change
then deleted the 242 files those recipes were baked into: one composite per unit
per side, three animation slices, and one file per death chunk. Only the 27 parts
remain, and a new creature adds none of them.

## Adding a creature

Add a recipe to `Scripts/Art/UnitRecipes.gd`. That is the whole step. Nothing is
baked, nothing is committed, and the creature is on screen the next time the game
runs.

`Tools/BakeParts.gd` is run only when a **part's shape** changes, which is rare:

```
powershell -ExecutionPolicy Bypass -File Tools\run.ps1 BakeParts -Headless
```

It draws the 27 parts from the polygon source in that file, dilates an outline
ring around each one, and writes them here. Commit what it wrote.

**A variant costs one part.** `goblin_archer` is the goblin's recipe plus a hat;
`dungeon_archer` and `dungeon_cultist` are `dungeon_grunt` plus a hood;
`rat_king` is the rat plus a gold hat. Use `{"base": &"other_id", "add": [...]}`
rather than copying a stack, or the two drift.

**A missing part is a black square.** The player's ruling, and deliberate: an
obvious defect beats a silent hole in a body.

## The slots

Six, and they are the draw order, top to bottom of the list drawn last:

`Body`, `Head`, `Headwear`, `Face`, `Hands`, `Extra`.

A slot holds as many parts as the recipe put in it, in the order the recipe named
them, because six slots cannot hold seven parts and `goblin_archer` has seven. A
slot the recipe put nothing in draws nothing.

**`Headwear` is under `Face`.** A hood covers the pixels the eyes sit on, so with
Face first the Priest, the Cultist, both hooded dungeon soldiers, the Siege
Master and The Warden all lose their eyes.

A part named in no slot lands in `Extra`, so a part added later draws last rather
than silently joining a group it was never put in.

**A slot is not a chunk.** Issue 630: slots are a drawing taxonomy and the chunks
a death throws are a physical one. `UnitRecipes.CHUNK_OF_SLOT` maps `Head`,
`Headwear` and `Face` into one `head` chunk, because a hat and a pair of eyes
travel with the head they are worn on; `Extra` maps to nothing, so a siege
engine's wheels and barrel leave separately and so does a part nobody has
slotted.

## The parts vocabulary

Bodies are the player's three, plus one for the things that are not people:
`body_skinny` (capsule), `body_muscular` (inverted triangle, floored at half the
capsule's width), `body_rotund` (circle), `body_low`.

Heads are `head_round`, `head_tall`, `head_small`, `head_snouted`. Features are
`ears_pointed`, `nose_triangle`, `horns`, `crown`, `hood`, `hat`, `hat_low`,
`helm`, `plume`, `spikes`, `tusks`, `mandibles`, `tail`, `eyes`, `eyes_snout`,
`barrel`, `wheels`. Hands are `hands` and `hands_wide`, free-floating circles
with no arm.

**Every part carries its own outline ring, baked into its own PNG.** That is what
gives a head an edge where it crosses a body, and it is why nothing has to be
composited to get one. The recipe's colour is applied as the sprite's `modulate`,
so one `body_skinny` serves a green goblin and a robed priest -- and the ring is
tinted with it, which is the one pixel-level difference from the composites this
replaced.

Parts are authored in a 32-unit square and rasterised at 256, so every coordinate
reads as a proportion of a body and the canvas size is one constant.

## Every unit, and what it is made of

| Unit | Recipe |
| --- | --- |
| `warrior` | muscular body, plume |
| `priest` | capsule body, hood |
| `geysermancer` | capsule body, hat |
| `siege_master` | muscular body, helm |
| `abomination` | rotund body, horns, tusks |
| `goblin` | capsule body, pointed ears, nose |
| `goblin_archer` | **the goblin, plus a hat** |
| `dungeon_grunt` | muscular body |
| `dungeon_archer` | **the grunt, plus a hood** |
| `dungeon_cultist` | **the grunt, plus a purple hood** |
| `rat` | low body, snouted head, tail |
| `rat_king` | **the rat, plus a gold hat** |
| `brute` | muscular body, horns |
| `cultist` | capsule body, hood |
| `ghoul` | capsule body, tusks |
| `grub` | rotund body, mandibles |
| `stalker` | capsule body, tail |
| `siege_engine` | rotund body, wheels, barrel |
| `the_warden` | muscular body, helm |

A side is a colour, never a file: a layer marked `"team": true` takes
`Palette.team_color`, and every part is shared by both sides and by every recipe
that names it.
