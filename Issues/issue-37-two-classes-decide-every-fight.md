# Issue 37: two classes decide every fight

**Assigned to: teal.** This answers your question — `no_siege_master` is not
supposed to be hard mode, and the lever is not in the bestiary. It is in the
classes.

## Your question, answered plainly

> *"Is `no_siege_master` supposed to be hard mode, or does it need its own
> lever?"*

**Neither. It needs a different lever, and so does the whole table.** A party
that wins 0 of 20 is not hard mode, it is a trap: the player picks it once,
loses, and learns "always take the Siege Master". That is a dominant strategy
wearing the costume of a choice, and it is the opposite of what a party-building
game is for.

Hard mode is fine. **4 to 6 wins in 20 is hard mode. Zero is a wrong answer on a
menu.**

## What the table is actually telling us, and it is not about the room

The five parties are a **leave-one-out ablation**, which is the cleanest way
there is to attribute value to a single class. Read it that way:

```
no abomination      19/20      <- the party without the Abomination is the best
no geysermancer     10/20
no priest            5/20
no warrior           5/20
no siege_master      0/20      <- the party without the Siege Master is the worst
```

Now look at the top and bottom rows specifically. They differ by **exactly one
swap**:

- `siege_master` + geysermancer + priest + warrior = **19/20**
- `abomination` + geysermancer + priest + warrior = **0/20**

Same three other classes. Change one pawn and the party goes from winning
nineteen fights in twenty to winning none. And the three parties that contain
*both* land in the middle at 5, 5 and 10.

**The Siege Master is worth a fight and the Abomination costs one.** Every other
number on the board is downstream of those two facts. That is why five separate
bestiary tunings all hit the same wall: you were adjusting the room to
compensate for a class-power gap, and the room applies to everyone equally while
the gap does not.

## Why your five attempts failed, and they were not wasted

Every lever you tried raised the room's threat, and a room-wide threat increase
hits the party that is already weakest hardest. You could not fix the bottom row
by making the room harder because **the bottom row's problem is that it is
carrying a weak pawn, not that the room is easy.** Your own summary said the
ceiling might be a composition's own fragility rather than the bestiary. That was
right, and it is worth saying that you got to the answer before I did, from the
same data, having been told to look at the room.

Issue 35's mechanism is not dead either, and it fits here rather than competing:
free target selection is *why* the Siege Master is worth so much. It is the class
that gets to choose, and choosing costs nothing. So issue 35 explains **which**
class is overpowered, and this issue is what to do about it.

## What to do

**Bring the two outliers toward the middle**, and prefer a per-class change over
a room-wide one, because the problem is per-class. Both directions are yours:

- The **Abomination** is a liability in every party it joins. Whether that is
  raw numbers, the Rage economy, or its plans is your call — you know that class
  better than I do, and you already fixed one Rage-affordability trap in it.
- The **Siege Master** is mandatory. If issue 35's reading is right, some of its
  value is the freedom to pick targets for free, so this may be the same fix as
  issue 35 rather than a second one.

**Do not make the room harder to fix this.** You have already measured five
times that it does not work, and the reason is now clear.

## Acceptance criteria

Measured with `Tools/SampleFights.gd`, real parties only.

1. **No party wins 0 of 20.** The worst should be a hard party, not a trap.
   Somewhere around 4 to 6 wins.
2. **No party wins 20 of 20.** The best around 16 to 19, still losing somebody
   most times it wins.
3. **At least one genuine coin flip** in the 8 to 12 band. `no_geysermancer` is
   at 10/20 today and is the best fight in the game — protect it.
4. **Wins still cost something.** The cost column is why it exists; a fix that
   flattens the spread by making everyone survivable is a worse game.
5. **Composition still matters.** If all five parties converge on 10/20, choice
   has stopped mattering, which is the failure at the other end. A spread from
   about 5 to about 18 is the shape.

## What would make stopping the right answer

If moving those two classes into line only shifts which class is mandatory —
`no_priest` becomes the new 0/20 — **say so and stop.** That would mean the
problem is structural rather than in two classes' numbers, and it would point at
the room needing more than one axis of threat, which is a much bigger design
question and one I would want to take rather than have you discover halfway
through.
