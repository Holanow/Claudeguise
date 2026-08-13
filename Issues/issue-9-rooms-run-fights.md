# Issue 9: the floor actually runs its fights

**Assigned to: wren.** Start it on top of `issue-5/first-floor-structure`
rather than waiting for me.

## Outcome

A room in a `FloorPlan` can be played: entering an enemy room builds a
`CombatState` from that room and the party's current condition, runs it, and
writes the result back to the `FloorRun` so the next room starts from it.

Issue 5 built the graph and the party state. This connects it to `CombatSim`.
Still headless, still no screen.

## Files you own

`Scripts/Floor/**`, `Tests/test_floor_*.gd`.

**Not `Scripts/Combat/**` unless you need to change it** — you own that too, but
teal is tuning against its current behaviour for issue 7, so anything that
changes fight outcomes gets announced on the board before it merges rather than
after. Additive is fine; changing damage or timing is not, this week.

**Not `Scripts/Content/**`.** A room says what kind of room it is and how hard
it is; teal decides which enemies that means. Where the two meet is a lookup you
call, not a table you write.

## Acceptance criteria

1. **A room's outcome carries forward.** A party that finishes room 1 at reduced
   hp enters room 2 at that hp; a party that finishes untouched enters at full.
   Both asserted.
2. **A wipe ends the run.** Losing a room ends the run rather than advancing;
   winning the last room ends it the other way. Both.
3. **The same seed plays the same floor the same way.** Two runs of one seed,
   same rooms in the same order with the same outcomes. And two different seeds
   differ — note that this criterion depends on teal's issue 7 landing damage
   variance, so if it still holds trivially, say so rather than asserting a
   sameness that is really an absence.
4. **Difficulty means something.** Across twenty seeds, later rooms are harder by
   some measure you name and paste. And the first room is winnable by a starting
   party in the large majority of them, because a floor whose first room kills
   you is not a difficulty curve.

## What would make stopping the right answer

If it turns out a room cannot be made harder without content teal owns, say so
and stop at criterion 3. Half of this issue landing with the reason written down
is better than a difficulty knob invented in the wrong file.
