# Issue 34: a unit will shoot a wall for two minutes

**Assigned to: teal.** This restores work of yours that I approved the removal
of. The judgement was mine and it was wrong.

## The measurement

`floor1_room1`'s exact roster, with `floor1_chokepoint`'s wall dropped in and
nothing else changed, `siege_master x4`, seed 0, run to the 3600-tick cap:

```
ACTION_FIRE = 438     MISS = 414     DAMAGE = 24
```

**94% of every shot fired in that fight missed.** All four siege_masters ended
at x between -170 and -186, which is the party deploy zone: **they never moved
at all.** Five enemies finished at full health sitting at y = +/-222, on the far
side of the wall segments.

So the fight is four units standing still, firing into a wall, missing, for two
minutes, until the tick cap calls it a draw. Twenty seeds, twenty draws. The
balanced party draws 3 of 20 the same way.

## Why, and why it is my fault rather than yours

You built two things in 13b and I treated them as one. `PlanInterpreter`'s
`_target_in_los` refused to *order* a shot at a target the unit cannot see, and
`DefaultBehavior` walked toward it instead. Then issue 28a's
`ActionDef.requires_line_of_sight` landed, checked when the effect resolves, and
you judged it the better mechanism because it catches a target stepping behind
cover *mid-wind-up* — which a decide-time check genuinely cannot. You removed
your own version rather than run both, and I merged that and praised the call in
the commit message.

**They are not two versions of one mechanism. They answer different questions.**

- Decide-time: *should I aim at this?* If the answer is no, walk. Without it a
  unit has no reason to ever move, because its target is in range.
- Resolve-time: *did the shot I already committed to actually connect?* Without
  it, cover cannot be used defensively at all.

Removing the first leaves a unit with a target it can neither hit nor be
persuaded to approach. That is this issue. Restore `_target_in_los` and
`DefaultBehavior`'s approach branch, and **keep the flag**. Both.

Your original instinct was right and my read of it was the error. I want that on
the record because you deleted working code on my say-so.

## Acceptance criteria

1. **`floor1_room1`'s roster behind `floor1_chokepoint`'s wall resolves** rather
   than drawing, for `siege_master x4` and for the balanced party.
   `Tools/TerrainAB.gd` runs exactly this, three parties against three terrain
   arms, and is the fastest way to check yourself.
2. **The miss rate in that fight comes down to something a player would read as
   a fight** rather than 94%. I am deliberately not naming a number: a shot
   blocked mid-wind-up *should* still miss sometimes, and that is the flag doing
   its job.
3. **A target that steps behind cover during a wind-up still causes a miss**, so
   restoring the decide-time check does not undo 28a. This is the one that
   would be easy to lose, and it is the reason you preferred the flag.
4. `floor1_chokepoint` can go back in the registry, or you say plainly why not.

## What this does not change

Issue 31 still stands and is still the more important one. Pillars on
`floor1_room1`'s roster produced a result **identical to no terrain at all** for
`siege_master x4` — 20/20, 77%, the same 341-tick median — so terrain is not the
answer to the untouchable back line either way. Do not let this issue eat that
one. This is a correctness bug; issue 31 is the game.
