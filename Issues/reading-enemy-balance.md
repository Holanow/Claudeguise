# What other people have already worked out about enemy balance

Notes for teal, on issue 7's unmet criterion. rook's reading, not rook's
opinions — where I am adding my own inference to connect something to our
situation, I say so.

The user's standing instruction, which I should have followed sooner: **when you
cannot make a functional thing work, the first instinct should be to read about
how other people make it work.** A lot of ink has been spilled on this exact
problem and we were deriving it from first principles at 11pm.

## Our problem, stated so the reading has something to hit

Every winning party wins with all four pawns alive. Damage variance moves how
*long* a fight takes and never *who dies*. Raising enemy damage to force
casualties crushes the coin-flip compositions, so the obvious dial is the wrong
one. Measured, not assumed: `Tools/SampleFights.gd`.

## 1. Action economy is the lever, and it is the one we were not using

This is the strongest and most repeated finding, and it is exactly the thing the
user handed us independently.

> "A fight against multiple medium-strength enemies can be more dangerous than
> against a single powerful boss. More enemies mean more actions, which often
> leads to more tactical variety and threat."

> "No matter how strong the monster is, it's almost always at a disadvantage if
> it's outnumbered, unless it is ridiculously beyond the skills of the party."

Two enemies attacking four pawns is four pawn-actions against two. Nine enemies
attacking four pawns inverts it. **The number of actors on each side is a
separate dial from how strong each actor is, and it is the one that produces
casualties rather than longer fights** — because damage arrives at more places at
once and a healer cannot be everywhere.

That is my inference for why it fixes *our* symptom specifically, and it is
worth checking rather than trusting: our strong parties survive because incoming
damage is concentrated enough that hp lasts. Spread the same total damage across
four targets and the party's effective pool stops being "four healthy pawns" and
starts being "whoever is being hit right now".

## 2. The count dial is sharp — move it one at a time

From Into the Breach's postmortem, and this is a warning rather than a technique:

> "Balancing the difficulty has been a numbers game, with a single additional
> enemy turning a battle from 'a fun challenge' to 'completely impossible'."

Subset Games spent four years on that game. If one enemy flips a fight from fun
to impossible for them, **do not add three at a time and re-tune damage in the
same pass.** Sample the table after each single change or you will not know which
change did what. This is the same discipline as reproducing a bug before fixing
it.

## 3. Glass cannons threaten without flattening

> "Glass Cannon Enemies with high damage and low HP creates frantic, high-stakes
> tension."

Directly useful to us. A high-damage, low-hp enemy makes a strong party bleed
*and* dies to a strong party, so it threatens without becoming an unkillable wall
that crushes the weak compositions. That is precisely the shape criterion 4 needs
and raising everyone's damage does not have.

Pairs with the user's "enemies may have higher stat blocks than pawns": a
monster that hits harder than any pawn but folds in two hits is a completely
different design object from a pawn, which is the point of `EnemyDef` not using
the attribute system.

## 4. Do not tune every fight to the middle

> "By rigorously balancing every fight to be 'Medium' or 'Hard' according to a
> chart, we often smooth out the spikes of difficulty that create memorable fear
> or power fantasies."

Worth holding against issue 7's criterion 2, which asks for a coin flip. **A coin
flip is a target for *some* composition, not for all of them.** The shape on the
board stands: a weak party loses, a middling party is a coin flip, a strong party
wins and it costs them. Three different fights, not one difficulty.

## 5. Composition of the roster, not just its size

> "You'll likely need a mix of weak and strong, slow and fast, small and big,
> close range and long range."

> "Mixing roles like melee fighters, ranged attackers, and support units keeps
> players on their toes; pairing archers in high positions with melee combatants
> creates a more tactical challenge than simply increasing enemy numbers."

Note the last clause — role mixing is described as *better* than raw count, not a
substitute for it. Both, and the roles are what make placement matter, which is
the third lever the user gave us.

## 6. Terrain as a difficulty lever rather than decoration

> "Utilizing terrain features such as chokepoints, difficult terrain, cover or
> environmental factors can challenge your player's creativity immensely."

Already scoped as issue 13. Nothing new, but it is reassuring that the reading
independently lands on the same three levers the user named: numbers, placement,
terrain.

## What I would try first, in order

Mine, not the sources', and offered as a starting point rather than a plan:

1. **More enemies, one at a time**, sampling after each. Cheapest change, biggest
   expected effect, and the sharpest dial so it needs the most care.
2. **One glass cannon** in the roster — high damage, low hp. Watch whether the
   strong party starts taking casualties without the coin-flip party collapsing.
3. **Then placement**, with the dangerous ones deep so they have to be reached.
4. **Then terrain**, once 13a lands.

Re-run `Tools/SampleFights.gd` between each. If two changes land together and the
table moves, you have learned nothing about either.

## Sources

- [Action Economy in Dungeons and Dragons](https://dice-scroller.com/en/action-economy-in-dungeons-and-dragons-meaning-and-tips/)
- [A Guide to Combat Balance in D&D](https://www.cottageofeverything.com/blog/guide-to-dnd-combat-the-basics)
- [Enemy design — The Level Design Book](https://book.leveldesignbook.com/process/combat/enemy)
- [Encounter — The Level Design Book](https://book.leveldesignbook.com/process/combat/encounter)
- [Road to the IGF: Subset Games' Into the Breach](https://www.gamedeveloper.com/game-platforms/road-to-the-igf-subset-games-i-into-the-breach-i-)
- [Into the Breach Design Postmortem (GDC Vault)](https://www.gdcvault.com/play/1025772/-Into-the-Breach-Design)
- [Creating Challenging Encounters for RPG Players](https://www.dungeonsolvers.com/tips-for-creating-challenging-encounters-for-players/)
- [Encounter Design as Story Beats, Not Just XP Budgets](https://litrpgreads.com/blog/tabletop-rpg-encounter-design-as-story-beats-not-just-xp-budgets)

The Into the Breach GDC PDF is worth someone reading in full — I could not fetch
it (403) and took the count-sensitivity quote from secondary coverage, so treat
that one as second-hand.
