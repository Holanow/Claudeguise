# Issue 27: re-measure whether the floor is a difficulty curve

**Assigned to: wren.** This finishes issue 9's one open criterion, and it is the
right moment because the thing that made it unanswerable has been fixed.

## What you found the first time

On issue 9 you measured average survivors across difficulties 1 to 4, twenty
seeds each, and reported it honestly rather than asserting the criterion:

```
{ 1: 4.0, 2: 4.0, 3: 4.0, 4: 4.0 }
```

Flat. You said it read as the landslide problem rather than a defect in the
wiring, and recommended re-measuring once issue 7 landed. That was right, and the
re-measurement is now worth doing:

- Fights cost something. The balanced party finishes `floor1_room1` on 23% of its
  health and never with all four alive.
- Damage carries between rooms already — that is your `FloorRun` from issue 9.
- There are three real encounters now instead of one, of genuinely different
  shapes.
- Resource regeneration, statuses and the affordability fall-through all exist,
  so a pawn's second room is fought with a real resource state rather than an
  artefact of the first.

**A floor is a difficulty curve or it is a corridor.** Nothing else in the
project answers whether it is one.

## What to measure

1. **The same table, again.** Average and distribution of survivors by room
   difficulty, twenty seeds, with a party that is neither the strongest nor the
   weakest. Paste it beside the old flat one.
2. **Attrition across a run.** Party hp entering room 1, 2, 3 and so on. The
   interesting question is whether a run is a *sequence* or four independent
   fights: if the party enters every room at full health, `FloorRun` is carrying
   damage that regeneration then erases, and the floor has no arc.
3. **Where runs end.** Across twenty seeds, which room number kills a run. If it
   is always room 1 or always the last, the curve is a cliff.
4. **Whether `room.difficulty` is doing anything at all.** It currently scales
   the count of an encounter's spawns. With three encounters of different shapes
   available, that may be the wrong knob entirely — say so if the trace points
   there rather than working around it.

## What this is not

**Not a fix.** If the curve is still flat, report it with the numbers and stop.
The likely answers are content-shaped and therefore teal's — which encounter goes
in which room, how difficulty picks between them — and I would rather have your
measurement than your patch.

`Scripts/Floor/**` and `Tests/test_floor_*.gd` are yours if something genuinely
needs to change in the model.

## Acceptance criteria

1. The old flat table and the new one, side by side.
2. The attrition trace across a full run, and a plain statement of whether a run
   is a sequence or four independent fights.
3. A named answer to "is `room.difficulty` the right knob", with the evidence.

## What would make stopping the right answer

Finding that the floor is still flat. That is a real result and it is the one
that decides whether floor 1 is worth building out at all — which is the first
item behind the gate in `Issues/NEXT-after-the-slice.md`, so this measurement is
what tells me whether that gate should open onto a floor or onto something else.
