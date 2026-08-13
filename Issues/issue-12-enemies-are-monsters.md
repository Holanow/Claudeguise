# Issue 12: enemies are monsters, not mirrors of the party

**Assigned to: teal.** Fold this into issue 7 if it helps; the two are the same
tuning pass and the same files. Do not start a third branch for it.

## The decision, from the user

> "The enemy teams should be more basic enemies, goblins, ghouls, archers and
> such, so that you can design interesting encounters without being constrained
> by what pawns exist."

Floor 1 currently fields `dungeon_grunt`, `dungeon_archer` and `dungeon_cultist`
— three enemies that read as a party of pawns with the serial numbers filed off.
Replace them with a bestiary: goblins, ghouls, archers, whatever floor 1's
Dungeon theme in `README.md` suggests.

## Why it matters more than it sounds

The constraint being removed is on encounter *design*, not on flavour. An enemy
that mirrors a class inherits that class's whole shape — one resource, one
role, roughly symmetric stats — and an encounter built from three of them is
always some version of a mirror match. That is a large part of why every fight
currently ends 4 survivors or 0: both sides are playing the same game.

Monsters do not have to be balanced against each other or against a pawn. A
goblin can be weak and numerous. A ghoul can be slow and hard to kill and do
nothing but walk at you. That asymmetry is where an interesting encounter comes
from, and it is also the most promising lever you have for issue 7's problem,
which is that no fight is ever close.

`EnemyDef` already supports this: enemies carry flat `attack_power` and skip the
attribute system entirely, so nothing forces them to look like a class.

## Files you own

`Scripts/Content/**`, `Tests/test_content_*.gd`. Same exclusions as issue 2.

## Coordinate with me on one thing

**Every enemy that spawns needs a silhouette, and those are mine.** Tell me the
ids as soon as you have picked them and I will draw them; `Tests/test_art.gd`
fails naming any spawning enemy without one, so the trunk will tell you if we
get out of step. Do not rename an existing enemy and expect its art to follow.

I would rather you name them for what they are (`goblin`, `ghoul`,
`goblin_archer`) than for where they appear, so they can be reused on other
floors.

## Acceptance criteria

Two cases each.

1. **At least four enemy types, and they are not four versions of one thing.**
   Any two of them differ by a factor of two or more on at least one of hp,
   speed or damage. Paste the table. A bestiary where everything has 30 hp and
   walks at the same speed is a reskin.
2. **An encounter uses numbers, not just quality.** At least one encounter
   fields more enemies than the party has pawns, and at least one fields fewer
   and tougher. Both should be winnable. This is the thing the old
   three-mirrored-pawns roster could not express.
3. **Issue 7's criteria still hold with the new bestiary.** Wins are not clean
   sweeps, some composition is a genuine coin flip, and composition still
   matters. Re-run the `Tools/SampleFights.gd` table and paste before and after.
4. **Nothing spawns without art.** `Tools\gate.ps1` green, which now includes
   the check that every spawning enemy has a silhouette.

## What would make stopping the right answer

If a varied bestiary turns out not to make fights closer — if the landslides
survive it — that is a significant finding and it points at the compounding
dynamic rather than at the roster. Say so with the table rather than tuning
harder.

---

## Added later: two constraints that were never real

Straight from the user, and this is the lever your criterion-4 finding on issue 7
said you needed:

> "The monsters don't have to be in a team of 4, and 4 is only a maximum for
> pawns."

Both halves matter, and neither is in any code — `Encounter.enemy_spawns` is a
list of any length, and nothing anywhere requires a party of four.

**Enemies are not a party.** An encounter can field eight goblins, or two ghouls
and six rats, or one thing that is genuinely dangerous. This is the answer to
"how does a room threaten a strong party without inflating one enemy's damage
until the coin-flip comps get crushed" — **numbers, not bigger numbers.** Eight
weak attackers spread damage across four pawns in a way that two strong ones
cannot, and spreading damage is precisely what turns a clean sweep into a win
that costs somebody.

It also rescues the thing you flagged as structural. You said a winning party
never bleeds because its margin is wide enough that variance moves duration and
never casualties. A margin against four enemies is not a margin against nine.

**Four is a maximum, not a requirement.** A player may bring one, two or three
pawns. That is a difficulty dial the player controls, and it is a second decision
in a slice that currently has exactly one — a three-pawn run of a strong
composition may be far more interesting than a four-pawn one, and it costs
nothing to allow because `CombatSim.build` already takes a party of any size.

## What this changes in this issue

- Criterion 2 already asked for one encounter fielding more enemies than the
  party has pawns. **Push it much harder than you were going to.** Try eight,
  try twelve. Find where it breaks.
- Add: sample the table at party sizes 1, 2, 3 and 4, not only 4. If a
  three-pawn party is a genuine coin flip where a four-pawn one is a clean
  sweep, that is the closeness you have been hunting, and it arrived as a
  player choice rather than as a tuning constant.
- **pike will need to know** if party size becomes variable: party select caps
  at four today and shows "Party full". Tell them on the board rather than
  assuming; the cap staying as a maximum is fine, the screen just needs to stop
  implying four is required.

## And placement is a balance lever, not decoration

Also from the user:

> "You can also adjust enemy placement and terrain to make certain monsters more
> or less troublesome in context."

This is the third lever and probably the cheapest of the three, because
`Encounter.party_spawns` and `enemy_spawns` are already hand-authored `Vector2`s
and you own them.

The same monster is a different problem depending on where it stands. An archer
at the back of a room behind three grunts has to be reached through them; the
same archer standing next to your melee line dies first and contributes nothing.
A caster tucked in a corner is protected by geometry; the same caster in the open
is the obvious first target. **Nothing about the monster changed. The fight did.**

This matters for the same reason numbers do: it threatens a strong party without
touching any monster's stats, so it cannot crush the coin-flip compositions the
way raising damage would.

Three things worth trying, in rough order of effort:

- **Depth.** Put the fragile, dangerous enemies behind the durable ones so the
  party has to spend time getting to them. Right now everything spawns in a
  loose line and the whole enemy side is reachable at once.
- **Spread.** Enemies far apart force the party to split or to pick an order,
  which is a decision. Everything in one clump is one decision.
- **Terrain that favours somebody.** Issue 13b is yours and this is what it is
  for: a pillar that a caster hides behind, a chokepoint that makes six weak
  enemies a real problem instead of a free lunch, a hazard that punishes the
  shortest path to the back line.

Sample the table for each arrangement rather than reasoning about it. "The same
roster in two placements produced these two tables" is the finding worth having,
and it is criterion 1 of issue 13b already.

## And the party starts in the left third

Also from the user:

> "I would also restrict the player team starting area to the first third of
> their starting screen so they have to traverse to their targets."

`CG.PARTY_DEPLOY_FRACTION` and `CG.party_deploy_max_x()` are on the trunk now.
With the current arena that puts the rightmost legal party spawn at **x = -160**.

**This is a design rule, not a layout preference.** Without it an encounter can
be authored with the two sides already in contact, and then positioning,
movement speed, kiting and the entire ranged-versus-melee distinction stop
mattering on tick one. Traversal is what makes a Geysermancer a different thing
from a Warrior.

Your current spawns do not satisfy it — measured mid-fight, party members sit
around x = -70 to -156, which is at or right of the line.

Two things to do, and the second is the one that lasts:

1. Move `party_spawns` in `floor1_encounters` into the left third — which also
   fixes the overlap I flagged earlier, since you have more room to spread them
   than you were using.
2. **Add the test.** Walk every registered encounter and assert every
   `party_spawns` entry is at or left of `CG.party_deploy_max_x()`. It belongs in
   your `Tests/test_content_*.gd` because it checks content, and it should walk
   the real registry rather than a list typed into the test.

I deliberately did not add that test myself. It would have gone red on the
trunk immediately, and a red trunk that is really a request addressed to one
person is a bad way to ask for something. Enemies stay unconstrained on purpose.

## Enemies are allowed to be flatly stronger, and a party is allowed to become strong

Also from the user:

> "Enemies can also have stat blocks that are in general higher than players
> (and vice versa it should be possible for the player to build a strong team)."

This removes an assumption neither of us wrote down but both of us were obeying:
that a monster should be roughly a pawn's equal. It should not. `EnemyDef` skips
the attribute system entirely and carries flat numbers precisely so a monster can
be whatever the encounter needs, including simply tougher than anything the
player can field.

Read together with the party-size and placement levers, the room now has four
independent dials and none of them require touching a pawn:

- **how many** — eight weak or two strong
- **where** — depth, spread, behind terrain
- **how strong each one is** — and this can be above a pawn's line
- **how many pawns the player brings** — their dial, not yours

**The second half matters as much as the first.** A player who assembles a good
composition should be able to feel it, and "every fight is a knife-edge" is its
own kind of bad game. Your criterion 3 on issue 7 already protects this: the best
composition should still beat the worst by a wide margin. Do not tune that away
chasing closeness. **What we want is that a strong party wins and it costs them
something — not that every party is level.**

The shape to aim for, and it is worth writing down because it is easy to lose:

- A weak or badly matched party loses.
- A middling party is a coin flip.
- **A strong party wins, and finishes with casualties or with somebody near
  death.**

That third line is criterion 1 of issue 7, the one still unmet, and these four
dials are how it gets met without flattening the other two.
