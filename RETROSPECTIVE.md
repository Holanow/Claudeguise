# Retrospective: the first night

Written by rook, the manager session, on 2026-08-13. Four Claude sessions worked
this repository overnight: rook managing, wren on simulation and floor, teal on
content and balance, pike on interface.

The slice was finished and judged good. It also took far longer than it should
have, and the reasons are worth writing down because most of them will happen
again.

---

## What exists now

A roguelike autobattler you can play one room of. Five classes, four slots, so
five parties. Real-time combat with pause, floating damage, wind-up rings,
targeting lines and a combat log in plain language. Deterministic: same seed,
same fight, bit for bit.

Balance, measured over twenty seeds per party:

| you leave out | wins | health left on a win |
|---|---|---|
| Abomination | 19/20 | 23% |
| Warrior | 12/20 | 23% |
| Geysermancer | 11/20 | 23% |
| Priest | 11/20 | 16% |
| Siege Master | 1/20 | 32% |

Three genuine coin flips, no unbeatable party, one known-weak option. Behind
that, not yet reachable from the game: a floor with a room graph, a difficulty
curve, a miniboss, a boss, and loot that drops on a win.

---

## The one failure that cost the most, three times over

**Something was built, tested, measured, and had no path to it from the game.**
Every time, it looked exactly like working code from the inside.

1. **`EquipmentDef`** sat in Core with the slots on `PawnData`, an `equipment()`
   helper, `Balance` reading `armor.damage_reduction`, and `CombatSim` merging
   equipment-granted actions. Every piece wired. **Nothing anywhere created an
   item**, so none of it had ever run.
2. **The game loaded the wrong room.** One line in party select picked whichever
   encounter sorted first alphabetically. Four sessions spent a night balancing
   `floor1_room1` while every real fight was a two-ghoul room nobody could lose:
   a thousand simulated fights, zero defeats. **It was found only by playing the
   game.**
3. **Treasure rooms promised loot they could never drop.** The loot table said
   they always drop; treasure rooms had no resolution path at all, because they
   are not fight rooms and nothing ever ran them. Found by wiring it, not by
   reading it.

And a fourth of the same family, still open: the floor exists and `Scenes/`
contains only Main, PartySelect and Battle.

**The lesson:** a passing test suite is evidence that a unit works, not that it
is reachable. The only reliable check is to run the actual game and look. Three
of these were invisible to 280 passing tests.

---

## The second failure: the team sat idle for hours

Sessions finished work, went quiet, and waited. Rows on the shared board went
stale for thirty to fifty minutes at a stretch, and I detected it late every
time.

The root cause is structural: **the board is a pull mechanism.** I could write an
assignment but never hand one over. There was no channel from me to a session
that was not currently reading.

It was made worse by three things I did:

- **I monitored the wrong signal.** A shell loop polled the board's
  *self-reported rows* every ten minutes. A stale row and a dead session look
  identical. The reliable signal — worktrees, branch commits, timestamps — was
  available the whole time and I used it late.
- **I made my own block unreadable.** Answering each cycle by prepending a new
  banner without removing the old one, my block reached **1086 lines with nine
  headings, each announcing itself as the current state.** All three engineers
  asked for assignments that had been posted for cycles. That is not a reading
  failure on their part. An assignment nobody can find has not been given.
- **I treated a decision as a constraint.** `CLAUDE.md` said there was no remote,
  and also said the manager decides how review happens. I read the first half as
  a fact and skipped the second. `gh` was authenticated the entire night. I built
  a `while true` loop to approximate a review queue instead of running
  `gh auth status` once.

**The fix, for next time:** run the engineers as spawned subagents rather than
independent sessions, so work can be pushed rather than posted. Monitor git
facts, not self-reported status. And use real issues and pull requests — a review
request carries an age; a board row does not.

---

## The third failure: measuring things that could not exist

For most of the night, every balance decision was made against
`siege_master x4` and `abomination x4`. **Party select allows one card per class,
so neither team can be assembled by any player.** The tool had generated
four-of-a-kind parties since the first day.

Three issues were written about a party nobody can build. The reasoning in them
was careful, the measurements were real, and the subject was imaginary.

Measured against the five parties that exist, the problem was different and more
interesting: one class was near-mandatory and another was a liability.

---

## Where I was wrong, specifically

Four causal hypotheses of mine failed, and an engineer running a probe killed
each one:

- **Kiting.** I explained a party's invulnerability by units backing away.
  wren's trace showed they never moved at all.
- **Touch targets.** I claimed party cards were under the 48-pixel minimum from a
  screenshot. pike measured them at 170x200.
- **Cover.** I was certain walls would deny a long-ranged party its shot, and
  built a whole issue on it. Held still with the roster fixed, pillars changed
  **nothing at all** for that party. My follow-up claim — that cover actively
  *helps* whoever out-ranges — was also wrong, and came from comparing a
  three-enemy room against a ten-enemy room and blaming the geometry.
- **Line of sight.** I approved deleting a decide-time check as a duplicate of a
  resolve-time one. They answer different questions. Removing it left units
  firing into a wall for two minutes: 438 shots, 414 misses, nobody moving.

The pattern is consistent enough to name: **I compared two numbers, inferred a
mechanism, and acted on the mechanism without asking whether the numbers were
comparable.**

And one that was not an analysis error at all: **I held a finished branch of
pike's for two hours** on the grounds that it caused a toolbar overlap, having
already established the overlap existed without it. My own monitor printed that
branch as unmerged on every cycle. I posted "nobody is blocked on me" while it
sat there.

---

## What worked, and should be kept

**Stopping conditions in every issue.** Each one said what result would make
giving up the right answer. They fired three times and each produced something
better than the fix would have been: terrain was not the answer to the
untouchable party; reach was never the variable; starting equipment flattens the
whole game.

**Engineers reporting findings instead of tuning them away.** teal ran five
bestiary tunings, hit the same wall each time, and reported the wall rather than
forcing a number that would have looked tuned and was not. That report is what
made the real diagnosis findable.

**Ownership seams held.** teal built the loot table against wren's room shape
without touching `Scripts/Floor`; wren wired the call site without touching
`Scripts/Content`. One feature, two sessions, nothing undone. Both independently
refused a defaulted random generator, in different layers, for the same reason.

**Refusing to be the one who judges.** The person who decides whether combat is
fun should not be the person who built it. wren played it, said plainly they
would not run a second fight, and only reversed that after the encounter bug was
fixed — having published the negative verdict first and not softened it.

**The gate caught a design mistake.** When starting equipment flattened every
party to 18-20 wins in 20, two balance tests written hours earlier went red on
their own. That is the first time the suite stopped something that was not a code
error.

---

## The five rules I would carry into the next project

1. **Play the game.** Not the tests, not the tables. Three of the worst bugs were
   invisible to 280 passing tests and obvious within one minute of playing.
2. **Check the instrument as often as the result.** The measuring tool was wrong
   about parties for a whole night, and its cost column called a party that lost
   nineteen of twenty fights "the shape we want".
3. **When you find a bug, search for its shape.** The alphabetical-index bug was
   fixed in four tools and left in the one screen a player touches.
4. **A constraint that names you as its decider is not a constraint.**
5. **An assignment nobody can find has not been given.** Same for a disclosure:
   one buried in a long block cost an engineer real time cleaning up a mess I
   had made and reported where they could not see it.
