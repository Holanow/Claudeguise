# Issue 1: the fight actually happens

**Assigned to: wren.** Not "whoever picks it up". You.

There is no code host on this project, so this file is the issue. It is
versioned, which is the point: the board is a status channel and it is not
backed up.

## Outcome

Two parties are placed in a room, and over a few hundred ticks one of them
wins. Units move toward what they are trying to reach, actions wind up and land,
damage and healing apply, statuses tick down, dead units stop acting, and the
fight ends with a result. Every one of those produces a `CombatEvent`.

Nobody can see any of this yet. Issue 3 draws it. You are done when it is
correct and observable from a test.

## Files you own

- `Scripts/Combat/**` — all of it, new files welcome
- `Tests/test_combat_*.gd` — any number of them

## Files you must not touch

- `Scripts/Core/**` — frozen contract, rook's. Propose changes on the board and
  they get applied immediately; do not edit and do not work around.
- `Scripts/Content/**` and `Scripts/Plans/**` — teal's
- `Scripts/UI/**` and `Scenes/**` — pike's
- `Tests/run_tests.gd`, `Tests/TestCase.gd`, `Tests/test_skeleton.gd`,
  `Tests/test_scenes.gd`, `Tools/**`, `project.godot` — rook's
- `Tests/test_stubs_expire.gd` — rook's, with one exception: delete the
  `Scripts/Combat/CombatSim.gd` line when you implement it. That is what the
  file is for. Leave the other entries alone.

## How you work without teal's half existing

`Balance` and `PlanInterpreter` are stubs today and will be for a while. You are
not blocked by either, and you must not wait.

**Numbers.** `CombatSim.build()` is the only place that calls `Balance`. It
copies the derived values onto the `CombatUnit` and after that the simulation
reads fields. So write `build()` against the `Balance` signatures as they stand
and test everything else by constructing `CombatUnit`s directly with whatever
numbers make the case clear. Do not call `Balance` from `step()`, and do not
hardcode a tuning number anywhere in `Scripts/Combat/`. Both will be rejected in
review: teal has to be able to retune the whole game by editing one file.

**Decisions.** `CombatUnit.intent` is the seam. A tick asks the decision layer
only for units whose `intent` is null, and clears the field once it has resolved
it. Set intents by hand in your tests and you never touch teal's code.

## Tick order

This is a contract, not an implementation detail, because changing it changes
every fight and invalidates every number anyone has tuned.

1. Decide. For each unit in id order with `intent == null` and not busy, ask
   `PlanInterpreter.decide`, then `DefaultBehavior.decide` if that returns null.
   Every unit decides against the state as it was at the start of the tick.
2. Resolve, in unit id order.
3. Tick statuses, cooldowns, wind-ups and resource regeneration.
4. Check the outcome.

If you find a reason this order is wrong, say so on the board before building
around it. It is easier to change now than after tuning starts.

## Already faked, do not wire up the real thing

- No equipment generation, no loot, no shops, no floors, no procedural rooms.
  One hand-authored encounter, from `Scripts/Content/`.
- No save or load. A run exists for as long as the process does.
- No enemy plans. Enemies use `DefaultBehavior` only.

## Acceptance criteria

Each one names two cases on purpose. A criterion checked against a single case
is how work gets built exactly to spec and is wrong anyway.

1. **A fight resolves both ways.** A party that outclasses the enemies ends
   `PLAYER_WIN`; an enemy group that outclasses the party ends `ENEMY_WIN`. Both
   from `CombatSim.run`, both asserted.
2. **A stalemate ends.** Two units that cannot reach or damage each other end
   `DRAW` at `CG.MAX_TICKS` rather than running forever. Also: a fight that
   *can* resolve does so well before `MAX_TICKS`, so the cap is not quietly
   deciding your fights.
3. **The same seed gives the same fight.** Two `run`s from the same seed and the
   same units produce identical event lists: same length, same kinds, same
   ticks, same amounts. And two *different* seeds produce different ones, or the
   rng is not being consulted at all.
4. **Range is measured when the effect lands, not when the action commits.** A
   target that walks out of range during the wind-up is missed and the log says
   so. A target that stays is hit. Both asserted.
5. **Death stops everything.** A unit that dies mid-wind-up does not land its
   action, stops emitting events, and stops being a valid target. A unit at 1 hp
   still does all three.
6. **Every state change has an event.** Take a fight, replay only its
   `CombatEvent`s, and reach the same hp for every unit. If hp moved without a
   `DAMAGE` or `HEAL`, this fails. This is the criterion pike's whole screen
   rests on, so it is worth writing first.

## What would make stopping the right answer

If the fixed-tick model turns out to make movement read as jerky or the fights
unreadable at 30 ticks per second, say so and stop. Do not rescue it by adding
interpolation into the simulation. Post the finding with the tick rate you tried
and what it looked like; changing `CG.TICKS_PER_SECOND` is a one-line change to
a file rook owns and it can happen the same day.

"I built it and the fights are boring" is also a real result. Report it.

## Before you ask for review

`Tools\gate.ps1` green, `main` merged in, and the count of collected tests went
up. There is no screenshot to take for this issue; say that in the PR rather
than leaving it unmentioned.
