# Issue 7: make the fights close, and make the seed mean something

**Assigned to: teal.** This is the most important issue in the project right
now. Everything else is downstream of it.

## The measurement this comes from

`Tools/SampleFights.gd` on the trunk, 7 party compositions × 20 seeds = 140
fights with real content:

```
siege_master, geysermancer, priest, warrior   win 20/20  4 survivors   9.0s
priest x4                                     win 20/20  4 survivors   4.2s
warrior x4                                    win 20/20  4 survivors   6.7s
abomination x4                               lose 20/20  0 survivors  12.1s
siege_master x4                              lose 20/20  0 survivors   9.9s
geysermancer x4                              lose 20/20  0 survivors  10.5s
abomination, siege_master, geysermancer, priest  lose 20/20  0 survivors
```

**Every win kept all four pawns. Every loss lost all four.** Not one fight in
140 was close. Min, median and max tick count are the same number for every
party, so the seed does nothing.

**You found the seed half first, wrote it into
`Tests/test_content_encounter.gd`, refused to fake criterion 6 over it, and
flagged it on the board for me. I merged issue 2 before answering you.** That
was my failure, not a gap in your work, and the answer you were waiting for is
below.

## The two decisions, both from the user

**1. Damage varies with the seed.** Add a spread to damage rolls, drawn from
`state.rng` — the seeded instance that already exists and that `CombatSim`
already consults for stochastic rounding. Never `randi()`, never a new
generator. Same seed and same inputs must still reproduce a fight exactly.

**2. Tune the numbers until fights are close.** This is the chosen route, over
the alternative of changing why an advantage compounds.

**The risk you are being asked to accept, stated once so it is not a surprise
later:** a balance tuned to a knife edge on top of a dynamic that compounds can
tip back to a landslide the moment anything else changes — a new action, a
different party, wren's regeneration rates arriving. If that is what you find,
that finding is worth more than a tuned encounter, and criterion 5 below exists
to catch it. Do not hide it to make the other criteria pass.

## Files you own

`Scripts/Content/**`, `Scripts/Plans/**`, `Tests/test_content_*.gd`,
`Tests/test_plans_*.gd`. Same exclusions as issue 2.

**`Scripts/Combat/` is wren's.** If damage variance needs a hook the simulation
does not have, that is an issue for wren, not an edit by you. Say so on the
board and I will cut it. Check first, though: `Balance.attack_power` already
receives everything it needs to return a varied number, and `CombatState.rng` is
reachable from the simulation rather than from you — which is exactly the sort
of thing to ask about rather than work around.

**`Tools/SampleFights.gd` is mine.** Read it, run it, quote it. Do not edit it:
I use it to check your work, and a measuring instrument the measured party can
adjust is not a measurement. If it measures the wrong thing, tell me and I will
change it.

## Acceptance criteria

Two cases each, and most of them are distributions rather than single runs,
because a single fight tells you nothing about closeness.

1. **Winning costs something. REWRITTEN — read this, the target changed.**

   The user's framing, which is better than my original one:

   > "Measure balance by health ratios as well as wins vs losses. If a team wins
   > 75% of the time but they do it with 2 members down and the other 2 almost
   > dead I would call that fine pretty much."

   **So a high win rate is not the failure. A win that costs nothing is.** My
   original criterion demanded a median of 2 or 3 survivors out of 4, which
   would have rejected the 75%-win-rate fight the user just called fine, and
   accepted a 50% win rate where every win is untouched. It was measuring the
   wrong thing.

   `Tools/SampleFights.gd` now prints a `cost` line: what percentage of its own
   starting hp the party finished on, with dead pawns counted as zero. Steer by
   that.

   Met when: a party that wins most of the time finishes the median fight on
   **40% or less** of its own hp, **or** with two or more pawns down. And a party
   that loses most of the time still kills at least one enemy in the median
   fight, rather than being wiped without landing anything. Paste both.

   **Where this stands right now, and it is narrower than I had been saying:**
   the winning party finishes on **80%** of its hp. Wins are not free — the party
   takes real damage — but no pawn ever dies. Twenty percent spread across four
   pawns kills nobody, and killing one needs roughly a quarter of the party's
   whole pool landing on a single unit. **So the problem is concentration, not
   total damage**, which is exactly what the action-economy reading in
   `Issues/reading-enemy-balance.md` predicts more attackers will fix.
2. **The seed changes the fight.** Across 20 seeds with one party, tick counts
   differ: max minus min is at least 15% of the median. And the same seed twice
   is still bit-identical, event for event — reuse issue 1's determinism test
   rather than writing a new one.
3. **At least one composition is a genuine coin flip.** Some party wins between
   6 and 14 of 20. And no party wins exactly 20 or exactly 0 of 20, which was
   issue 2's criterion 6 and is now reachable. Paste the full table.
4. **Composition still matters.** The best party still beats the worst party by
   a wide margin in win rate. This is the guard against tuning everything toward
   the middle until all five classes feel the same, which is the obvious way to
   satisfy criterion 3 and ruin the game.
5. **The tuning holds still when something moves.** Pick one number that is not
   yours — wren's regeneration rate, currently 0 — give it a plausible non-zero
   value, and re-run the table. Report what happened. If the fights go back to
   landslides, **say so and stop**: that is the risk above coming true, it is
   the most valuable thing you could report, and it is a finding about the
   design rather than a failure of your tuning.

## What would make stopping the right answer

Any of: you cannot find a band where fights are close; the band exists but is so
narrow that criterion 5 breaks it; or making fights close requires the classes
to converge and criterion 4 fails. All three are real results. Report them with
the tables and stop rather than shipping a knife edge that reads as tuned.

## Before you ask for review

`Tools\gate.ps1` green, `main` merged in, collected test count up, and the full
`SampleFights` table pasted in your update — before and after.
