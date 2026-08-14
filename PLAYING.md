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
floating damage numbers, a progress bar above each unit with the icon of the
action it is about to land, targeting lines, and a combat log in plain language.

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
five parties.** Each is defined by who you leave out. Over twenty generated
floors each:

| you leave out | clears the floor | one room, wins | health left on a win |
|---|---|---|---|
| Abomination | 20 of 20 | 19 of 20 | 23% |
| Geysermancer | 20 of 20 | 11 of 20 | 23% |
| Priest | 20 of 20 | 11 of 20 | 16% |
| Warrior | not measured | 12 of 20 | 23% |
| **Siege Master** | **5 of 20** | 1 of 20 | 32% |

1. **Leave out the Geysermancer or the Priest.** Near coin flips room to room
   that still clear a floor. These are the best fights and the ones to judge it
   by.
2. **Leave out the Abomination.** The strongest party, and it still loses
   somebody in 19 fights out of 20.
3. **Leave out the Siege Master** to see what is still broken. One class is
   close to mandatory.
4. **The same seed twice**, then change one class and keep the seed. Same floor,
   same rooms, same fights.

## What is honestly not right yet

- **One class is close to mandatory.** The party without a Siege Master clears
  the floor 5 times in 20, where the other three clear it every time. It is the
  biggest balance problem left and the diagnosis is below.
- **Recovery between rooms is written but not connected.** The numbers exist and
  nothing calls them yet, so the floor currently wears you down with nothing
  given back. It gets easier when that lands.
- **Portrait phone layout is cramped.** Landscape is the target and is fine.
- **No plan editor, no shops, no second floor.**

### Why one class is mandatory, which took four wrong guesses

I was sure walls would deny a long-ranged party its shot. They do nothing. The
engineers then tried an ambusher spawning inside the party's own deploy zone, an
enemy sniper matching the party's reach, and finally dialling the Siege Master's
own range from 260 down to 150 — shorter than a goblin's swing. A ranged team
still won every fight at 70 to 85% health.

The trace explains it in one line: **the room hits exactly as hard against every
party.** 7.8 damage per attack against a team that walks away clean, 7.6 against
one that nearly dies. The only difference is that it gets to attack 8 times
instead of 61.

A party that has to walk fights whatever is in its way. A party that does not
walk picks whatever it likes, and what it likes is the archers, who deal the most
damage in the room and have the least health. **Killing the most dangerous thing
first is free, so there is no decision to make.**

### The two worst bugs, and how they were found

**The game did not load the room it was balanced for.** One line in party select
picked whichever room sorted first alphabetically, so every fight was a
two-ghoul encounter **no party could lose** — a thousand simulated fights, not
one defeat. Four sessions spent a night balancing a room nobody was playing. It
was visible only by playing the game, and the fix was one line.

**The log called everybody "?".** Anything poisoned or standing in fire has no
attacker to name, and the log had one sentence shape, so it printed a question
mark. At the climax of a fight, ten of twenty-two lines could read
`? hits Siege Master for 1 Profane damage`. Two people found it independently and
both said it drowned the log exactly where you most want to read it.

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
