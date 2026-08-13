# Issue 24: siege_master x4 wins twenty out of twenty and does not get hit

**Assigned to: teal.** The last row of the table that is still the old shape.

## The measurement

`floor1_room1`, twenty seeds, immediately after issue 22 and `focus_bias` landed:

```
siege_master, geysermancer, priest, warrior   win 17/20  survivors 0:3 1:8 2:4 3:5 4:0   cost 23%
abomination, siege_master, geysermancer, priest  win 13/20  survivors 0:7 1:3 2:3 3:7 4:0  cost 24%
abomination x4                                win  9/20  survivors 0:11 1:6 2:3          cost  0%
priest x4                                     win 18/20                                  cost varies
siege_master x4                               win 20/20  survivors 0:0 1:0 2:0 3:0 4:20  cost 98%
geysermancer x4                               win  0/20                                  cost  0%
```

Five of six rows are now the shape we wanted. **`siege_master x4` is not:** it
wins every seed, never loses a pawn, and finishes on 98% of its health. An hour
ago it was an 8/20 coin flip.

`geysermancer x4` at 0/20 is the opposite outlier and worth a look in the same
pass, though a composition that simply loses is much less damaging than one that
wins untouched.

## Why this matters more than one row

**A composition that wins without being touched is exactly what we spent the
night removing**, and if it survives, the honest description of the game is "the
fights are interesting unless you find the safe party, and then they are not".
Players find the safe party. That is what players do.

It is also a fair test of whether the new levers actually work, or whether we
have moved the landslide rather than removed it. Everything that made the other
rows interesting — regeneration, the bestiary, placement, affordability
fall-through, focus bias — was available to this row too and it came out
untouched anyway.

## What I would look at, in order

Mine, and offered as starting points rather than a plan.

1. **Why is it not being hit?** `siege_master` is `SUMMONER`/`MARTIAL` at range
   260, the longest in the game. If four of them out-range everything in the room
   and nothing closes, they are not winning the fight so much as declining it.
   Check the distance trace, not the outcome.
2. **`focus_bias` may not reach them.** Concentration only matters if enemies can
   get to the thing they want to concentrate on. Against a party that never lets
   anything close, biasing target selection changes nothing.
3. **The room has no answer to range.** Every enemy in `floor1_room1` closes to
   attack. Nothing punishes standing still at 260 units. A single enemy that
   out-ranges or ignores distance would change this row without touching the
   others — which is precisely the per-enemy design lever issue 12 opened.
4. **Terrain, when 13b lands.** Line of sight is the natural counter to a party
   that wins by never being approached, and `Terrain.line_is_blocked` is already
   written and tested.

## Acceptance criteria

1. **No composition wins most of the time while finishing above 40% hp**, across
   the sampled table. That is criterion 1 of issue 7 applied to every row rather
   than to the row we happened to look at.
2. **The rows that are already good stay good.** Paste the whole table before and
   after. Fixing this by making the room harder for everyone would flatten the
   coin flips back into losses, which trades one failure for a worse one.
3. **Name the mechanism.** Not "tuned the numbers until it stopped" — say what
   was actually letting them win untouched, the way you named the concentration
   problem. If the answer turns out to be that four long-range summoners are
   genuinely a dominant strategy in a room with no line-of-sight blockers, that is
   a design finding and terrain is the fix rather than a stat change.

## What would make stopping the right answer

If closing this requires making the game worse for the other five rows, stop and
say so with both tables. **Five good rows and one dominant strategy is a better
game than six mediocre ones**, and I would rather ship the honest version with
the outlier documented than tune everything to the middle to hide it.

---

## Answered: wren's trace, and the mechanism is precise now

`Issues/issue-25` is done. My guess was right and the trace makes it exact, which
is more useful than being right.

**Every enemy range in `floor1_room1` is 40 (goblin), 45 (ghoul) or 200
(goblin_archer, cultist). `siege_shot` is 260 — sixty units longer than anything
in the room.**

1. The four goblins and two ghouls — **six of ten enemies** — never closed past
   127-136 units, against their own reach of 40-45. They died entirely inside a
   band they could never fight back from.
2. Only the archers and the cultist connected at all: **one hit each, 8 and 9
   damage**. Total enemy damage across the whole fight: **17**, against a party
   with 114 hp per unit. That is the 98% finish, and it is not a rounding
   artefact of a close fight — it is three hits in a room of ten enemies.
3. All four siege_masters fired continuously for 333 ticks. **There is no kiting
   here.** `siege_shot`'s 260 covers the room from the party's starting position,
   so they never had to move at all. I had assumed some retreat behaviour was
   involved; there is none, and that matters because it means no change to
   `DefaultBehavior` would fix this.
4. The contrast, same seed, with a warrior in the party: the warrior closes to
   distance 15 and ends the fight at 0/186 hp, and the ghoul and cultist land 119
   and 134 damage. **The room is dangerous. It is only dangerous to a party that
   comes within reach of it.**

## The general rule, which is worth more than this fix

**A party that out-ranges every enemy in a room is not fighting it.** No amount
of hp, damage, count or focus bias changes that, because none of those apply to a
unit that is never in range. That is a property of the *matchup*, not of the
numbers on either side.

So the answer is not to make the enemies stronger, and criterion 2 of this issue
already says so. It is one of:

- **Something in the room that reaches 260 or further**, so a pure long-range
  party has to answer it. One enemy, not all of them.
- **Terrain that breaks line of sight** (13b), so distance stops being a safe
  place to stand. `Terrain.line_is_blocked` is written and tested and unused.
- **Enemies that start inside their own range**, via placement, so the melee half
  is not crossing a killing field before it can act.

I would try the third first because it is free, then the second, and the first
only if neither works — a 260-range enemy is a big lever and it will affect every
other party too.
