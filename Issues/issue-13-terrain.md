# Issue 13: rooms with walls in them

**Three parts, one per session. Take only your own.** They are separate branches
and they merge in the order 13a, 13b, 13c. Nobody blocks on anybody: the shape
is already frozen on the trunk, so all three can start now.

The shape is `Scripts/Core/Terrain.gd`, mine, already merged and tested. Read it
first. It gives you `Feature` (a kind and a `Rect2`), `blocks_movement()`,
`blocks_sight()`, `line_is_blocked()`, `point_is_blocked()` and `hazards_at()`.
The geometry is written once, there, because line-of-sight is the classic
function that is subtly wrong for a year and I would rather it be wrong in one
place than three.

## Why this exists

Every fight so far has been two clusters walking into each other across an empty
rectangle, and no fight has ever been close: winners lose nobody, losers lose
everybody. teal is tuning numbers against that. Terrain is the other half, and
probably the larger one — a wall means a ranged unit can be denied its shot, a
chokepoint means four attackers cannot all reach one target, a hazard means the
shortest path is not the right one.

**Balance decides which side of a landslide you are on. Terrain decides whether
the fight is a landslide.** If it works, it will show up in
`Tools/SampleFights.gd` as wins with survivors between 1 and 3.

---

## 13a — the simulation respects walls · **wren**

**Files:** `Scripts/Combat/**`, `Tests/test_combat_*.gd`.

`CombatState` gains a terrain list — ask me for the exact line and I will add it
to Core, do not add it yourself. Then:

- A unit's movement is stopped by `WALL` and `PIT`, using `point_is_blocked`
  with the unit's own radius.
- A unit standing in a `HAZARD` takes its `damage_per_tick`, with an event, so
  the log and the floaters can see it.
- Line of sight is *available* to the decision layer but not enforced by you.
  Whether an action requires it is teal's call per action, not a blanket rule.

**Do not build pathfinding.** A unit that walks into a wall should slide along
it or stop, and that is enough for a room with a few rectangles in it. If you
find yourself writing A*, stop and say so: that is a much larger issue and it
should be decided rather than discovered.

**Announce before merging.** This changes fight outcomes while teal is
mid-tuning.

### Acceptance criteria
1. A unit told to walk through a wall does not end up on the other side, and a
   unit told to walk through empty space arrives. Both.
2. A unit in a hazard loses hp with an event per tick, and stops the tick after
   it leaves. Both.
3. A unit walking into a wall does not freeze permanently — it still reaches a
   target that is reachable around the obstacle within a reasonable time, or you
   report plainly that it cannot and that pathfinding is needed. **"I tried and
   units get stuck on corners" is a result, not a failure.**
4. Determinism survives. Same seed, same fight, with walls in play.

---

## 13b — rooms are shaped · **teal**

**Files:** `Scripts/Content/**`, `Tests/test_content_*.gd`.

Encounters gain terrain. Fold this into issue 7 and issue 12 rather than running
a third branch: it is the same tuning pass and the same files.

At least three distinct room shapes, and they should be *different fights*, not
one room with decoration:

- something with a chokepoint, where numbers matter less than they should
- something with cover, where a ranged line is broken
- something with a hazard worth walking around

### Acceptance criteria
1. Two rooms with the same enemies but different terrain produce measurably
   different outcomes. Paste both `SampleFights` tables. If terrain changes
   nothing, it is decoration and you should say so rather than shipping it.
2. No room can spawn a unit inside a wall, on any seed you sample.
3. Issue 7's criteria still hold: wins are not clean sweeps, some composition is
   a coin flip, composition still matters.

---

## 13c — you can see the room · **pike**

**Files:** `Scripts/UI/**`, `Scenes/**`, `Tests/test_ui_*.gd`, `Screenshots/**`.

Draw the terrain. Walls, pillars, pits and hazards each need to be
distinguishable **at phone size**, which is the standing target now, and a pit
and a wall must not look the same — they behave like exact opposites.

`Palette` has `ARENA_FLOOR` and `ARENA_EDGE`. If you need more colours, post the
exact lines and I will add them; do not put literals in `Scripts/UI/`.

### Acceptance criteria
1. All four kinds are distinguishable from each other in one screenshot, at
   1280x720 and at a phone-shaped viewport.
2. A hazard reads as dangerous rather than as floor, and a pit reads as
   impassable rather than as a hazard. Show a fight, ask wren or teal which is
   which without telling them, paste the answer.
3. Terrain stays quieter than the units, in a busy fight and a near-empty one.

---

## What would make stopping the right answer, for any of the three

If terrain turns out not to change how fights play — if the `SampleFights` table
looks the same with and without it — say so and stop. That is a real finding and
it points hard at the compounding dynamic being the whole problem, which is
worth more than three sessions of polish on rectangles.

---

## Update: 13a has landed, and 13b is now on the critical path

`issue-13a/terrain-movement` is merged. Movement respects walls and pits, hazards
damage what stands in them, and `Terrain.line_is_blocked` is available to the
decision layer without being enforced by the simulation.

**So `Terrain` has a working consumer and no content.** 13b — teal putting
features into rooms — is what turns it from a tested module into part of the
game, and it has become more important than when this issue was written, for a
reason nobody predicted:

`siege_master x4` wins 20 of 20 finishing on 98% of its health (issue 24). The
likeliest mechanism is that four units at range 260 are never approached by a
room where every enemy closes to attack. **Line of sight is the natural answer to
a party that wins by declining the fight**, and it is the one lever that changes
that row without touching the five rows that are already good.

That makes 13b the most promising remaining item on the whole board, ahead of the
polish work.

**pike, on 13c:** you are not blocked. `CombatState.terrain` is on the trunk,
untyped and empty by default, so build the drawing against a hand-made array of
features exactly as you built the battle screen against hand-made `CombatState`
fixtures before `CombatSim` existed. When 13b lands you swap the source; if the
screen notices, you reached past the shape and that is worth knowing now.
