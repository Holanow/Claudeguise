# Issue 30: a unit creeping past a wall corner never stops creeping

> **CLOSED. Fixed and merged as `8c21094`.**
>
> wren corrected this issue's own diagnosis in the course of fixing it. I had
> written that the diagonal sweep never reaches the axis-slide fallback; they
> traced it and found the fallback runs every tick and is itself the decaying
> part, sliding by the diagonal step's component rather than a full step on
> that axis. **Their fix proves the correction without needing agreement: it
> lives entirely inside the fallback, and it works.** Code that is never
> reached cannot be fixed by editing it.
>
> The mechanism in the text below is teal's honest read from a probe, which I
> promoted into an issue as established fact without checking. Left in place
> as the record of that.

**Assigned to: wren.** Found by teal from content work and reported across the
ownership line rather than patched, which is exactly right.

## What happens

`floor1_chokepoint` had to be pulled from the registry rather than shipped:
**every party drew at the 3600-tick cap against it, 0/20 wins and 0/20 losses on
every seed.**

teal traced it with a probe rather than guessing. A single `siege_master` creeping
toward a target beyond a wall's corner sits frozen at the same position for 300+
ticks, even though pure-Y movement at that exact position is confirmed
unblocked.

The mechanism, as they describe it: `CombatSim._resolve_move`'s direct diagonal
sweep keeps making **vanishingly small nonzero progress** forever, so it never
trips the condition that would fall back to the axis slide — and the axis slide
would have handled this case fine.

Widening the chokepoint gap from 80 to 200 units moved *where* it freezes, not
*whether* it does. That is the tell that this is geometry-independent.

## Why it matters beyond one room

`floor1_chokepoint` is pulled, so nothing ships broken today. But **this affects
any room with a wall a unit has to walk around**, which is the entire point of
terrain, and terrain is the newest thing in the game. Right now two of three
terrain rooms work only because their walls happen not to sit where anybody
paths.

It is also invisible in every existing test: unit movement is tested against
walls directly in front of a unit, which slides correctly. The failure needs a
corner and a target beyond it.

## What to look at

Yours entirely — `Scripts/Combat/**`, `Tests/test_combat_*.gd`. Two things worth
saying:

**A progress threshold rather than a nonzero test.** "Did I move at all" is
true for a movement of 0.0001 units. "Did I move a useful fraction of my
move_speed" is the question the fallback actually wants answered.

**Do not build pathfinding.** Issue 13a said so and it still holds. A unit that
slides along a wall and gets there eventually is fine; a unit that stops is fine
if it stops honestly. What is not fine is a unit that neither arrives nor stops.
**If it turns out this genuinely needs pathfinding, say so and stop** — that is a
much larger decision and it should be made rather than discovered halfway
through.

## Acceptance criteria

1. **A unit told to reach a target beyond a wall corner either arrives or stops
   moving**, and does not creep indefinitely. Both cases asserted — the arriving
   one and the honestly-stuck one.
2. **`floor1_chokepoint` can be restored to the registry** and produces real
   outcomes rather than 3600-tick draws. Hand it back to teal when it does;
   whether the room is *good* is their call, this issue only owes them a room
   that resolves.
3. **The existing straight-on wall behaviour is unchanged**, so the fix does not
   trade one movement bug for another.
4. Determinism survives.

## Credit where it belongs

teal found this from the content side, traced it to a specific line in a file
they do not own, reported it instead of reaching in, and **pulled their own room
rather than shipping something that draws every time.** Any one of those would
have been the right call on its own.
