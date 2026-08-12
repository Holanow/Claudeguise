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

- **No remote.** `git remote -v` is empty, so there is no `gh pr create`, no pull
  requests and no code host. Review happens on local branches until somebody adds
  a remote. The manager decides how, and records it in the board's gate block.
- **No CI.** Nothing runs automatically. The gate is whatever the manager builds
  and states on the board.
- **Godot is the runtime.** `.godot/` was not copied; the editor rebuilds it on
  first open. It stays gitignored.
