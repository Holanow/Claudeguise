# Issue 32: somebody has to actually play it

> **CLOSED. Verdict delivered and merged as `c276451`.**
>
> wren watched all five parties twice: once against the wrong room, where they
> said plainly they would not run a second fight voluntarily, and again after
> the encounter fix, where they **reversed that on the record** having watched
> two real defeats and two one-survivor scrapes.
>
> **This issue found the bug that cost the entire night**: `PartySelect` loaded
> whichever encounter sorted first alphabetically, so four sessions balanced a
> room nobody played. It was visible only by playing the game. It also
> surfaced that `SampleFights` measured mono-class parties nobody can build,
> which invalidated the framing of issues 24, 31 and 35.
>
> Everything valuable here came from someone playing rather than measuring.

**Assigned to: wren.** This is not a code issue and it does not end in a merge.
It is the one requirement on this whole project that has never been met.

## Why you

The player's standing instruction, in their words: **"I should not be the first
person to playtest this game."** Every number we have comes from
`Tools/SampleFights.gd`, which runs the simulation headless and prints medians.
Not one person has watched a fight and said whether it is any good.

You are free, you wrote the simulation, and you are the person most likely to
notice when the screen disagrees with what the simulation is actually doing.
That last part is the real reason: you can tell "that looked wrong" from "that
was wrong", and nobody else on the board can do both halves.

## Run it

```
"D:\Projects\Claudeguise-team\tools\godot\Godot_v4.7.1-stable_win64.exe" --path D:\Projects\Claudeguise
```

Windowed, not headless. **Do not open the Godot editor** — every editor mode
hangs on this machine, the game itself is fine, reasoning at the top of
`Scripts/Core/CG.gd`.

Play it the way the player will, not the way an engineer debugs it. Pick a party
from the cards. Watch the whole fight. Pause when you want to. Do it several
times.

## What I want back, and what I do not

I want **your reaction**, written as prose on the board. Not a table.

- Is it fun to watch? Would you run a second fight without being told to?
- **Can you tell what is happening?** Not "is the information present" — is it
  legible while it is moving. There is a difference and only watching finds it.
- Is anything unreadable, too fast, too slow, too small, or invisible?
- Does the pause do what you want when you reach for it?
- Does a fight have a shape — a turn, a moment where it tips — or is it a flat
  line that resolves?
- **Where does it get boring?** Median fight length is 731 ticks, about 24
  seconds. Say if that is too long.

I do **not** want a bug list unless something is broken. `SampleFights` already
tells us the numbers are roughly right. This issue exists to find out whether
the thing those numbers describe is a game.

## Screenshots

Save them in `Screenshots/` so the player can see what you saw. That directory
is pike's, so **name yours `playtest_wren_*.png`** and do not touch theirs. The
player has asked that screenshots stay in the project rather than be cleaned up.

## Acceptance criteria

1. **At least four fights watched end to end**, including one you lost.
2. A written reaction on the board covering the questions above.
3. **At least one thing you would change, and one thing you would not.** The
   second is not filler: knowing what is already good stops us from polishing
   it away in the morning.
4. Screenshots of anything you describe as unclear, so the claim can be checked
   rather than taken on faith.

## Say it if it is bad

If you watch four fights and it is boring, **say it is boring.** That is the
single most valuable sentence anyone could put on this board tonight, it is the
reason this issue is assigned before any remaining polish, and nobody here gets
defensive about it. A slice that is not fun is worth knowing at 02:30 rather
than after another night of features built on top of it.

## Afterwards, if you want more

`Scripts/Floor/FloorFightRunner.gd` is yours and `_ENCOUNTER_FOR_TYPE` maps three
of the five encounters that exist. `floor1_cover` and `floor1_hazard` are built,
registered and never drawn by the floor, and MINIBOSS and BOSS both point at
`floor1_ghoul_den`, so the two most distinct rooms in the game currently only
appear if you ask for them by name. **Play first, though.** That is the issue.
