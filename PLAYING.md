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
   It wins 19 times in 20 and finishes on 23% of its health. It has never once,
   in twenty seeds, ended a fight with all four alive, and it loses somebody in
   19 of them.
2. **Four `siege_master`.** It wins every time and takes very little back: 77%
   health, four alive in 17 of 20. **This is a known flaw, not a discovery** —
   see below — and it is worth seeing precisely because it is the one thing in
   the game that is still wrong.
3. **Four `abomination`.** A genuine coin flip, 6 wins in 20, and the wins cost
   it 91% of its health. It lost every single fight earlier tonight, because a
   Rage pawn that could not afford its finisher stood still instead of using its
   free attack, and so never landed the hits that generate Rage.
4. **Four `priest` or four `geysermancer`**, if you want to see the floor. They
   win 1 and 0 of 20. A party can be built badly and the room will say so.
5. **The same party twice on one seed**, then change one class and keep the seed.

## What is honestly not right yet

- **A party that out-ranges the room does not have to fight it.** Every enemy in
  `floor1_room1` reaches 40, 45 or 200 units; `siege_shot` reaches 260. Six of
  ten enemies never get close enough to swing at four `siege_master`. This is
  much better than it was — the room did 17 damage to that party earlier tonight
  and now takes it to 77% — but a fight nobody in the room can reach is still
  the weakest thing in the slice. Issues 24 and 31.

  **We now know why, and it is not about range at all.** This took four wrong
  guesses to establish and the answer is the most interesting thing in the
  project. I was sure walls would deny the long shot. They do nothing. Then the
  engineers tried an ambusher spawning inside the party's own deploy zone, an
  enemy sniper matching the party's reach, and finally dialling the Siege
  Master's own range from 260 down to 150, which is shorter than the goblins'
  swing. Four Siege Masters still won every fight at 70 to 85% health.

  The trace explains it in one line: **the room hits exactly as hard against
  both parties.** It does 7.8 damage per attack against the party that walks
  away clean and 7.6 against the party that nearly dies. The only difference is
  that it gets to attack 8 times instead of 61.

  A party that has to walk fights whatever is standing in its way. A party that
  does not walk picks whatever it likes, and what it likes is the archers, who
  deal the most damage in the room and have the least health in the room.
  **Killing the most dangerous thing first is free, so there is no decision to
  make.** That is the actual bug, it is being fixed as issue 35, and none of the
  range experiments could ever have touched it.
- **The floor is not a difficulty curve.** Rooms carry damage forward correctly,
  but room type does not yet pick an encounter, so difficulty changes how many
  enemies rather than which fight. Issue 27.
- **The arena is smaller than it should be.** The combat log no longer hides
  units, but it costs about a third of the screen to do it. Issue 29.
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
