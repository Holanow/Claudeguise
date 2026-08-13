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

There are five classes and you pick four, one card each, so **there are exactly
five parties in the game.** Each is defined by who you leave out. Against
`floor1_room1`, over twenty seeds each:

| you leave out | wins | health left when it wins |
|---|---|---|
| Abomination | 19 of 20 | 23% |
| Warrior | 12 of 20 | 23% |
| Geysermancer | 11 of 20 | 23% |
| Priest | 11 of 20 | 16% |
| **Siege Master** | **1 of 20** | 32% |

1. **Leave out the Warrior, the Geysermancer, or the Priest.** All three are
   near coin flips that cost you most of the party when you win. These are the
   best fights in the game and the ones to judge it by.
2. **Leave out the Abomination.** The strongest party, and it still loses
   somebody in 19 fights out of 20. It has never once ended with all four alive.
3. **Leave out the Siege Master**, to see what is still broken. It wins once in
   twenty. One class is close to mandatory, and that is the biggest balance
   problem left.
4. **The same party twice on one seed**, then change one class and keep the seed.

## What is honestly not right yet

- **Nobody has yet watched the real game and said whether it is fun.** That is
  the honest headline and it is deliberate.

  For most of last night the game did not load the room it was balanced for. One
  line in the party select screen picked whichever room sorted first
  alphabetically, so every fight was a small two-ghoul encounter that **no party
  could lose**: a thousand simulated fights across all five parties, not a
  single defeat, every one over in about eight seconds. It was found by having
  somebody actually play the game, which is the only place it was visible.

  It is fixed and verified through the real party select screen: five fights,
  four defeats and one win with a single survivor, running 14 to 22 seconds. The
  game has stakes now.

  But the engineer who played the broken version said they would not voluntarily
  run a second fight, and said they could not tell whether that verdict survives
  the fix, because nobody had seen the real room fought. **They are replaying it
  now.** Until that comes back, nobody should tell you this slice is good, and I
  am not going to.
- **One class is close to mandatory.** The party without a Siege Master wins
  once in twenty. That is much better than the zero it was earlier tonight, and
  it is still the top balance problem. It has a diagnosis, below.

  The Abomination half of it is fixed and the fix is worth reading, because it
  was not a strength problem. Traced, that class was getting **5 actions in a
  whole fight against the Siege Master's 22**, because it spent most of every
  fight crawling five hundred units to reach a melee kit. It was not losing
  fights, it was barely attending them. Giving it the speed to arrive turned
  three of the five parties into coin flips.

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
