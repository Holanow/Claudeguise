# Issue 16: units walk out of the arena and never come back

**Assigned to: wren. This is the most valuable fix available right now** and I
would take it ahead of issues 10, 11 and 13a.

## What happens

Nothing clamps a unit's position to the arena. `CombatSim._resolve_move` moves a
unit toward its destination and no code anywhere compares that position to
`CG.ARENA_HALF_WIDTH` or `CG.ARENA_HALF_HEIGHT`.

Measured on the trunk, seed `0000002A`, the four-class party, after a full
fight:

```
arena half-extent: 480 x 270
outcome DRAW after 3600 ticks (the cap)

  abomination    alive  pos=( 10107.4, -2464.8)   *** OUTSIDE THE ARENA ***
  Archer         alive  pos=(  7889.1, -1940.2)   *** OUTSIDE THE ARENA ***
  Cultist        alive  pos=( 10151.6, -2475.2)   *** OUTSIDE THE ARENA ***
  (the five dead units are all inside, near the origin)
```

The survivors are twenty-one arena widths off the map. They spent a hundred
seconds running into the void.

## Why it happens, and why it matters more than it looks

`DefaultBehavior` kites: a ranged unit closer than a fraction of its range backs
off by a fixed step. A melee unit chases. If the ranged unit is faster, or the
chase is diagonal, the pair drifts, and there is no edge to stop them. Nothing
resolves, and the fight ends at `CG.MAX_TICKS` as a draw.

Three consequences, and the third is the one I care about:

1. **Stalemate draws.** The default four-class party now draws 20 of 20 at the
   cap. A 120-second nothing is worse than a loss.
2. **The arena pike draws is decorative.** A player watches units leave the
   boundary and keep going. The most basic promise the screen makes is false.
3. **A kiter that cannot be cornered is unbeatable, and a cornered one has to
   fight.** This is the whole reason walls make fights interesting, and we have
   been trying to tune closeness on a battlefield with no edges. **I think this
   is a large part of why no fight is ever close**, alongside focus fire.

That last one makes this a gameplay fix rather than a bounds check.

## Files you own

`Scripts/Combat/**`, `Tests/test_combat_*.gd`.

Clamp in the simulation, not in the view: the view drawing a unit at the edge
while the simulation thinks it is elsewhere would be worse than the bug.

Coordinate with `Scripts/Core/Terrain.gd` while you are here — issue 13a asks you
to make walls block movement, and the arena boundary is the same problem with a
simpler shape. Doing them together is sensible and I would rather you did than
wrote the clamp twice.

## Acceptance criteria

Two cases each.

1. **Nobody leaves.** After a full fight, every unit's position is inside the
   arena, on every seed you sample. And a unit told to walk to a point outside
   the arena ends up on the boundary rather than refusing to move at all.
2. **A cornered kiter fights.** A ranged unit backed into a corner by a melee
   unit stops retreating and acts. And an uncornered one still kites normally,
   so the fix has not simply disabled kiting.
3. **The stalemate is gone.** The four-class party on seed `0000002A` reaches a
   real outcome well before `CG.MAX_TICKS`. Paste the tick count. And a fight
   that genuinely cannot resolve — two units that cannot damage each other —
   still draws at the cap, so the safety net still works.
4. **Determinism survives.** Same seed, same fight. Reuse issue 1's test.

## Announce before merging

This changes every fight outcome, and teal is mid-tuning on issue 7. Say on the
board before it lands, not after, and expect teal to re-run their table. Given
what it does, I expect their numbers to change a lot and mostly for the better.

## What would make stopping the right answer

If clamping turns fights into units pinned in corners unable to act, say so with
the sample table. That would point at `DefaultBehavior`'s retreat rule needing
to understand the boundary, which is teal's file, and it would be a better
finding than a clamp that technically holds.
