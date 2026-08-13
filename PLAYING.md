# Playing the slice

Written for the morning, so the first five minutes are spent on whether you like
the game rather than on whether it works.

**Somebody other than you has played it, which is what you asked for.** An
engineer on the team watched five fights end to end, twice: once early, when
they said plainly that they would not run a second fight voluntarily, and again
after the fixes, when they reversed that and said they would. They watched two
real defeats and two fights won with one pawn left standing. Their verdict is
that it has a shape and is worth watching. Mine is not the one that counts here,
and neither is theirs really. It is yours, and the point of tonight was to get
it in front of you in a state where the answer means something.

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

**Pick a party.** Five class cards, up to four, one of each. There is a seed box:
same seed, same run, every time.

**Play a floor.** You get a map of rooms. You can see what each one is before you
walk into it, which rooms you can reach from where you stand, and what you have
found so far. A boss is never a surprise.

**Fight a room.** Real time, with pause. Party and enemy health at the top,
floating damage numbers, wind-up rings showing an action about to land, targeting
lines, and a combat log in plain language.

**Carry your losses forward.** Damage does not reset between rooms and the dead
stay dead. The floor is meant to wear you down.

**Equip what you find.** Winning a room can drop equipment. Assign it to a pawn
and it changes their numbers in the next fight.

**Meet The Warden.** Floor 1's boss. It throws a chain further than anything your
party can reach, so standing at the back is not a strategy.

**Inspect a pawn** before committing: attributes, actions, and their plans
written out as sentences.

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

- **The toolbar runs into the log** when an extra label appears, such as the
  result at the end of a fight. Being fixed.
- **The floor is not reachable from the game yet.** Rooms, a difficulty curve
  and a boss all exist and are tested, but nothing on screen leads to them. One
  fight is what you can play. That is being built now.

The two worst things in the game as of a few hours ago are both fixed, and both
are worth knowing about because of how they were found.

**The game did not load the room it was balanced for.** One line in the party
select screen picked whichever room sorted first alphabetically, so every fight
was a small two-ghoul encounter that **no party could lose** — a thousand
simulated fights across all five parties, not one defeat, every one over in about
eight seconds. Four sessions spent a night balancing a room nobody was playing.
It was found by having somebody actually play the game, which is the only place
it was visible, and the fix was one line.

**The log called everybody "?".** Anything poisoned or standing in fire has no
attacker to name, and the log had only one sentence shape, so it printed a
question mark. At the climax of a fight, ten of twenty-two visible lines could
read `? hits Siege Master for 1 Profane damage`. Two people found it
independently and both said the same thing: it drowned the log exactly at the
deaths and defeats where you most want to read it. Sourceless damage has its own
sentence now.
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
- **Portrait phone layout is cramped.** Landscape is the target and is fine.
- **No plan editor, no shops, no second floor.** All deliberate and listed in
  `Issues/NEXT-after-the-slice.md`, which is now open and being worked on rather
  than gated shut.
- **Loot exists but you cannot collect it.** Winning a room rolls a real drop
  against a real table and puts it in the run's satchel. Nothing shows it to you
  and nothing lets you equip it, because the run itself has no screen yet. Same
  root cause as the item above: the floor is built and unreachable.

Fixed since the last time this file described them: the combat log moved beside
the arena instead of below it, roughly doubling the play area; room type now
picks a real encounter, so the floor has a measured difficulty curve rather than
just more enemies; and thirteen items exist with real numbers and descriptions,
though nothing equips them yet.

## The art is a placeholder and swapping it is one step

Drop a PNG into `Assets/Units/` named after the unit — `warrior.png`,
`goblin.png`. No code change, no import, no registration. Delete it and the
polygon comes back. `Assets/Units/README.md` has the full list, and a test keeps
that list honest against the real content.

**Checked rather than assumed**, because it is a promise made to you: a plain
magenta square was saved as `priest.png` and `ghoul.png` and a real fight
rendered with it. The Priest and both Ghouls became magenta squares and every
other unit kept its polygon. `Tools/preview/art_swap_proof.png` is that frame.

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
