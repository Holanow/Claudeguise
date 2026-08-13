# Issue 4: resources refill, and statuses do something

**Assigned to: wren.** Follow-up from the issue 1 review. Issue 1 is merged;
this is not a rejection of it.

## Where this came from, and whose mistake it was

Issue 1's tick order says step 3 is "tick statuses, cooldowns, wind-ups **and
resource regeneration**". None of the six acceptance criteria mentioned
resources. wren built and tested exactly what the criteria asked for, and the
criteria are what got checked. **That is my error in writing issue 1, not a miss
in the work**: a contract paragraph nothing checks is a comment, and I should
have written a criterion for it or left it out.

Same for statuses. Issue 1 said "statuses tick down", and they do, exactly as
specified. It did not say anything applies them to anything, so nothing does.

## Outcome

A fight can be fought with resource-gated abilities without every caster
permanently running dry, and a status effect changes what happens rather than
only appearing in the log.

## Files you own

- `Scripts/Combat/**`
- `Tests/test_combat_*.gd`

Same exclusions as issue 1. `Balance` stays teal's: every number here arrives
through `SimDeps`, and `Scripts/Combat/` still holds none of its own.

## What to build

**1. Resource regeneration, per kind.** `README.md` gives the three kinds
different behaviour and the difference is the point:

- **Mana** — large pool, refills slowly over time
- **Energy** — small pool, refills quickly over time
- **Rage** — small pool, fills *when the pawn attacks*, not over time

Rage is the one that does not fit a regen-per-tick hook, so design the seam for
it rather than bolting it on: a Rage pawn that has not swung recently should be
empty. Add whatever `SimDeps` entries you need; the rates are teal's numbers,
the mechanism is yours. Emit an event when resource changes if you conclude the
combat log needs it — your call, and say which way you went and why.

**2. Statuses that do something.** At minimum `STUN`, and whichever others you
conclude belong in the simulation rather than in `Balance`.

`SHIELD` and `BLOCK` already work without you: they can be read inside
`Balance.damage_reduction`, which receives the whole `CombatUnit`. Leave them
there and say so, rather than implementing them twice.

`STUN` cannot be done that way — nothing in `_decide_phase` looks at statuses,
so a stunned unit decides and acts normally today. That is the trap: teal can
write a perfectly good stun action and it will do nothing, and it will look like
their bug.

`BURN` and `POISON` are damage over time and need a tick hook and an event, or
they are invisible. `HASTE` is a movement or action-speed modifier. Decide which
of these are in scope for the slice and **say in the PR which you left out**, so
teal does not build content on a status that does nothing.

## Acceptance criteria

Two cases each.

1. **Mana and Energy refill; Rage does not.** Run a fight where a Mana pawn
   spends its pool: it recovers over time and casts again later. Then the same
   for a Rage pawn holding still without attacking: its resource does **not**
   climb. Paste both resource traces.
2. **Rage fills from attacking.** A Rage pawn that lands attacks gains
   resource; the same pawn out of range, swinging at nothing, does not. The
   second half is what stops rage becoming a slow timer with extra steps.
3. **Regeneration respects the ceiling and the floor.** A unit at full resource
   stays at `resource_max` rather than climbing past it, and a unit at zero
   never goes negative when an action is refused for cost.
4. **A stunned unit does not act.** A unit stunned during another unit's wind-up
   issues no intent and lands no action for the duration, and the same unit acts
   normally on the tick after the stun expires. The second half catches a stun
   that never clears.
5. **Determinism survives.** The same seed and inputs still produce an identical
   event list with regeneration and statuses in play. Rerun the criterion 3 test
   from issue 1 rather than writing a new one.

## What would make stopping the right answer

If Rage cannot be made to feel different from Energy inside this slice's scope,
say so. Three resources that all read as "a bar that fills" is a finding about
the design worth having early, and `README.md` is a design document, not a
specification I am defending.

## Before you ask for review

`Tools\gate.ps1` green, `main` merged in, collected test count up, and the PR
says which statuses you did not implement.
