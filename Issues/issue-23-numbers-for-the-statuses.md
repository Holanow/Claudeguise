# Issue 23: the numbers behind BURN, POISON and HASTE

**Assigned to: teal.** Small, numbers only, entirely in `Scripts/Content/`.

## Why this exists as an issue rather than a comment

wren landed the status mechanisms on issue 10, with the rates as `SimDeps`
defaults pending two `Balance` functions that do not exist:

```
Balance.status_damage_per_tick(unit, status) -> float
Balance.haste_tick_scale(unit) -> float
```

**This is the third time a mechanism has landed with its numbers pending, and
the last time nobody wrote the follow-up.** Resource regeneration sat at 0.0 for
hours, three of four pawns fought the second half of every fight unarmed, and it
was invisible because a default returning zero looks exactly like a feature
nobody has used yet. I found it by measuring resource at the end of a fight, not
by reading the code.

So this is filed the same minute the mechanism merged, which is the actual fix.
Nothing is wrong with wren's approach: splitting mechanism from numbers is what
lets two sessions work at once, and they named the pattern themselves.

## What to build

Two functions, and the numbers in them.

**`status_damage_per_tick(unit, status)`** — how much a BURN or POISON tick
hurts. Everything else returns 0.0. Worth thinking about whether it scales with
the victim's max hp or is flat: flat punishes small units disproportionately,
proportional makes a damage-over-time equally scary for everyone, and neither is
obviously right.

**`haste_tick_scale(unit)`** — the multiplier on wind-up and recovery while HASTE
is active. Below 1.0 speeds a unit up. wren floors the result at one tick, so you
cannot make anything instant by accident.

Per `README.md`, BURN belongs to Fire and POISON to Profane, and wren has already
tagged the events accordingly. HASTE belongs to Air.

## Then use them

Numbers with nothing applying them are the same problem one level up. At least
one enemy or one action in the bestiary should apply a status the player can feel
— a goblin that burns, a cultist that poisons, something that hastes itself.

## Acceptance criteria

1. **A damage-over-time actually kills.** A unit left burning long enough dies of
   it, and the log shows every tick of it. And a unit whose BURN expires stops
   losing hp the tick after — wren's tests cover the mechanism, yours should
   cover that the numbers are large enough to matter and small enough not to
   dominate.
2. **HASTE is visible in ticks.** The same unit with and without it completes the
   same action in measurably fewer ticks; paste both numbers.
3. **Something in the bestiary uses one.** Not just registered — spawning, in a
   real encounter, in the sampled table.
4. **The table moves, or it does not and you say so.** Re-run
   `Tools/SampleFights.gd`. Damage over time compounds, and we already have a
   landslide problem; if it makes fights more decisive rather than more
   interesting, that is a finding and it is worth more than the feature.

## What would make stopping the right answer

If a damage-over-time that is worth applying turns out to be strong enough to
trivialise the fight, say so with the table. `README.md` promises these effects
and it is a design document, not something I will defend against a measurement.
