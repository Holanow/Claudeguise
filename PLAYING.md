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

**One caveat before any of this: there is a live one-line bug that makes the
game load the wrong room, and in that room nothing can lose.** It is the first
item under "what is honestly not right yet" below. The table here describes the
room the game is meant to load, which is the room all the balance work was done
against.

There are five classes and you pick four, one card each, so **there are exactly
five parties in the game.** Each is defined by who you leave out. Against
`floor1_room1`, over twenty seeds each:

| you leave out | wins | health left when it wins |
|---|---|---|
| Abomination | 19 of 20 | 23% |
| Geysermancer | 10 of 20 | 14% |
| Priest | 5 of 20 | 19% |
| Warrior | 5 of 20 | 4% |
| **Siege Master** | **0 of 20** | never wins |

1. **Leave out the Geysermancer.** A real coin flip that costs you almost
   everything when you win. This is the best fight in the game and the one to
   judge it by.
2. **Leave out the Abomination.** The strongest party, and it still loses
   somebody in 19 fights out of 20. It has never once ended with all four alive.
3. **Leave out the Siege Master**, to see what is broken. It loses every time,
   on every seed anyone has tried. One class is currently mandatory, and that is
   the biggest balance problem in the game.
4. **The same party twice on one seed**, then change one class and keep the seed.

## What is honestly not right yet

- **Read this first, because it changes what everything above is worth.** Until
  the fix lands, the game does not load the room described above. One line in
  the party select screen picks whichever room sorts first alphabetically
  instead of the room the game intends, so every fight you start is a small
  two-ghoul encounter that **no party can lose** — a thousand simulated fights,
  five parties, not a single defeat. Every fight ends in about eight seconds
  with everyone alive.

  This was found by having somebody actually play it, which is the only place it
  was visible, and it is the reason nobody should read the table above as
  describing what you will see on screen tonight. Issue 36, and it is one line.

  It also means the honest answer to "is this fun yet" is **not yet, and we do
  not know.** The engineer who played it said they would not voluntarily run a
  second fight as it stands, and also that they cannot tell whether that
  survives the fix, because nobody has watched the real room fought. That is the
  next thing that happens.
- **One class is mandatory.** The party without a Siege Master loses every
  single fight. That is the top balance problem now, and it has a diagnosis:
  see below.

  **We now know why, and it is not about range at all.** This took four wrong
  guesses to establish and the answer is the most interesting thing in the
  project. I was sure walls would deny the long shot. They do nothing. Then the
  engineers tried an ambusher spawning inside the party's own deploy zone, an
  enemy sniper matching the party's reach, and finally dialling the Siege
  Master's own range from 260 down to 150, which is shorter than the goblins'
  swing. A ranged team still won every fight at 70 to 85% health.

  The trace explains it in one line: **the room hits exactly as hard against
  every party.** It does 7.8 damage per attack against a team that walks away
  clean and 7.6 against one that nearly dies. The only difference is that it
  gets to attack 8 times instead of 61.

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
