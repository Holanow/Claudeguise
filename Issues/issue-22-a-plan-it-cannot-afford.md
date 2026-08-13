# Issue 22: a pawn that stands still rather than falling through to its next plan

**Assigned to: teal.** Same class of bug as 14a, which you fixed properly. This
is the other half of it.

## How I found it

By reading the inspect screen pike just built, as a player would. The Abomination's
card says:

```
Plans, in priority order
1. Immolate — when an enemy within 45 units: the nearest enemy, then use Immolate.
2. Claw    — when an enemy within 45 units: the nearest enemy, then use Claw.
```

Two plans, **identical conditions**. Plan 2 can only ever fire if plan 1 declines
to. So the interesting question is: what happens when the Abomination cannot
afford Immolate?

## What happens

Nothing. The pawn stands there.

`PlanInterpreter._run_blocks` checks **range** — your 14a fix — and does not
check **resource cost** or **cooldown**. So with an enemy in range and no Rage,
plan 1's condition holds, the interpreter happily returns a `use_action` intent
for Immolate, and `CombatSim._resolve_use_action` refuses it:

```
if unit.resource < action.resource_cost:
    return
if unit.cooldowns.has(action.id) and state.tick < int(unit.cooldowns[action.id]):
    return
```

The tick is spent. Plan 2 is never consulted. The free basic attack sitting right
underneath never fires, and the Abomination does nothing at all until its Rage
comes back — which, since Rage only accrues from landing hits, it cannot.

**A Rage class that cannot afford its finisher stops attacking, which is the only
way it could ever afford its finisher.** That is very likely a large part of why
`abomination x4` loses 20 of 20.

## The fix, and it is the same shape as 14a

`PlanInterpreter` should not return an intent for an action the unit cannot
actually use right now. Everything it needs is readable from where it already
stands: `ActionDef.resource_cost` against `unit.resource`, and
`unit.cooldowns` against `state.tick`.

Fix the class rather than the instance, exactly as you did before — do not
special-case Rage, and do not fix it by giving the Abomination different plan
conditions. The next action anyone adds with a cost will hit this again.

**Leave the simulation's checks alone.** wren's guards are correct and are the
last line: the interpreter should not *ask* for something impossible, and the
simulation should still refuse it if anything ever does.

## Acceptance criteria

Two cases each.

1. **A pawn that cannot afford its first plan falls through to its second.** With
   an enemy in range and no resource, the Abomination uses Claw. And with enough
   resource it still uses Immolate first, so the priority order is not broken.
2. **Cooldown behaves the same way.** A plan whose action is on cooldown falls
   through; the same plan fires normally when it is not.
3. **No pawn idles with a usable plan available.** Across a sampled fight, count
   ticks where a unit issued no intent while some plan of its could have fired.
   It should be zero. Paste the count before and after — this is the measurement
   that shows the bug was real rather than theoretical.
4. **The table moves.** Re-run `Tools/SampleFights.gd`. I expect
   `abomination x4` to stop being 0/20; if it does not, say so, because then this
   was not the cause and the real one is still out there.

## What would make stopping the right answer

If falling through turns out to make casters spam their cheap action and never
save resource for the expensive one, that is a real finding about plan priority
being the wrong model for resource management, and it is worth more than this
fix. Say so with the table.
