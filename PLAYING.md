# Playing the slice

Written for the morning, so the first five minutes are spent on whether you like
the game rather than on whether it works.

## Run it

```
"D:\Projects\Claudeguise-team\tools\godot\Godot_v4.7.1-stable_win64.exe" --path D:\Projects\Claudeguise
```

That is the standalone Godot fetched from the GitHub release, kept outside the
repo. **Do not open the project in the Godot editor** — every headless editor
mode hangs on this machine and the windowed one does too, on both this build and
the Steam copy. The game itself runs fine; it is only the editor that will not
start. The reasoning is at the top of `Scripts/Core/CG.gd`.

## What you can do

**Pick your party.** Five class cards, each showing its silhouette, role and
damage types. Up to four. There is a seed box — type the same seed twice and you
get the same fight, which is how you compare one party against another.

**Inspect a pawn** before committing. Its attributes, its actions, and its plans
written out as sentences: *"1. Immolate — when an enemy within 45 units: the
nearest enemy, then use Immolate."* That screen exists because you asked to see
what pawns will do, and it is also the reason we found two real bugs.

**Watch the fight.** Real time, with pause. Party and enemy health summarised at
the top, floating damage numbers, wind-up rings showing an action about to land,
targeting lines, and a combat log. Restart with the same seed, or change party.

## What to try first

1. **`siege_master`, `geysermancer`, `priest`, `warrior`.** The balanced party.
   It wins about 17 times in 20 and finishes on roughly a quarter of its health.
   It has never once, in twenty seeds, ended a fight with all four alive.
2. **Four `siege_master`.** It wins every time and barely gets touched. **This is
   a known flaw, not a discovery** — see below — and it is worth seeing precisely
   because it is the one thing in the game that is still wrong.
3. **Four `abomination`.** A coin flip. This morning it lost every single fight,
   because a Rage pawn that could not afford its finisher stood still instead of
   using its free attack, and so never landed the hits that generate Rage.
4. **The same party twice on one seed**, then change one class and keep the seed.

## What is honestly not right yet

- **Four `siege_master` wins for free.** Every enemy in the room reaches 40, 45
  or 200 units; `siege_shot` reaches 260. Six of ten enemies never get close
  enough to swing. Total enemy damage in that fight: 17, against 114 hp per pawn.
  A party that out-ranges the whole room is not fighting it. Issue 24.
- **The floor is not a difficulty curve.** Rooms carry damage forward correctly,
  but every room draws the same encounter, so difficulty only changes how many
  enemies rather than which fight. Issue 27, in progress.
- **The combat log can hide units** fighting in the bottom third of the arena.
  pike is on it right now.
- **Portrait phone layout is cramped.** Landscape is the target and is fine.
- **No plan editor, no items, no loot, no shops, no floors beyond room one.**
  All deliberate, all listed in `Issues/NEXT-after-the-slice.md`, all gated shut
  until the slice is good.

## The art is a placeholder and swapping it is one step

Drop a PNG into `Assets/Units/` named after the unit — `warrior.png`,
`goblin.png`. No code change, no import, no registration. Delete it and the
polygon comes back. `Assets/Units/README.md` has the full list, and a test keeps
that list honest against the real content.

## If you want the numbers rather than the game

```
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://Tools/SampleFights.gd
```

Every encounter, every party, twenty seeds each: win rate, tick spread, survivor
histogram, and what the win cost the party as a percentage of its own health.
That last column is the one you asked for, and it is what the balance was
finally steered by.

`Tools/preview/fight_sheet.png` is six frames of one real fight, regenerated
after every merge.
