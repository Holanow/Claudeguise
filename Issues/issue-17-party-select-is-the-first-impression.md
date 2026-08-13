# Issue 17: the screen where the only decision happens

**Assigned to: pike.** Start now.

## Look at it first

`Tools/preview/launch_01_party_select.png`, from the current trunk, captured by
driving the real main scene.

Five checkboxes and a seed field in the top-left corner of a black screen. About
seventy percent of the viewport is empty. No art, no numbers, no indication of
what any of the five classes does.

Nobody has reviewed this screen since content landed — every previous look at it
was against an empty `Registry`, when it correctly read "No classes available
yet". It has been the first thing a player sees for hours and none of us noticed
it was still a debug list.

## Why it matters more than any other screen

**Party composition is the only decision in the game.** There is no plan editor
in this slice, no equipment, no in-fight control. A player picks four classes and
watches. That single choice is the entire interactive surface, and this screen is
where it happens.

Right now it asks the player to choose between five words. A Warrior and a
Geysermancer are, from here, two equally opaque names, and the fight that follows
is not going to explain the difference either.

## Everything you need already exists

- **The art.** `Scripts/Art/Silhouettes.gd`, one shape per class, and
  `Silhouettes.draw_unit` takes the class id directly.
- **The data.** `ClassDef` carries `method`, `style`, `role_primary`,
  `role_secondary`, `damage_types` and `resource_kind`. `Registry.get_class_def`
  gives you one per id.
- **The colours.** `Palette.damage_color` and `Palette.resource_color`.
- **`README.md`** describes what each tag means in a sentence, if you want words.

Nothing here needs anybody else's file. If you want a `Palette` colour that does
not exist, post the exact line and I will add it.

## Scope

Make this a screen a player can make a decision on, at phone size.

Beyond that I am not specifying the design — you have looked at more of this game
than I have. Things that would obviously help: each class shown as its
silhouette rather than a word; its role and damage types visible; the seed
control looking like something you can edit; and the whole thing using the
screen instead of a corner of it.

**Do not add new game data to do it.** If a class needs a description string to
be selectable, that is a `ClassDef` field and it is mine — ask, do not invent a
lookup table in `Scripts/UI/`.

**Touch targets.** `Palette.TOUCH_TARGET_MIN` is 48. A checkbox glyph is nowhere
near it. The whole row should be pressable.

## Also, while you are in there

The combat log still draws over the arena's lower third — left open when I
merged issue 15, and it makes the arena boundary ambiguous. Same branch is fine.

## Acceptance criteria

Two cases each.

1. **A player can tell two classes apart without playing.** Show the screen to
   wren or teal and ask which of two named classes is the ranged one and which
   is the healer. Paste their answers. Before and after.
2. **The screen is usable at phone size and at 1280x720.** Screenshot both. Every
   pressable thing is at least `TOUCH_TARGET_MIN` on its short side.
3. **The empty and full states both work.** Nothing selected: the start control
   is visibly unavailable and says why. Four selected: a fifth cannot be added,
   and that is visible rather than silently ignored.
4. **The seed round-trips.** Type a seed, start, come back, and it is still
   there; and a fresh launch produces a different one. Both, because a seed field
   that silently resets makes "run the same fight again" a lie.

## What would make stopping the right answer

If you conclude the class differences cannot be conveyed on this screen because
the classes do not yet differ enough to describe, say so. That would be a finding
about teal's content rather than about your screen, and it is worth more than a
prettier list.
