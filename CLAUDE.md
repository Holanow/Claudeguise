# Claudeguise

A Godot 4.5 roguelike autobattler. Copied from `God-Guise` as a fresh repository
with no remote and no shared history. `README.md` is the design document and is
the only substantial thing in here so far: the rest is an empty scene and script
skeleton with placeholder `icon.svg` files, plus `Scripts/Pawns/Pawn.gd` and
`Scripts/Pawns/PawnGenerator.gd`.

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
