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

Floors, runs, room sequencing, shops and between-floor economy are **parked**,
and their issues carry the `parked-not-single-room` label. Do not work them, and
do not use a floor-run measurement as evidence for a single-room decision.
`Tools/SampleFights.gd` is single-encounter and is the right instrument;
`Tools/FloorRuns.gd` is not.

## The principle that governs pawn behaviour

> **Pawns should never do anything the player cannot see in the plans of
> action.**

The player's own words, and it is binding. An autobattler's loop is: author
behaviour, watch it, adjust. Every hidden rule breaks that loop twice — once
when the pawn does something unasked, and again when there is nowhere to change
it.

This has already cost real work three times. An automatic kiting branch made
the Abomination run away from fights it was built to close. `DefaultBehavior`
picking the first affordable action in list order is why `warden_chain_toss`
never fired, and why `geyser_spout` had to be *placed first* in
`starting_actions` to work at all. **Two of those three were mistaken for
balance problems** and tuned against before anyone found the cause.

It does not mean deleting `DefaultBehavior`: enemies have no plans and do not
need them. It does not mean the player must configure everything — an immutable
default row they can read but not edit satisfies it. The test is: **can the
player see it happening and find where it is decided?** If not, it becomes a
block, a visible default, or it goes. Audit and detail in issue #98.

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
