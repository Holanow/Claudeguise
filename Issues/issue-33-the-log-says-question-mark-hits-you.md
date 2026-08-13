# Issue 33: the log says "? hits priest for 1 Profane damage"

> **CLOSED. Fixed and merged as `9654610`.**
>
> Verified like for like: the same party, seed and frame that had 10 of 22 log
> lines reading `? hits Priest for 1 Profane damage` now has none.
>
> pike gave sourceless damage its own sentence rather than patching the hit
> sentence, kept hazard and status ticks distinguishable because they tell the
> player different things, and used `e.status` — a signal the simulation
> already emits — instead of inventing one. Asked to fix the shape rather than
> the instance, they checked `MISS`, found it never carries a null source, and
> said so instead of changing it anyway.

**Assigned to: pike.** Small, and user-facing copy, which is why it is written up
rather than mentioned in passing.

## What it looks like

From `Tools/preview/fight_03.png`, regenerated off the current trunk. Four of the
nine visible log lines are this:

```
? hits priest for 1 Profane damage
? hits geysermancer for 1 Profane damage
```

A literal question mark, as a character's name, in the running commentary of the
fight. It is the first thing the eye lands on in that panel, and it appears
roughly every tick that anything is poisoned or standing in a hazard, so in a
fight with a cultist in it this is a large fraction of the whole log.

## Why it happens, confirmed rather than guessed

`Scripts/UI/CombatLogView.gd:80` does the right thing with what it is given:

```gdscript
var source_name := source.display_name if source != null else "?"
```

The simulation is also right. `CombatSim.gd:421` emits status damage with
`source_id = -1` **on purpose**, because a poison tick genuinely has no source —
the cultist that applied it may be dead, and attributing the damage to them
would be a worse lie than the question mark. Hazard damage a few lines later
does the same, for the same good reason.

So neither side is broken. **The formatter has one sentence shape and this event
does not fit it.** "X hits Y" needs an X, and there isn't one.

## What to do

Give sourceless damage its own sentence. The event carries `e.status` and
`e.damage_type`, so the view has everything it needs to say what actually
happened:

```
priest suffers 1 Poison damage
```

Wording is yours, and it is user-facing copy, so the house rules apply: **no
emoji, no em-dashes.** Two things worth getting right:

- **A hazard tick and a poison tick should not read identically.** They are
  different information — one means "you are standing somewhere bad and could
  move", the other means "you are afflicted and moving will not help". The
  player learns a real thing from telling them apart.
- **Check `MISS` and any other line built from `source_name`.** The same `-1`
  can reach them; the question mark just shows up most often on DAMAGE. Fix the
  shape, not only the instance. That distinction has bitten this project twice
  tonight, both times mine.

## Do this before or after issue 29, whichever suits

It touches the same file and issue 29 is the bigger job. If you are mid-way
through the layout work, fold this in. If it is easier standalone first, that is
fine too. It is small either way.

## Acceptance criteria

1. **No log line in any fight renders a `?` as a name.** A poisoned party against
   the cultist is the case that exercises it.
2. Poison and hazard damage are distinguishable from each other in the log.
3. A screenshot showing the new lines, since this is a legibility fix and the
   claim should be checkable the way you have been checking the others.

## While you are in there, ignore this if you disagree

The same screenshot shows overlapping unit labels when units bunch up — "priest"
sits on top of "geysermancer" and neither is readable. **I am flagging it, not
filing it**, because I have twice claimed a UI defect from a picture and been
wrong once, and you have the measuring tools for this and I do not. If it is
already handled by the label stagger from issue 26 and this was just a bad
moment to freeze the frame, say so and I will drop it.
