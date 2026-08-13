# Issue 10: the statuses you deferred, and the interrupt question

**Assigned to: wren.** After issue 11. Purely additive, entirely in your files.

## Outcome

`BURN` and `POISON` do damage over time and are visible while they do it, and
`HASTE` changes how fast a unit acts. teal can then build content that uses
them, which is impossible today: a status that does nothing produces an action
that looks broken in their file for a reason that lives in yours.

You deferred these in issue 4 and said so plainly, which is why this is an issue
rather than a surprise.

## Also decide the interrupt question

Issue 4 left `STUN` skipping the decide phase without cancelling an action
already committed, and flagged it as a separate design decision rather than
quietly choosing. Time to choose, and it is your call.

Both are defensible: a stun that cannot interrupt makes wind-ups safe once
committed, which rewards timing; a stun that interrupts makes long wind-ups
risky, which rewards cheap actions under pressure. **Write down which you picked
and why, in the code, where the next person will hit it.** Then say on the board
what you chose, because it changes what teal's stun content is worth.

## Files you own

`Scripts/Combat/**`, `Tests/test_combat_*.gd`.

**Timing matters more than usual this week.** teal is tuning against the
simulation's current behaviour for issue 7. Anything that changes damage or
action timing gets announced on the board *before* it merges, not after, or
their tuning silently becomes wrong and it will look like their error.
Damage-over-time is exactly such a change. Say so, land it, and expect teal to
re-run their table.

## Acceptance criteria

1. **A damage-over-time status damages, and stops.** A unit with `BURN` loses hp
   on the expected ticks and stops the tick after the status expires. Both
   halves asserted.
2. **It is visible in the event stream.** Every point of damage-over-time
   produces an event, so the log and the floaters can show it. A unit's hp
   moving with no event is the one thing `CombatEvent` exists to prevent — run
   issue 1's replay test, which will catch it if you get this wrong.
3. **`HASTE` speeds a unit up, measurably.** The same unit with and without it
   completes the same action in fewer ticks, numbers pasted. And a unit without
   it is unchanged from today, so the mechanism cannot be quietly applying to
   everybody.
4. **Determinism survives.** Same seed, same fight, with damage-over-time and
   haste in play. Reuse issue 1's test rather than writing a new one.
5. **The interrupt decision is documented and tested.** A test asserting the
   behaviour you chose, and a comment saying what you rejected and why.

## What would make stopping the right answer

If damage-over-time makes fights shorter and more decisive rather than more
interesting, say so with the before-and-after from `Tools/SampleFights.gd`. We
already have a landslide problem, and a mechanic that compounds damage further
would make it worse. That finding is worth more than the feature.
