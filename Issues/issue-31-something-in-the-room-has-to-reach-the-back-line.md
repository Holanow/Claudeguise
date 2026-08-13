# Issue 31: something in the room has to reach the back line

**Assigned to: teal.** This replaces terrain as the answer to issue 24. Terrain
was my idea, it was measured, and it did the opposite of what I said it would.

## The measurement that killed the previous plan

Issue 13's own text said, in my words: *"line of sight is the only lever that
threatens a back line as such rather than punishing one composition."* Measured
like for like on `siege_master x4`, after 13b landed and line of sight was really
enforced:

```
floor1_room1 (open)      20/20 win   77% hp   9.6-14.1s
floor1_cover (pillars)   20/20 win   92% hp   3.1-3.7s
```

**Cover made the pure-ranged party stronger and three times faster.** Not
neutral. Worse, on the exact row it was meant to fix.

The reason is not subtle in hindsight and I should have seen it before spending a
branch on it: **line of sight is symmetric, and the side with the longer reach
chooses the engagement.** A pillar that can deny `siege_shot` at 260 also denies
`goblin_arrow` at 200, and the unit that can stand further back is the one that
gets to pick which side of the pillar the fight happens on. Cover is a tool for
whoever out-ranges the room. That is not a bug in teal's rooms; the rooms do
exactly what they say. It is a wrong premise in my issue.

I do not know the mechanism behind the *speed* change — three seconds versus ten
is a large effect and "the enemies bunch up walking around a pillar and die
together" is a hypothesis, not a finding. **Do not tune against my hypothesis.**
It is written down so it can be checked, not believed.

## What the room actually lacks

Every enemy in `floor1_room1` reaches 40, 45 or 200 units. `siege_shot` reaches
260. wren's trace (issue 25) measured what follows: six of ten enemies never
closed past 127 units, never swung once, and the whole room did **17 damage** to
a party with 114 hp each.

The party deploys in the first third of the arena, by design and by the player's
own request. So **the room's back half is safe by construction** for anything
that never has to leave the deploy zone. Nothing in the bestiary can be in that
zone early. That is the gap, and it is a bestiary and placement gap rather than a
geometry one.

## Three levers, all yours, take whichever measures best

1. **Something fast and cheap.** A rusher with high `move_speed` and low hp that
   arrives while the back line is still firing. It does not have to survive. It
   has to make four ranged units spend shots on it, which is action economy, and
   action economy is the thing the bestiary work already showed moves this game.
2. **Something that reaches.** An enemy whose range matches or beats 260. This is
   the most direct answer and also the bluntest — it threatens the back line by
   being a back line, and two artillery pieces shooting at each other is not
   obviously a good fight. Worth measuring, worth being suspicious of.
3. **Something that starts close.** An ambusher spawning at or behind the party's
   own third. This one costs nothing in stats and changes the geometry that the
   deploy rule creates. It is my guess at the best of the three, which is exactly
   the reason to measure it rather than take my word.

You have been right about placement over stats twice tonight. Trust that over
this list.

## Acceptance criteria

1. **`siege_master x4`'s cost drops out of the UNTOUCHED band into a real cost**,
   on `floor1_room1`, measured with `Tools/SampleFights.gd`. It does not have to
   lose. The player's own bar: *"if a team wins 75% of the time but they do it
   with 2 members down and the other 2 almost dead I would call that fine."* A
   20/20 win at 40% with a casualty clears this. A 20/20 win at 92% does not.
2. **`abomination x4` stays a coin flip** and the composition spread survives.
   This has broken twice when the room got harder for everyone, which is the
   standing reason to reach for placement and one new enemy rather than for
   across-the-board numbers.
3. **The balanced party still lands around 17-19 wins in 20 at a real cost.**
4. **Say which of the three levers you used and what the other two measured**, if
   you tried them. A lever that did nothing is a result and I want it on the
   board rather than discarded.

## What would make stopping the right answer

If nothing in the bestiary can threaten a 260-range party without also flattening
the coin-flip comps, **say so and stop.** That points at `siege_shot`'s range
being the actual problem rather than the room's answer to it, which is a one-line
content change you own outright, and it would be a better finding than a new
monster. I have now been wrong about this row three times; the fourth guess
should not be mine.
