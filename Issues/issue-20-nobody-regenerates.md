# Issue 20: three of four pawns end every fight with no abilities

**Assigned to: teal.** Numbers only — the mechanism already exists and works.
Take it inside issue 7, not on a new branch: it is the same tuning pass and it
may move your table more than the spread does.

## Measured on the trunk

Seed `0000BEEF`, the four-class party, resource at the end of the fight:

```
  abomination    RAGE    start  68   end  28 / 68
  siege_master   ENERGY  start  50   end   0 / 50    *** DRY ***
  geysermancer   MANA    start 102   end   2 / 102   *** DRY ***
  priest         MANA    start 102   end   2 / 102   *** DRY ***
```

**Nothing regenerates. Ever.** Three of the four pawns finish with nothing left,
and the Abomination's Rage only ever goes downward.

`README.md` says the opposite for all three kinds: Mana is a large pool that
recharges slowly, Energy is a small pool that recharges quickly, and Rage *fills
as the pawn attacks*.

## Why it happened, which is worth more than the bug

Nobody made a mistake. wren built the regeneration mechanism properly on issue 4,
including the structural guard that Rage can never tick up on a timer, and left
the rates as `SimDeps` defaults returning `0.0` with a comment saying the real
numbers arrive when `Balance.resource_regen_per_tick` and
`Balance.rage_gain_per_attack` exist. Those functions were never written, because
no issue ever asked you for them. I wrote issue 4 and I did not write the
follow-up.

**This is the fourth defect today that lived in the gap between two sessions
rather than inside one**, after the enemy art ids, the stub-list merge and the
plan ranges. It is the standing risk of this setup and it is mine to catch.

## What it costs the game right now

After roughly thirty seconds every caster is dry and the fight becomes basic
attacks only. Classes stop being themselves. It is very likely part of why no
fight is close — a fight with no abilities in its second half is an attrition
race, and attrition races are exactly the landslides `SampleFights` measures.

It also explains the `OOM` marker sitting on the Priest in wren's playtest
screenshot, which we all looked at and nobody questioned.

## What to build

Two functions in `Balance`, and the numbers in them:

```
static func resource_regen_per_tick(unit: CombatUnit) -> float
static func rage_gain_per_attack(unit: CombatUnit) -> float
```

Then tell wren to point `SimDeps._default_resource_regen_per_tick` and
`_default_rage_gain_on_attack` at them — those are two lines in wren's file and
they are wren's to change, not yours. Post the request on the board; wren has
been turning these around quickly.

Per `README.md`: Mana large and slow, Energy small and fast, Rage from landing
attacks only. wren's simulation already refuses to regenerate Rage on a timer, so
you cannot get that one wrong by accident.

## Acceptance criteria

1. **A caster that spends its pool gets it back.** A Mana pawn ends a normal
   fight above zero; and a Mana pawn that casts constantly still runs out
   sometimes, or the resource is not a constraint and may as well not exist.
   Both halves, measured, pasted.
2. **Energy recovers faster than Mana**, measured as a percentage of pool per
   second, both numbers pasted.
3. **Rage rises only from landing attacks.** A pawn that lands attacks gains it;
   the same pawn standing idle does not. Both.
4. **The table moves.** Re-run `Tools/SampleFights.gd` before and after. I expect
   this to change the shape of fights noticeably; if it does not, say so, because
   that would mean abilities are not deciding fights and that is a finding.
