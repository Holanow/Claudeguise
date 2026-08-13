# What happens after the slice — GATED, do not start

**Nobody starts anything in this file until I say the gate is open on the board.**

The user's instruction, verbatim on the condition:

> "I'd like you to start working on fleshing out the whole first floor, rooms for
> procedural generation, a boss/miniboss, and also an item system. I want pawns
> to be able to equip items that change their stats and also give them new
> options for their plans of action. I would also like a plan of action editor.
> **Again all of this stuff is only to be done if you think the vertical slice
> looks good** and also I'm asleep."

## The gate

`Issues/slice-done-bar.md`, and specifically the parts still unmet:

- **Winning has to cost something.** Currently the winning party finishes on 80%
  of its hp and never loses a pawn. Issue 7 criterion 1, rewritten.
- **No developer language on screen.** "Victory (197 ticks)", raw action ids in
  the log, `ANTI_SUPPORT` on a card. Issue 19.
- **Regeneration wired end to end**, and the table re-measured after it. Issue
  20, in flight.

I will say on the board when it opens, and I will say plainly if I do not think
it has. **A slice that is nearly good plus four new systems is worse than a slice
that is good**, because every one of these expansions multiplies the surface that
the unfixed problems live on. Items make balance harder to reason about. A plan
editor makes an unreadable plan system a worse experience, not a better one.

## The four, in the order I would do them

Sequenced by what each one needs, not by appetite.

### A. Items — teal and me, then pike
Highest value per unit of work, and the most nearly free: `EquipmentDef` already
exists in Core with `attribute_percent`, `attribute_flat`, `damage_reduction` and
`granted_actions`, and `PawnData` already has weapon, armor and accessory slots.
`CombatSim._collect_player_actions` already merges equipment-granted actions into
a unit's action list. **None of it is wired to anything that creates an item.**

So: generation (teal), the base types from `README.md`, the tag gating that says
which class can use what, and a screen to equip (pike). Wants `Balance` to be
the only place a stat multiplier is applied, or item stats and class stats will
be tuned in two files.

**Why first:** it is the piece with the most already built, and it feeds both of
the others — items grant plan blocks, and items are what a floor's treasure rooms
contain.

### B. Plan of action editor — pike, teal
The thing `README.md` is actually about, and the reason the plan interpreter was
built read-only. **Do not start it until issue 21 (inspect your pawns) has
landed and somebody has read a plan back correctly.** If a player cannot read a
plan, an editor is a worse experience than no editor, and issue 21's criterion 3
is exactly the test of whether they can.

Wants: block palette, drag or tap to build, the WIS budget from
`Balance.plan_block_budget` enforced visibly, and validation that refuses a plan
the interpreter would reject — `PlanInterpreter` already has the whitelists and
the range check.

### C. Floor 1 for real — wren, then teal
`Scripts/Floor/` already has `FloorPlan`, `FloorRoom`, `FloorGenerator`,
`FloorRun` and `FloorFightRunner`, all headless and tested, with seeded
generation and layout preserved across descent and ascent. What is missing is
the content behind the room types (`README.md` names Enemy, Big Enemy, Trap,
Treasure, Library, Cell, Miniboss, Boss) and a screen to see the map on.

**wren already measured that difficulty is flat** — average survivors 4.0 across
difficulties 1 through 4 — and correctly reported it as the landslide problem
rather than a wiring defect. That measurement has to be redone after issue 7
closes, and it is the real acceptance test for a floor: **a floor is a
difficulty curve or it is a corridor.**

### D. Boss and miniboss — teal, with wren for anything the sim lacks
`README.md`: The Warden and the Rat King. Bosses have three phases, traps in the
arena, and minions. **Phases are a simulation capability that does not exist**,
so wren scopes that before teal writes a boss around it.

Do this last. A boss is the hardest encounter to balance and it should be built
on top of an encounter system that has been shown to produce good fights, not
before it.

## What I would refuse to add here, unasked

Loot tables beyond floor 1, the other six floors, shops, the ascent, and the God
Guise item. All are in `README.md` and none of them make the first floor better.
