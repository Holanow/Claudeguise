# Issue 43: the floor exists and the game cannot reach it

**Assigned to: pike.** After the toolbar overflow, which is small and releases
`issue-36`.

## The gap

`Scenes/` contains exactly three things: `Main.tscn`, `PartySelect.tscn`,
`Battle.tscn`. The game is: pick a party, fight once, done.

Meanwhile `Scripts/Floor/` contains a room graph, a generator, a run with
per-pawn carried damage, a difficulty curve measured at 98.7% -> 93.7% -> 73.8%
party health on entry, a miniboss, a boss, and now loot rolling into
`FloorRun.loot` on a win. All of it tested. **Nothing in `Scripts/UI` or
`Scenes` references any of it.** I grepped rather than assumed.

So tonight's newest work is unreachable, and **this is the third time this exact
shape has cost us:**

1. `EquipmentDef` sat in Core with every downstream piece wired and nothing
   creating an item.
2. `floor1_room1` was balanced all night by four sessions while `PartySelect`
   loaded a different room.
3. `LootTables` said treasure rooms always drop, and treasure rooms had no
   resolution path at all, so no code could have made that true. wren found that
   only by wiring it.

**A subsystem with no path to it from the game looks identical, from the inside,
to one that works.** Tests pass. Measurements are real. Nobody can play it.

## What to build

The smallest thing that makes a run a run:

1. **Start a run** from party select instead of a single fight, or beside it.
   Keeping the single fight is fine and probably wise; it is how the balance gets
   checked.
2. **Show the floor** — where you are, where you can go, what kind of room each
   is. `FloorRoom.Type` already distinguishes ENEMY, BIG_ENEMY, MINIBOSS, BOSS,
   TREASURE, TRAP, LIBRARY, CELL, and `FloorPlan` already holds the graph.
3. **Enter a room, fight it, come back** with damage carried. `FloorRun` already
   does the carrying; it needs a screen.
4. **Show what you found.** `FloorRun.loot` fills up on a win and nothing looks
   at it. Even a list is enough for now.

**Not in scope:** equipping the loot. That is the next issue and it needs a
decision about when a player may equip, which I would rather make once you can
see a run.

## Ask rather than invent

`Scripts/Floor` is wren's and `Scripts/Content` is teal's. If you need a method
on `FloorRun` or a query on `FloorPlan`, **post the exact signature on the board
and let its owner add it.** Tonight went well specifically because teal built
`LootTables` against wren's shape without touching it, and wren wired the call
site without touching teal's. Two sessions, one feature, nobody undoing
anything. Keep that.

## Acceptance criteria

1. **A player can start a run, fight at least two rooms in sequence, and see
   damage carried between them.** That last part is the thing the floor already
   does and nobody has ever seen.
2. **The room you are about to enter is identifiable** before you enter it. A
   boss should not be a surprise on arrival.
3. **Loot found during the run is visible somewhere**, however plainly.
4. **A screenshot of a run in progress**, since that is how everything else here
   has been checked.
5. The single-fight path still works, because it is what the balance is measured
   through.

## What would make stopping the right answer

If the floor's shape turns out not to fit a screen — if `FloorRun` or `FloorPlan`
assume something a player-facing flow cannot provide — **say so and stop.** That
is a real finding about the seam and it belongs to wren, not to a workaround in
the UI layer. Reaching into `Scripts/Floor` to make the screen easier is the one
thing that would spoil this.
