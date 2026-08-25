# Claudeguise

A Godot 4.5 roguelike autobattler. `README.md` is the design document.

The game is playable. A deterministic fixed-tick simulation, five classes, a
plan system the player edits, terrain, projectiles, summons and a drawn battle
screen all exist and run. **This paragraph described "an empty scene and script
skeleton" for weeks after that stopped being true**, which is the failure mode
this file is most prone to: a description written once and never re-read
against the thing it describes.

## The goal right now

**One room, and nothing else.** In the player's words: *"get single room combat
super satisfying and fun — I should be eager to try out every team
combination."* And, ruling out the rest: *"This should really be one room,
nothing else. For now at least."*

**And it now has a finish line, in the player's words:**

> "Single room combat is done when I can watch a fight **without pausing** and
> broadly follow what happened **and why**, and when that process is
> interesting and engaging enough to get me to want to do it again."

Read that against any change you are about to make. It is not "the fight is
balanced" and it is not "every feature is built" — it is **legible without
pausing, and worth repeating**. The "and why" is the demanding half: a player
who can see *that* a pawn retreated but not *why* has not met it, which is the
same thing the pawn-behaviour principle below is about.

The player is playing a cut of it periodically and leaving specific notes.
Those notes are the measurement.

**The order the game gets built in**, in the player's words:

> "we're building out so a solid 1 room combat, then a solid 1st floor, then the
> rest"

So the parked work below is **next, not indefinite** — floor 1 follows this, and
floors 2 to 7 are far enough away that designing for them is waste. `README.md`
has a full bestiary of seven bosses and seven mini-bosses; **only The Warden and
the Rat King are floor 1**, and the other twelve are not worth anyone's time
yet. Same for shops, the ascent, and the Gate Guardian.

This is a reason to keep parked issues parked rather than a reason to start
them. It is written down so nobody reads "one room, nothing else" as "floors are
cancelled", and nobody reads the bestiary as a work queue.

Floors, runs, room sequencing, shops and between-floor economy are **parked**,
and their issues carry the `parked-not-single-room` label. Do not work them, and
do not use a floor-run measurement as evidence for a single-room decision.
`Tools/SampleFights.gd` is single-encounter and is the right instrument;
`Tools/FloorRuns.gd` is not.

## Balance: the freeze has lifted, the discipline has not

**The freeze's own condition is met.** It read *"frozen until equipment lands"*
and named #100 as the unblocker; #100 merged. Pawns wear gear, weapons grant the
basic attack, seventeen items are equippable.

So balance changes are allowed again. **What does not change:**

- **Measure, report, then act -- in that order.** Every number this project got
  wrong was got wrong by acting first.
- **Do not edit a threshold because a measurement crossed it.** #144 records five
  widenings of one cap and zero narrowings; after five it constrains nothing.
- **A regression is a finding.** Report it plainly, including when it is yours.

The original reasoning, kept because it explains every number below it:

> **"Equipment will pretty fundamentally change the balance so basically all
> balance changes should be tabled until then."**

The player's ruling, and it is binding. The reason is not caution, it is that
**every balance number this project has ever taken was measured on pawns
wearing no equipment.** Seventeen items are defined, `PawnFactory` equips
nothing, and the day a pawn can wear plate the whole table moves. Tuning
against today's numbers is tuning against a state the game will not be in.

**What this forbids:**

- Changing damage, health, costs, cooldowns, ranges or attribute values *to
  move a win rate*.
- Loosening or tightening a threshold in a test because a measurement crossed
  it. finch already refused this once and was right: a cap 0.9 points over
  while the underlying number moved eighteen points is not a threshold problem.
- "Fixing" a party that got worse. Several deliberately did — the Warrior lost
  Block to armor and gets it back by wearing plate, which is the equip screen's
  job to prove.

**What it does not forbid**, and these are where the work is:

- **Building systems and features.** Equipment, the plan editor, the room
  picker, kiting as a block, making hidden behaviour visible.
- **Fixing defects.** A mechanic that does nothing, an ability nothing can
  reach, a stall, a wrong icon. If it is broken it gets fixed, whatever it does
  to a number.
- **Measuring, and reporting what you measure.** Keep taking numbers. Report
  movement plainly, including regressions. **Report it; do not act on it.**
- Content that adds something new, as long as it is not authored to hit a
  target win rate.

If you cannot tell which side of the line a change falls on, it is a balance
change. Post it on the board and ask.

**The unblocker is #100, equipment**, and it is therefore the highest-value
work on the board.

## The principle that governs pawn behaviour

> **Pawns should never do anything the player cannot see in the plans of
> action.**

The player's own words, and it is binding. An autobattler's loop is: author
behaviour, watch it, adjust. Every hidden rule breaks that loop twice — once
when the pawn does something unasked, and again when there is nowhere to change
it.

This has already cost real work three times. An automatic kiting branch made
the Abomination run away from fights it was built to close. `warden_chain_toss`
never fired. `geyser_spout` had to be *placed first* in `starting_actions` to
work at all. **Two of those three were mistaken for balance problems** and
tuned against before anyone found the cause.

**Those three happened. The mechanism this file used to blame for the last two
did not, and sessions reasoned from it for weeks** — including a manager brief
that handed the wrong rule to the engineer who then measured it. It said
`DefaultBehavior` "picks the first affordable action in list order". Measured on
#575, here is what the code does instead:

- **A plan row wins if it can act at the instant the pawn is free.** Order is
  priority only among the rows that can act *now*. `_action_can_fire` — range,
  line of sight, cost, cooldown, summon cap, mark — is a **second, silent gate
  with nothing to do with the row's condition**, and it is the half nobody knew
  about. Long actions make those instants rare: a pawn is busy 71.8% of its
  life, and 9.5% of busy ticks have a higher row ready and unreadable.
- **`DefaultBehavior` is heal, then a self-buff gated on `unit.pawn == null`, so
  never a pawn, then the *cheapest* attack on whichever side of
  `MELEE_RANGE_THRESHOLD` matches the target's distance.** List order survives
  only as the tie-break between two equally cheap attacks on the same side.
- **Commitment is actions, not plans.** `MOVE_TO` never sets busy, so a walking
  pawn re-reads its whole plan every tick. Only wind-up and recover commit, and
  `_interrupt_on_stun` is the one designed way to break that.

**What caused the original two was not re-derived**, and the examples no longer
reproduce: `geyser_spout` comes from the `orb` weapon now rather than from
`starting_actions` at all. Keep them as a warning about the trap. Do not cite
them as evidence for a rule.

It does not mean deleting `DefaultBehavior`: enemies have no plans and do not
need them. It does not mean the player must configure everything — an immutable
default row they can read but not edit satisfies it. The test is: **can the
player see it happening and find where it is decided?** If not, it becomes a
block, a visible default, or it goes. Audit and detail in issue #98.

## Comments are one sentence, and the gate counts them

The player, 2026-08-20:

> "we should remove basically any comment that is a diary entry, we already
> have the issue board"

**A comment block keeps its first sentence.** 6,339 lines came out of the repo
on that ruling: comment lines 12,889 -> 6,565 against 25,017 of code, and the
longest block in the repo went from 82 lines to 10.

`Tools/gate.ps1` fails any comment block over 10 lines. The older 2:1 ratio cap
is still there and is now inert -- the repo sits at 0.26:1, so nothing can fail
it. **The block cap is the live control.** A rule nobody can break is not a rule.

Reasoning goes in the commit or the issue, where it can be read on demand and
cannot rot against the code beside it. A measurement nobody has acted on is an
issue, not a paragraph -- #299, #300 and #302 were all lifted out of comments
during the sweep rather than deleted with them.

**Cut at a sentence boundary, never by line count.** An earlier pass cut blocks
by deleting trailing lines and left 207 comments ending mid-clause. A half
sentence is worse than no comment: it reads as though it is still saying
something.

## Roles

- If you are the manager session, follow `.claude/MANAGER.md`.
- Otherwise you are an engineer session: follow `.claude/ENGINEER.md`.
- The team board is at `D:\Projects\Claudeguise-team\TEAM_LOG.md`. Read it before
  doing anything, keep your own block current, and **never write the whole
  file** — edit by exact-string replacement inside your own block only.

## Layout

```
D:\Projects\
  Claudeguise\               <- this repo, main checkout
  Claudeguise-team\
    TEAM_LOG.md              <- the board. untracked, never committed
    worktrees\               <- one per session, outside the repo on purpose
```

Worktrees go in `..\Claudeguise-team\worktrees\`, never inside this repo. A
worktree under `.claude/` gets committed as a gitlink by the next `git add -A`,
and `git clean -xdf` in that layout deletes another session's uncommitted work.

## Setup facts a session should know before planning

- **Remote: `https://github.com/Holanow/Claudeguise` (private).** Added
  2026-08-13. `gh` is authenticated as Holanow with `repo` scope, so
  `gh issue` and `gh pr` both work. **Use real issues and pull requests**;
  review no longer has to happen on local branches.

  This was set up late and should not have been. The previous version of this
  file said there was no remote and that the manager decides how review happens.
  A manager session read that as a fact about the world rather than a decision it
  was empowered to make, and spent a night approximating a review queue with a
  shell loop instead of checking whether `gh` was authenticated. It was, the
  whole time. **If a constraint in this file names you as the person who decides
  it, it is not a constraint.**

- **No CI.** Nothing runs automatically. The gate is whatever the manager builds
  and states on the board.
- **Godot is the runtime.** `.godot/` was not copied; the editor rebuilds it on
  first open. It stays gitignored.

## Art is baked, not drawn

The player, 2026-08-19:

> "we should do basically 0 drawing with code ever"
>
> "unless the asset itself changes -- like the aim lines"

**If a picture is the same every frame, it is a PNG.** Icons, glyphs, badges,
silhouettes, plates. `Assets/UI/README.md` documents the filename for each, and
`UIArt.texture_for` already prefers a file over the drawn version, so a baked
asset needs no call-site change.

**Draw in code only where the geometry is a function of live state:** an aim
line to a moving target, a bar whose fill is a fraction, a wind-up whose length
is a remaining tick count. Those cannot be assets, because the asset would have
to change every frame.

**A missing sprite falls back to a black square.** Also the player's ruling. The
placeholder polygons existed so a missing file still drew something; that
guarantee is withdrawn deliberately, because a black square is an obvious defect
and 400 lines of unreachable geometry is not.

The trap, hit three times already: a test that measures drawn geometry keeps
passing after that geometry stops being what ships. Rasterise and compare pixels
instead. See #280.
