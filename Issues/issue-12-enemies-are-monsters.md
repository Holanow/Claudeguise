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
