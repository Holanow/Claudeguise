# Issue 41: put one item on one pawn and prove it changes a fight

**Assigned to: teal.** Before item generation, before the equip screen, before
a fourteenth item.

## Why this and not the two you offered

You asked whether to take item generation (rolling stats within a base type's
range) or armour screen prep. **Neither.** Thirteen items exist and **nothing in
the game can hold one.**

This project has already paid for that mistake twice tonight, and both times it
cost hours:

- `EquipmentDef` sat in Core with `PawnData` slots, an `equipment()` helper,
  `Balance` reading `armor.damage_reduction` and `CombatSim` merging granted
  actions. Every piece wired. **Nothing created an item**, so none of it ran.
- `floor1_room1` was balanced all night by four people while `PartySelect`
  loaded a different room. Every number was real and described a fight nobody
  played.

**Content that exists but cannot be reached is worth nothing, and from the
inside it looks exactly like content that works.** Rolling varied stats now
multiplies unreachable content. Get the chain working on one item first.

## The smallest thing that proves it

`PawnFactory.make_starter_pawn` is yours. Give a starter pawn a starting weapon
from the registry. That is the whole change.

Then run `Tools/SampleFights.gd` and **show the table moving.** That single
measurement exercises the entire chain end to end: registry -> item -> pawn slot
-> `Balance.attribute` -> attack power -> a fight outcome. Nothing else you could
build tests all of that at once.

**If the table does not move, something in that chain is broken**, and you want
to find that now rather than after there are sixty items. A green test suite will
not tell you: every piece of this has passing tests today and the chain has never
once run.

## Acceptance criteria

1. **Starter pawns carry a weapon**, and the weapon is one each pawn's class may
   actually wield per `allowed_methods`.
2. **`SampleFights` output differs from trunk**, and you say by how much. The
   direction matters less than the fact that it moved.
3. **The five-party balance is re-stated after the change.** Items make every
   party stronger, so the table will drift; say where it lands. If it drifts far
   enough to flatten the three coin flips, that is a finding and it changes what
   items should be, so report it rather than tuning it away.
4. **A test that a pawn's equipment actually reaches its combat numbers** — not
   that the slot is populated, but that the number downstream of it differs.
   That is the assertion none of the existing tests make.

## What would make stopping the right answer

If starting equipment turns out to flatten the balance badly enough that items
cannot be starting gear at all — that they have to be loot, earned mid-run —
**say so and stop.** That is a real structural finding about where items belong
in the game, and it is worth more than a working `PawnFactory` change. It would
also route the next piece of work to wren rather than to you, which is exactly
the kind of thing to discover before three sessions build on the assumption.


---

## Outcome: the chain works, and the stopping condition fired. Items are loot.

**The chain is proven.** teal put starter weapons on the pawns and the table
moved, which is exactly what this issue asked for: registry -> item -> slot ->
`Balance.attribute` -> attack power -> outcome, running end to end for the first
time. Every part of that had passing tests before tonight and had never once
executed together.

**And it flattens the game.** All five real parties go to 18-20 wins in 20. The
two balance guarantees teal wrote earlier both went red on their own:

```
FAIL test_some_composition_is_a_genuine_coin_flip   expected 6-14 of 20, got 20/20
FAIL test_a_winning_party_pays_a_real_cost          expected <=40% cost, was 49%
```

Verified in a review worktree rather than taken from the report. **The gate
caught this by itself**, which is what it is for and the first time it has
stopped a design mistake rather than a code one.

teal reported it and did not tune it away, which is what the issue asked and is
the reason we get to make this decision on evidence.

### The decision: items are loot, not starting gear. This is mine.

Three reasons, in order of weight:

1. **Measured.** Starting gear destroys the three coin flips that took the whole
   night to create, and drops the cost of winning below the bar the player set
   ("2 members down and the other 2 almost dead"). Everything good about the
   current balance is gone in one change.
2. **It is where the genre puts them, and where this game already has a shape to
   hang them on.** wren's floor curve degrades party entry health 98.7% ->
   93.7% -> 73.8% across the rooms. Items earned as you descend are the thing
   that answers that curve. Items held from the start just make room one
   trivial, which is precisely the 18-20/20 we measured.
3. **It preserves the fight balance as tuned.** The room stays calibrated for an
   unequipped party. Power arrives during the run instead of before it.

### What this routes, and it is what the stopping condition predicted

- **wren:** the floor awards an item after a room. `Scripts/Floor/**` already
  carries damage forward between rooms, so it already has run state to hang this
  on. This is the reachability mechanism and it is now the critical piece.
- **teal:** drop the starter-weapon change, keep everything else. What drops,
  and how often, is content and yours.
- **pike:** the equip screen, once something can be equipped.

**Do not merge `issue-41/reachable-items`.** It is red, and correctly so. Its
value was the knowledge, and the knowledge is now written down here.
