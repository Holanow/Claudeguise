# Issue 28: walls stop feet and not arrows

**Two parts. wren consults the flag, teal sets it.** Filed the same minute the
Core field landed, because the last three times a mechanism arrived without its
other half, the other half did not get written.

## What teal's own test found

`test_the_wall_changes_the_fight_from_the_open_room` — teal wrote it to fail if
terrain turned out to be decoration, exactly as issue 13b criterion 1 asked. It
fails: *"floor1_chokepoint's wall should change the fight on at least one of 5
seeds, or it is decoration."*

The reason is not the wall's placement. **`Terrain.line_is_blocked` is written,
tested, and called by nothing.** Walls stop movement, and every ranged attack in
the game fires straight through them.

So terrain currently cannot touch the finding that matters most: a party at 200+
units takes zero damage, and the whole cost of every fight falls on whoever
closes to melee. A wall that does not block a shot does not threaten a back line.

`ActionDef.requires_line_of_sight` is on the trunk, defaulting to `false` so
nothing changes until both halves land.

## 28a — the simulation consults it · **wren**

**Files:** `Scripts/Combat/**`, `Tests/test_combat_*.gd`.

`_resolve_targets` already measures range at the moment the effect lands. Line of
sight belongs in the same place and at the same moment, for the same reason: a
target that steps behind a pillar during a wind-up should be missed, and that is
the interesting case rather than an edge case.

A blocked shot is a `MISS` — the event already exists, pike already draws it, and
a player already knows what it means.

**Pillars and walls block; pits do not.** `Terrain.blocks_sight()` knows the
difference and is tested.

### Acceptance criteria
1. An action with the flag set is stopped by a wall between actor and target, and
   lands with no wall. Both.
2. A target that moves behind cover during the wind-up is missed, and one that
   steps out from behind it is hit. Both — this is the case terrain exists for.
3. An action without the flag is unaffected by any wall, so nothing that works
   today changes until teal opts an action in.
4. Determinism survives. Reuse issue 1's test.

## 28b — content declares which actions need it · **teal**

**Files:** `Scripts/Content/**`, `Tests/test_content_*.gd`.

Set the flag on the actions where a clear shot should matter. My instinct is
every ranged attack and no melee one, but that is your call and there are
interesting exceptions — a lobbed or magical attack arcing over a wall is a
legitimate design choice and a good reason for one class to differ from another.

Then re-run your own wall test. If it still says decoration, that is a finding
about the room's geometry rather than about the mechanism, and it is worth
reporting rather than moving the wall until the test goes quiet.

### Acceptance criteria
1. Your `test_the_wall_changes_the_fight_from_the_open_room` passes for a real
   reason, and you can say in one sentence what the wall changes.
2. **The back-line measurement moves.** Re-run a fight and check what the ranged
   units finish on. Right now a geysermancer finishes a winning fight on 98/98
   having taken zero damage. If terrain does not change that number, terrain is
   not the answer to issue 24 and I want to know that.
3. The rest of the table holds — the coin flips stay coin flips.

## What would make stopping the right answer

If line of sight makes ranged classes unplayable rather than merely mortal, say
so with both tables. **A back line that cannot fight is not an improvement on a
back line that cannot be hurt**, and I would rather have the finding than a
mechanic that overshoots.
