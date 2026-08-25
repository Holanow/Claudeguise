# Unit art

A unit is a **recipe**, not a drawing. `Scripts/Art/UnitRecipes.gd` names the
parts it is made of; `Tools/BakeParts.gd` draws the parts, composes each recipe
for both teams, and writes the result here as `<id>.player.png` and
`<id>.enemy.png`. `UnitArt.texture_for` loads those files and nothing else.

Issue 566 replaced twenty-six hand drawings with this. The reason is the one the
player gave: a new enemy should be *easier to make*, and `README.md` at the repo
root carries seven bosses and seven mini-bosses of which two exist.

## Adding a creature

1. Add a recipe to `Scripts/Art/UnitRecipes.gd`.
2. Run the bake:

   ```
   powershell -ExecutionPolicy Bypass -File Tools\run.ps1 BakeParts -Headless
   ```

3. Commit the parts and the composed files it wrote.

The bake writes the same recipe three ways, and all three are committed art:

- `<id>.<side>.png` here, the flat body `UnitArt.texture_for` draws.
- `slices/<id>.<side>.s<n>.png`, the recipe cut at the parts that move, which
  is what issue 583's animation draws.
- `fragments/<id>.<side>.f<n>.png`, the recipe cut into the chunks a death
  throws (issue 589), grouped body / head / hands. A part named in no group is
  its own chunk, so a new part flies on its own rather than silently joining the
  body it was drawn over. The bake also deletes a chunk file a shrunk recipe no
  longer writes; without that, a part removed later leaves dead art in git.

**A variant costs one part.** `goblin_archer` is the goblin's recipe plus a hat;
`dungeon_archer` and `dungeon_cultist` are `dungeon_grunt` plus a hood;
`rat_king` is the rat plus a gold hat. Use `{"base": &"other_id", "add":
[...]}` rather than copying a stack, or the two drift.

**A missing part is a black square.** The player's ruling, and deliberate: an
obvious defect beats a silent hole in a body.

## The parts vocabulary

Bodies are the player's three, plus one for the things that are not people:
`body_skinny` (capsule), `body_muscular` (inverted triangle, floored at half the
capsule's width), `body_rotund` (circle), `body_low`.

Heads are `head_round`, `head_tall`, `head_small`, `head_snouted`. Features are
`ears_pointed`, `nose_triangle`, `horns`, `crown`, `hood`, `hat`, `helm`,
`plume`, `spikes`, `tusks`, `mandibles`, `tail`, `eyes`, `eyes_snout`,
`barrel`, `wheels`. Hands are `hands` and `hands_wide`, free-floating circles
with no arm.

Every part carries its own outline, so a head has an edge where it crosses a
body. Parts are authored in a 32-unit square and rasterised at 256, so every
coordinate reads as a proportion of a body and the canvas size is one constant.

## Replacing a unit with a hand drawing instead

The old path still works, and it is how every unit here looked before issue 566.
For a unit whose id is `X`:

1. Delete its recipe from `Scripts/Art/UnitRecipes.gd`.
2. Delete the composed `X.player.png` and `X.enemy.png` from this folder.
3. Drop your drawing in as `X.png`, or as `X.player.png` and `X.enemy.png` if
   the two sides should differ.

Step 2 matters: a side-specific file is preferred over a shared one, so a
composed `X.player.png` left behind will beat the `X.png` you just added.

## Every unit, and what it is made of

| Unit | Recipe |
| --- | --- |
| `warrior.png` | muscular body, plume |
| `priest.png` | capsule body, hood |
| `geysermancer.png` | capsule body, hat |
| `siege_master.png` | muscular body, helm |
| `abomination.png` | rotund body, horns, tusks |
| `goblin.png` | capsule body, pointed ears, nose |
| `goblin_archer.png` | **the goblin, plus a hat** |
| `dungeon_grunt.png` | muscular body |
| `dungeon_archer.png` | **the grunt, plus a hood** |
| `dungeon_cultist.png` | **the grunt, plus a purple hood** |
| `rat.png` | low body, snouted head, tail |
| `rat_king.png` | **the rat, plus a gold hat** |
| `brute.png` | muscular body, horns |
| `cultist.png` | capsule body, hood |
| `ghoul.png` | capsule body, tusks |
| `grub.png` | rotund body, mandibles |
| `stalker.png` | capsule body, tail |
| `siege_engine.png` | rotund body, wheels, barrel |
| `the_warden.png` | muscular body, helm |

The filenames in that table are the ids. Each ships as `<id>.player.png` and
`<id>.enemy.png`; `<id>.png` is the shared-drawing name step 3 above uses.
