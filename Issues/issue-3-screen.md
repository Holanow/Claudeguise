# Issue 3: watch the fight, read why it went that way, run it again

**Assigned to: pike.** Not "whoever picks it up". You.

## Outcome

Someone launches the game, picks a party, watches a fight, and can say what
happened and why. Then they change the party, keep the seed, and run it again to
compare.

That sentence is the whole project this week. The simulation and the content
exist to be judged, and this is the only thing that lets anyone judge them.

## Files you own

- `Scripts/UI/**`
- `Scenes/**`
- `Tests/test_ui_*.gd`
- `Screenshots/**` — new directory, commit them, they do not get cleaned up

## Files you must not touch

- `Scripts/Core/**` — frozen contract, rook's
- `Scripts/Combat/**` — wren's
- `Scripts/Content/**` and `Scripts/Plans/**` — teal's
- `Tests/run_tests.gd`, `Tests/TestCase.gd`, `Tests/test_skeleton.gd`,
  `Tests/test_scenes.gd`, `Tools/**`, `project.godot` — rook's.
  `test_scenes.gd` asserts each scene's root keeps its script; if you add a
  scene, ask rook to add it there rather than editing it.
- `Tests/test_stubs_expire.gd` — delete your five lines as you implement them,
  and nothing else.

## Screens

**Party select.** Generate one pawn per class from `Registry.all_class_ids()`,
let the player pick up to four, show the seed and let them type one in, start
the fight. It is not a placeholder: swapping the party between runs is an
acceptance criterion for the slice, and a screen that always hands over the same
party makes the comparison impossible.

**Battle.** The arena, the units, the damage numbers, the combat log, and a
restart. `CG.ARENA_HALF_WIDTH` and `ARENA_HALF_HEIGHT` are world units centred
on the origin; scale them to the viewport however reads best.

## Rules that are not negotiable

**Read `CombatEvent`, never poll state.** Floating numbers and log lines come
from the event stream via `events_since`, using your own cursor. Watching
`unit.hp` change each frame gives you a number with no cause attached, and "that
felt bad" then cannot be traced to anything. Positions and bars may read
`CombatUnit` directly; anything that *happened* comes from an event.

**Step whole ticks.** The view owns the clock and calls `CombatSim.step` an
integer number of times per frame. Never scale a tick by `delta`, never
interpolate anything back into the simulation. Interpolating a sprite's drawn
position between two ticks is fine and encouraged; it must not feed back.

**Show the wind-up.** `ActionDef.wind_up_ticks` exists so a fight can be read
rather than merely watched. A screen that does not show an action coming makes
every hit look random. `Palette.WIND_UP` is there for it.

**Every colour comes from `Palette`.** No literals.

## Working before the other two land

`CombatSim` and the content are stubs today. Do not wait for them: build against
a `CombatState` you construct by hand in a test scene, with a handful of
`CombatUnit`s and a synthetic event list. That also gives you the fixture for
your tests. When issue 1 lands, swap the source and the screen should not care —
if it does, you reached past `CombatEvent` somewhere.

## Acceptance criteria

Two cases each, on purpose.

1. **The same seed reruns identically.** Run a fight, note the outcome and its
   length in ticks, restart with the same seed and party, and get the same two
   numbers. Then change one pawn, keep the seed, and get different ones. Paste
   all four.
2. **The party can be swapped and it shows.** Two runs on one seed with
   different parties produce visibly different fights, and the screen names the
   party it is actually running. A screen that quietly runs a stale party is the
   failure this catches.
3. **Damage numbers match the log which matches the events.** Pick one hit. The
   floater, the log line and the `CombatEvent.amount` all show the same number.
   Then pick a mitigated hit and confirm the log shows the mitigation rather than
   only the final number.
4. **A death is legible.** When a unit dies the screen says which one and the log
   records it. When a unit survives at low hp, it is visibly at low hp and no
   death is logged.
5. **Nothing renders off-screen.** A unit at each of the four arena corners is
   fully visible at 1280x720 and at a resized window. Screenshot both.
6. **It launches.** `godot --path . ` from a clean checkout reaches party select
   with no error in the output, and reaches battle with no error. Both, because
   a screen that boots and then breaks on transition passes the first half.

## Screenshots

Take them after your last commit, not before, and save them in `Screenshots/`.
A screenshot of an earlier state is worse than none: a reviewer will trust it.
At minimum: party select, a fight mid-wind-up, and the moment after a death with
the log visible.

## What would make stopping the right answer

If the fights turn out to be unreadable at 30 ticks per second no matter how you
draw them, say so with a screenshot and stop. That is a finding about the tick
rate, which is rook's one-line change, not something to paper over with
animation.

## Before you ask for review

`Tools\gate.ps1` green, `main` merged in, collected test count up, screenshots
committed, and you have played it yourself through the controls a player uses —
not by calling the functions underneath.
