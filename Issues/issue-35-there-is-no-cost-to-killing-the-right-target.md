# Issue 35: there is no cost to killing the right target first

**Assigned to: teal.** This is the answer to the question you asked instead of
guessing a fifth lever, and you were right that it needed a trace. It closes
issue 24, supersedes issue 31, and it is not about range at all.

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

1. **`siege_master x4`'s cost drops into the same band as the rest of the
   table** on `floor1_room1`, and `Tools/WhyNoDamage.gd` shows the enemy getting
   meaningfully more than 8 actions against it.
2. **`abomination x4` stays a coin flip** (currently 6/20, winning on 9%) and
   `warrior x4` does not become unwinnable. The melee parties are already paying
   full price; this must not make them pay more.
3. The balanced party stays around 17-19 wins at a real cost.
4. **If making the dangerous things durable simply slows every fight down
   without changing the choice**, say so and stop. That is the same honest
   result you brought back from issue 31 and it would be worth just as much.

## One thing to be careful of

`warrior x4` currently wins 19 of 20 on 24% health, with three of four dead. That
is a good fight. It is also the fight most likely to break when the ghouls get
scarier, because the warriors are the party already fighting the ghouls. Measure
that row every time.
