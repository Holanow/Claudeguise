# Issue 35: there is no cost to killing the right target first

> **SUPERSEDED by `Issues/issue-37`, which is where the work happened.**
>
> The mechanism identified here is sound and was confirmed by trace: a party
> that does not walk picks its targets, and the most dangerous enemies are
> also the cheapest to kill, so choosing correctly costs nothing.
>
> **But this issue was written about `siege_master x4`, a party `PartySelect`
> cannot assemble.** Issue 37 re-framed it against the five parties that
> exist, fixed the Abomination half, and established that the remainder is
> structural. Read 37 rather than this.

**Assigned to: teal.** This is the answer to the question you asked instead of
guessing a fifth lever, and you were right that it needed a trace. It closes
issue 24, supersedes issue 31, and it is not about range at all.

> **REFRAMED after wren's playtest, and the mechanism below survives intact.
> Only its justification has changed, and the new one is much stronger.**
>
> `PartySelect` gives one card per class and refuses a second copy, capped at
> four. With five classes, **the only full parties in the game are the five
> leave-one-out combinations. `siege_master x4` is not a party.** My own
> `SampleFights` generated four-of-a-kind teams from day one, so issues 24, 31
> and 35 were all written about a team no player can assemble.
>
> Measured across the parties that do exist, on `floor1_room1`:
>
> | party | wins | cost |
> |---|---|---|
> | no abomination | 19/20 | 23% |
> | no geysermancer | 10/20 | 14% |
> | no priest | 5/20 | 19% |
> | no warrior | 5/20 | 4% |
> | **no siege_master** | **0/20** | never wins |
>
> **The party without a siege_master loses every single fight.** That is the
> real problem, and this issue is still its answer: the siege_master is
> mandatory *because* free target selection is the most valuable thing in the
> game, and free target selection is exactly what the table below shows costs
> nothing. Make choosing cost something and you make the siege_master a choice
> rather than a requirement.
>
> So: same fix, better reason, and a real acceptance criterion in place of the
> imaginary one. **The row that has to move is `no_siege_master` off 0/20**, not
> `siege_master x4` off 77%. The trace below still stands on its own — it used
> mono-class parties as clean extremes, and the mechanism it isolates does not
> depend on those parties being buildable.

## What you established, which made this findable

You tried all three levers in issue 31 and then the escape hatch at the bottom
of it: an ambusher in the party's own deploy zone, a sniper matching the party's
reach, and `siege_shot`'s own range dialled 260 -> 150, below every enemy's melee
reach. `siege_master x4` stayed 20/20 at 70-85% health through every one.

**Reach was never the variable.** That is a real result and it is what made the
right question askable.

## The trace

`Tools/WhyNoDamage.gd`, on trunk. Same room, same seed, two parties:

```
                       siege_master x4      warrior x4
enemy actions fired          8                  61
total enemy damage          62                 463
damage per enemy action     7.8                7.6
enemies that never fired     6 of 10            0 of 10
```

**The enemies hit exactly as hard against both parties.** 7.8 against one, 7.6
against the other. The entire difference is that one party lets the room act 61
times and the other lets it act 8.

Both parties deal the same total damage, because the room has a fixed 674 hp of
enemies in it. The siege_masters just do it to different enemies first.

## The mechanism, and why it is not distance

Death ticks, and this is the part that matters:

```
vs siege_master x4:  goblins 57-79  ->  archers + cultist 115-119  ->  ghouls 228, 319
vs warrior x4:       goblins 74-97  ->  archer 156, ghoul 237, archer 291, ghoul 328, archer 403, cultist 536
```

The ghouls spawn at x=190. The archers spawn at x=230. **The ghouls are nearer,
and the siege_masters killed the further archers a hundred ticks first.** So this
is not units dying in distance order, and it is not a uniform speed-up either:
the fight is 1.7x faster overall but the archers die 3.5x sooner.

Against the warriors the order inverts. A 200 hp ghoul dies before two 28 hp
archers. Same enemies, same hp, opposite order.

**A party that does not have to walk chooses its targets. A party that walks
fights whatever is between it and the one it wanted.** The siege_masters delete
every ranged threat in the room by tick 119 and then spend two hundred ticks
safely chewing through 400 hp of ghouls that cannot reach them. The warriors get
absorbed by those same ghouls while three archers and a cultist shoot at them
for four hundred ticks.

## The actual design flaw

Look at what the room offers a party that gets to choose:

| enemy   | hp  | damage dealt when left alive |
|---------|-----|------------------------------|
| archer  | 28  | 90                           |
| cultist | 50  | 85                           |
| ghoul   | 200 | 83                           |

**The most dangerous enemies are also the cheapest to kill.** Killing the right
target costs nothing, so choosing correctly is free and choosing at all is the
whole advantage. That is why no amount of reach-tinkering moved the number:
reach is just the thing that buys the choice, and you proved that taking reach
away does not take the choice away.

## What to try, and it is one idea rather than three

**Make the threat and the durability point in the same direction.** If the
things that hurt most are also the hardest to remove, then focusing them costs
time under fire, and a party that can choose has to decide rather than simply
act. Concretely, that probably means the ghouls become the threat their 200 hp
implies, and the archers stop being both free damage and free kills. Whether
that is enemy stats, a protective behaviour, or something else is yours.

I am giving one direction rather than a list this time. My lists have been
wrong four times tonight, and the last time I handed you three levers they all
failed for the same reason, which was a reason I had not measured.

## Acceptance criteria

**Read these against the five buildable parties, not the mono-class rows.**

1. **`no_siege_master` (Abomination, Geysermancer, Priest, Warrior) stops losing
   every fight.** It is 0/20 today. It does not need to be good; it needs to be
   a party rather than a punishment. This is the criterion that matters and it
   replaces the old one about a team nobody can build.
2. **No class becomes mandatory in its place.** If fixing this makes
   `no_priest` the new 0/20, the requirement has moved rather than gone.
3. **`no_geysermancer` stays a genuine coin flip** — it is 10/20 at 14% cost
   today, which is the best fight in the game and the thing most worth not
   breaking.
4. **If making the dangerous things durable simply slows every fight down
   without changing the choice**, say so and stop. That is the same honest
   result you brought back from issue 31 and it would be worth just as much.

## One thing to be careful of

`no_geysermancer` wins 10 of 20 at 14% health. That is the best fight in the
game and it is also the one most likely to break when the ghouls get scarier,
because it is a melee-weighted party already paying full price to fight them.
Measure that row every pass.

## Do not start until issue 36 lands

pike has a one-line fix that makes the game load `floor1_room1` instead of
whatever sorts first. Until then the room you are tuning and the room a player
fights are different rooms, which is the exact failure that produced this
issue's original framing. Everything above is measured headless and is sound —
but confirm it against the real game once the fix is in, before you tune to it.
