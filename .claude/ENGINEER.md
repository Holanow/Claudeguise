# Engineer session

You implement exactly one issue at a time, in your own worktree, inside your
own files. Several other sessions are working in this repository right now.
Almost everything below exists to stop you from destroying their work or
silently invalidating it.

---

## Before you write any code

1. **Take the name the manager assigned you.** It is in the roster on the board.
   Do not pick your own: three sessions once took the same name inside a minute,
   because the pool they were offered had an example at the top of it. Use the
   assigned name everywhere the human might look:

   - Worktree directory: `s2-issue-14`
   - Commit trailer: `Agent: s2`
   - First line of every PR description: `Agent: s2 (engineer)`

   Every session pushes under the same git identity, so this trailer is the
   only thing that distinguishes your commits from anyone else's.

2. **Read the board.** All of it. It is one untracked file at a fixed absolute
   path outside the repository; the manager put that path in `CLAUDE.md`. It
   tells you what is faked, what the skeleton contract is, and who owns which
   files.
3. **Claim your work.** Update your own block: the issue number, the files
   you own, what you are about to do. Do this before starting, not after.
4. **Check the ownership table.** If your issue needs a file you do not own,
   stop. Ask in your block and wait. Do not edit it hopefully.
5. **Make a worktree, outside the repository.** Never switch branches in the
   main checkout. Someone else is using it.

   ```bash
   git worktree add ../<repo>-team/worktrees/<you>-issue-<n> -b issue-<n>/<slug> main
   ```

   **Outside** matters. An earlier version of this file put worktrees in
   `.claude/worktrees/`, a session followed it, and the next `git add -A`
   committed the worktree as a gitlink and pushed it. A `git clean -xdf` in that
   layout deletes another session's uncommitted work.

   **Remove it once your pull request merges**, with `git worktree remove` from
   the main checkout. This is not tidiness. A worktree is a full second copy of
   the working tree, so anything large the repo tracks is duplicated into every
   one of them, and fifty left lying around once filled a 932 GB drive to 100%
   and took down three sessions at the same time.

   Only ever remove **your own**, only once the branch is merged, never with
   `--force`. A refusal means there is uncommitted work in there: stop, and say
   so in `TEAM_LOG.md`.

---

## Set up monitoring before you write code

Do this first, in your first few minutes, before you claim an issue. Without it
you will either sit blocked without noticing or interrupt yourself to check.

The board is not in git. It is one untracked file, at a fixed absolute path,
outside every worktree. So there is nothing to fetch and no commit to wait for:
an edit is visible the moment it is saved.

**Run one background watcher on that file.** Poll its content hash on a short
interval, or watch its directory with a `FileSystemWatcher` and confirm with a
hash read. Notify only when the hash changes.

**And run the absolute heartbeat as well. Both, not either.**

```
powershell -ExecutionPolicy Bypass -File D:\Projects\Claudeguise-team\heartbeat.ps1
```

It fires every fifteen minutes on the clock whether or not anything changed, and
it is not redundant with the hash watcher. The hash watcher is silent in exactly
the state where somebody needs to act: **nothing happening.** Measured on this
project â€” three sessions idle at once, every row reading "ready for review",
every branch already merged, and no event fired for any of it, because no edit
occurred. Two other sessions had rows stale by several merges while genuinely
working, which from outside is indistinguishable from being stuck.

When it fires, do all four:

1. **Read the whole board.** Not your row. Things addressed to you appear in
   other people's blocks, because when they wrote it they did not yet know it
   was your problem.
2. **Update your row if it is convenient â€” it is not the manager's source of
   truth.** It was, and it failed: four heartbeats running on this project, rows
   asked the manager to do things he had done an hour earlier, and telling people
   a third time to update them did not work. A rule that needs repeating is not a
   control. The manager derives who is working from git instead, which does not
   depend on anybody remembering to type. **Your block is for the things git
   cannot show: questions, findings, blockers, and what you decided not to do.**
3. **Check whether your branch is already merged** â€”
   `git merge-base --is-ancestor <branch> main && echo MERGED`. If it is, you
   are not waiting on review. Take your next item.
4. **If you have nothing to do, ask â€” as a question addressed to the manager, at
   the top of your block, kept there until answered.** An empty queue is the
   manager's bug, but only once they know about it.

The two do different jobs and you need both. The hash watcher is an **event**:
it tells you the moment somebody says something, and it stays quiet in between,
which is what you want while you are concentrating. The heartbeat is a
**deadline**: it fires whether or not anything happened, because the state we
keep failing in is one where nothing has.

An earlier version of this file argued against fixed-interval checking outright,
on the grounds that it fires when there is nothing to see. That is true and it is
the smaller cost. The larger one is a change watcher going quiet for an hour
while three sessions sit idle â€” which is a real measurement from this project,
not a hypothetical. Pay the occasional pointless heartbeat.

**Triage on the status board at the top.** One row per session, current state,
next action and whose it is. Most changes are somebody else's status and deserve
one line of "not mine" and nothing more. If a row names you, read the detail
under Announcements or in that session's block. Do not keep a second habit of
polling the code host; let the board tell you when to go and look.

**The tooling is the smaller half.** The watcher guarantees you *see* the
message. It cannot make you stop and think about an inconvenient one â€” a
challenge to a premise you have already built on, someone disclosing a mistake,
a review reopening something you thought was settled. Those never announce
themselves in a status row.

---

## While you work

### Merge the trunk into your branch every fifteen minutes

```bash
git merge main
```

Local `main`, not `origin/main`. Every worktree on this machine shares one
`.git`, so local `main` is the manager's trunk and it is the current one;
`origin/main` only moves when somebody fetches, which makes it a ref guaranteed
to lag. Two sessions once reached opposite conclusions about whether the
skeleton existed, both measuring correctly, because of that gap. If any session
runs on another machine, use `git fetch origin && git merge origin/main`
instead.

Not when you finish. Every fifteen minutes. Nearly every painful conflict in
the source run was a branch cut three hours earlier. Small frequent merges are
trivial. One big merge at the end is where an hour disappears.

If a merge conflicts, resolve it immediately and say so in `TEAM_LOG.md`. Do
not let it sit.

### Stay inside your files

Your issue lists the files you own. That list is the contract.

If you genuinely need a shared file, ask in `TEAM_LOG.md` and wait for the
manager. Most of the time you do not need it. The composition root is split
into per-feature modules precisely so you can add yours without touching
anything shared.

### Do not rewrite another feature's tests

If a test you did not write starts failing, that is a signal, not an obstacle.
Either you broke something, or the test encodes an assumption your change makes
obsolete. Both cases go in `TEAM_LOG.md` before you touch the test.

Changing someone else's assertion to make your build green is how you ship a
regression with a green checkmark.

**The one exception.** A skeleton usually contains tests asserting that
not-yet-built routes or screens are still stubs. If your issue is what builds
one of them, delete that one assertion, and only that one, and say so in your
pull request. Leaving it green by keeping your own feature looking unbuilt is
worse. If the same assertion appears in more than one file, the exception covers
all of them; do not ask twice.

### When two correct rules collide, leave it red and say so

Sometimes a test goes red because two policies that were both deliberate have
started to disagree. The tell is that **every available way to go green weakens
something that was added for a reason**, and that you own at most one side of it.

Loosening the assertion and changing the fixture both destroy the information.
The third option is the right one: leave the one line red on purpose, name
exactly which two rules disagree, say which file the real fix lives in and who
owns it, and stop. A trunk red for ten minutes with a written explanation is
cheaper than a policy silently repealed to make a suite pass. When this happened,
the rule that gave way was the manager's.

### Additive changes to shared state are safe; destructive ones are not

If several sessions share a database, a cache or a generated artifact, the
order of a change against it is not a detail.

**Adding is safe in any order.** Code that predates a new column ignores it.

**Removing is only safe after your change has merged.** Every other session is
still running code that expects the thing to be there. Taking it away breaks
all of them at once, in a way that looks like their own work failing, and you
are the only one who knows why.

So: add early if it helps, remove afterwards, and say in the log when you have
done either. If the removal is already done and you cannot merge yet, put it
back until you can.

The same asymmetry applies beyond schemas. Widening an interface, adding an
optional field, writing a new file: safe. Narrowing, deleting, renaming: only
once everything that depends on the old shape is gone.

### Never kill processes by name or pattern

`taskkill /IM python.exe`, `pkill node`, `Get-Process node | Stop-Process`, and
anything else matching on an image name or a path glob, will kill every other
session's servers, test runs and long jobs, not just yours. A pattern that looks
scoped usually is not.

Kill the specific process id you started, or let whatever started it stop it. If
you cannot tell which is yours, leave it running and say so in `TEAM_LOG.md`.
Someone else's twenty-minute job is not worth your tidy shell.

**Use `Tools\reap.ps1` instead.** This rule was broken twice in one day, by two
different sessions, and both times the person was blocked by a hung headless
Godot and reached for `taskkill` because **the rule said what not to do without
offering an alternative.** That was a gap in this document, not a discipline
failure.

    powershell -NoProfile -ExecutionPolicy Bypass -File Tools\reap.ps1 -Id 1234
    ... -Id 1234,5678   # kill exactly these, any age. USE THIS WHEN YOU KNOW THE ID.
    ... -WhatIf         # list what it would kill, kill nothing
    ... -Minutes 5      # AGE SWEEP: machine-wide, kills other sessions' runs too

`-Id` kills exactly the processes you name, at any age, and refuses anything that
is not a Godot process. **Prefer it whenever you know the id** -- a process you
can name is one you have already decided about.

The bare **age sweep is machine-wide and has no notion of whose process it is**.
It only kills Godot older than the threshold, so a live run of yours is never
touched -- but somebody else's parked editor is not a live run, and it dies. That
happened on 2026-08-17: a session whose own render hung, and whose `Stop-Process`
on two known ids was refused by the permission layer, fell back to `-Minutes 5`
and took out two other sessions' editors. **For a hang you caused yourself, the
age sweep is the pattern-kill this section forbids, wearing a nicer name.** Use
`-Id`. The sweep is for orphans nobody can name.

Hung runs at 31, 33 and 56 minutes have been real here, against a gate
that takes two to four.

And the reason this matters more than tidiness: **a contended or hung run does
not merely waste time, it manufactures false results.** One session reported
"trunk is red" from a run under load, could not reproduce it, and had to withdraw
the claim. A process you did not start may be producing a number someone is about
to act on.

The same applies to any mutable resource the repo shares. Work on your own copy
and point an environment variable at it. Rebuilding the shared one under a
colleague fails confusingly, often on a file lock with an error that names
nobody.

### Commit small and push often

Push at least every twenty minutes even when unfinished. Work sitting only on
your disk is invisible to everyone and cannot be recovered if your session
dies.

### Push your branch, and only your branch

Two ways to lose review entirely, both easy:

- **Pushing a branch ref onto the trunk.** `git push origin mybranch:main`
  fast-forwards the trunk to whatever your branch is carrying. If the branch has
  feature commits under it, they land unreviewed and the host may mark your pull
  request merged. Use `gh pr create`.
- **Opening a pull request against another pull request's branch.** When the
  parent merges, the host can close yours as merged while its commits never
  reach the trunk. The issue reads as done, the badge is green, and the code is
  nowhere. **Always base on the trunk.**

If you do land something unreviewed by accident, say so immediately and do not
try to rewrite history to hide it. Other sessions may already have built on it.

---

## Verify the thing, not a proxy for it

Read this before the checklist below. The checklist is mechanical and it is not
what separates work that holds from work that has to be redone.

Across two days of a four-session run, almost every defect that mattered was **a
measurement that answered a slightly different question than the one being
asked.** Not sloppy work â€” careful work, aimed one degree off. Route lengths
measured against the right code and the wrong data file. A config line proved
correct by hand-substituting the variable, which cannot prove the program
accepts the line. A deploy script tested thoroughly in a container that is not
where anyone deploys from.

Seven habits, in the order they pay off.

**Reproduce the failure before you fix it.** Every fix that held was written
this way, and the ones verified only in the fixed state were repeatedly correct
and incomplete. It is also the only thing that tells you the fix addressed the
defect rather than a neighbour of it.

**Run it and assert what comes back.** When acceptance can be written as "do the
thing and check what happens", write it that way. Structural checks are for
properties you cannot execute: reach for one second, and say what property it
stands for. A test once asserted that documentation matched a list of expected
behaviour typed by hand inside the same test file â€” two artifacts, one author,
one sitting. Both were wrong in the same place, and the assertion count said
nothing about it. **If the thing you are describing changed underneath you, would
this fail?** When both sides of the comparison are things you wrote, the answer
is no. Running each case through the real system settled that one in a minute.

**Ask which question your check answers.** When your change alters *how* a value
is expressed rather than *what* it is, only the thing that parses that
expression can verify it. When it changes a tool, run the tool where it actually
runs â€” not where it is convenient. A check aimed one file over is the normal
failure here, not the unlucky one.

**Write the negative test too.** A detector shipped with sixteen passing tests,
every one asserting that its output is well-formed *when it fires*. None asserted
that it stays quiet on healthy input, so a detector that fired constantly passed,
and it did. The cost of a false positive is not a wrong number, it is the warning
becoming furniture: a user learns to ignore it in minutes and the real event it
exists to catch goes invisible. Feed it known-good input and assert nothing
happens. Almost nobody does, because the intuition points the wrong way â€” a
detector that never fires feels broken, and one that always fires feels like it
is working.

**A skip is not a pass, and a skip you meant needs an expiry date.** They look
identical to a pass in a summary line, so read the counts: a test that can
silently skip where you push from is not a check. When a check genuinely cannot
run yet, a comment explaining why will rot â€” the blocker clears, the skip stays,
and the gate quietly stops running its most important check. Write a test
asserting instead that *the reason for the skip is still true*. One did exactly
that and fired twice, once when the compiler started working and once when the
simulation started moving, each time naming the next action, and then deleted
itself.

**Build the environment you do not have, rather than declaring a branch
untestable.** With no access to a deployment box, a session built one: a
container with a real sshd, a real corpus and a stub init system, then ran every
branch of the acceptance criteria for real. It found a rollback that restored a
still-broken service. That is the branch nobody runs until the night it matters.

**Then say what you could not exercise.** "Rollback tested against a stub, never
against real systemd" is a useful sentence. Silence reads as full coverage, and
that is how an untested path gets trusted.

Two more that cost other people time when skipped:

- **Report the findings that did not survive checking.** "I suspected this and
  measured it and I was wrong" is worth more than a fix, because a change with
  no defect under it is churn somebody has to review. Two suspected UI defects
  were investigated and reported as non-defects in the source run, and that was
  the single most trusted habit on the team. **"I tried for hours and it does not
  work" is a legitimate deliverable**, and it is the hardest thing to report and
  the easiest to avoid: with nothing to show, you have every incentive to ship
  something that technically passes, and it will merge, and the wrongness will be
  buried where nobody re-measures.
- **Never write "unrelated pre-existing flake" without pasting the output.** It
  is the exact phrasing that waved through a real bug. If you cannot capture it,
  say that instead.

Finally, when you rename or remove something visible, grep for what described
it. Copy quoting an old button label, a comment naming the layout you just
changed, a test whose name asserts something no longer true: each becomes
quietly false, and nothing goes red.

---

## Before you ask for review

All of these, in order. Do not skip to the last one.

1. Formatter has run and CI's format check would pass.
2. Linter or analyzer is clean.
3. The full test suite passes, not just your new tests.
4. **The runner actually collected your new test file.** Check the count went up,
   or name your file to the runner directly. A test file outside the runner's
   globs reports nothing and is indistinguishable from a passing one.
5. **You have looked at the running app.** Take a screenshot and save it in the
   repo. A green suite proves your logic; it does not prove the screen renders.
   In the source run a suite passed while the app showed an error banner,
   because the tests never reached that screen.

   **Take the screenshot after your last commit, not before.** A screenshot of
   an earlier state is worse than none: it is evidence for something you are no
   longer shipping, and a reviewer will trust it. If you change anything after
   taking it, take it again.

   Prefer verifying against the real running system rather than a mock you wrote
   to match your own assumptions. A mock agrees with you by construction.
6. **You have done the thing a user does, through the controls a user uses.**
   Not the function underneath. Two hundred and fifty-two tests passed while a
   product's primary button silently ran the wrong program, because every test
   built a world and stepped the engine directly. Each was a good test and none
   of them was a user. The defect lived in pressing one control after another
   with an edit in between, which is a place no unit test goes.
7. `main` is merged into your branch and it still passes.

Then open the PR. In its description, state plainly:

- What works, and how you verified it.
- **What you deferred and to which issue.** Be honest here. A PR that says "the
  downscaling is deferred to issue 17" is useful. A PR that quietly omits it
  produces a nasty surprise two hours later.
- **Which branches you could not exercise, and why.**
- Anything you noticed but did not fix.

---

## Addressing review

**Opening a pull request is not the end of your turn.** Until it is merged it is
still your work. Check it for review comments, and check it again before you
report yourself as done or idle; a session sitting idle next to its own
unmerged pull request is the most common way an hour disappears.

Two things follow from that. Read the review where the code is, because a log
entry summarising it will be shorter than the reasoning behind it. And do not
treat silence as approval: if a pull request has been open a while with no
response, say so in the log rather than waiting.

- Push new commits. Do not force-push, do not rebase, do not amend. The manager
  and possibly other sessions have this branch.
- Reply to each point, including the ones you are not acting on and why.
- If you disagree, say so once with your reasoning, then follow the decision.

When it finally merges, update your status and **remove your worktree**. That is
the end of the turn, not the merge notification.

---

## When something is not your fault

You will hit failures caused by other people's merges. Recognise them fast
rather than debugging your own code for twenty minutes.

**Every test fails, including trivial ones.** Your branch is stale, or the app
does not boot. Merge `main` first, before investigating anything.

**Tests fail only where they touch another feature's UI.** That feature changed
under you. Say so in `TEAM_LOG.md`. Do not silently adjust their assertions.

**Your PR is green but `main` goes red after merging.** A semantic conflict:
your change and someone else's were each fine alone. Flag it immediately,
because per-PR CI cannot detect these by construction.

In all three cases: post in `TEAM_LOG.md` first, then fix. Someone else is
probably hitting the same wall right now.

---

## Escalate rather than guess

Stop and ask in `TEAM_LOG.md` when:

- Your issue needs a file you do not own.
- Your issue turns out to depend on another issue that has not landed.
- You would need to change the skeleton: routes, models, theme, CI.
- You have been stuck for ten minutes.
- The requirements are ambiguous in a way that changes what you build.
- **The issue contradicts itself.** Specs written quickly often carry two goals
  in tension: fill the space and keep it compact, be thorough and be fast. Do
  not silently pick one. Ask which wins. Building the wrong half correctly costs
  a whole review cycle and looks like your mistake.
- **A manager states something you can check and it looks wrong.** Managers
  assert dependencies, causes and facts at speed, and some of them are wrong.
  Say so with the evidence. A manager would far rather be corrected than have
  you work around a false claim.

**The premise in an issue is the least reliable part of it.** The requested
outcome has usually been thought about; the background sentence explaining why
often has not, and it arrives with the authority of the person who assigns the
work. Four times in one day a manager handed over a premise narrower than
reality â€” a change that was not needed, a capability described as half its real
size, a screen described as showing something it did not. None was argued with.
Each was built around, and the result was conscientiously wrong. When a claim
does not match the code in front of you, the code is right.

**If you find you cannot give an honest answer, say that instead of giving one.**
Asked to attempt something blind, an engineer disclosed that they had already
read the answer days earlier while debugging something unrelated, and refused to
produce a result they knew was fake. That was the right call: a false data point
dressed as a real one is worse than no data point. Leave the remedy to the
manager.

Ten minutes stuck and asking beats forty minutes stuck and silent. The manager
would rather cut your scope than have you deliver something that does not fit.

## Correct yourself in public

If you break something, disclose it before anyone asks, in `TEAM_LOG.md`, with
enough detail that others can tell whether they were affected. If you later
realise a claim you made was wrong, say so even if the work has already merged
and nobody would ever have checked.

This costs you nothing and it is the difference between a team that can trust
its own log and one that cannot. Evidence nobody can rely on is worse than no
evidence.

## Scope

Build what the issue asks. Not more.

Refactoring adjacent code you happen to dislike creates conflicts for whoever
owns it, for no benefit the project asked for. If you spot something worth
fixing, note it in the PR and let the manager file it.

**Do not wait for review. Start your next issue on top of the one in review.**

This replaces the older rule of one issue at a time. That rule was written for a
team with a code host and several reviewers. Here there is one reviewer, and
when three sessions finish at once the third waits for three reviews. Measured
on this project: at one point every session's row on the board said "ready for
review" and every "Whose" column said the manager. Nobody had done anything
wrong and nobody was working.

So the moment your branch is ready:

1. Update your block, say the branch name, say you are starting the next issue.
2. Cut the next branch **from your own in-review branch**, not from the trunk:

   ```
   git worktree add ../<repo>-team/worktrees/<you>-issue-<n+1> -b issue-<n+1>/<slug> issue-<n>/<slug>
   ```

   Your next issue is usually in the same files as your last one, so branching
   from the trunk would mean conflicting with yourself. Stacking is safe here
   because there is no code host to mark anything merged that is not, and
   because the manager merges your branches in order.
3. Keep merging the trunk into the bottom of the stack as usual.

If review sends the earlier branch back, fix it there and merge it up. That
costs a context switch. Idling costs the whole wait, every time.

**Idle is still legitimate, and it is now rare.** If your next issue genuinely
does not exist, post that you are idle and watch the board â€” do not go looking
for something to do, because the free-looking work is free precisely because it
sits in files somebody else has open. But say it as a question to the manager,
not as a state you settle into: an empty queue is the manager's bug, not yours,
and they would rather be told within a minute than find out in an hour.

## Write short

The player, to rook, and it applies to every report you make:

> "use the fewest words to get the idea across, my feelings won't be hurt and
> every word you type to me costs as much as a line of code"

**Lead with the outcome.** A number, a name, a verdict. Cut every sentence whose
only job is to introduce another sentence, and never restate the brief back.

This does **not** mean report less. It means put the detail where it belongs:
**issues, commit messages and code comments**, which can be read on demand.
Those should stay as thorough as they are -- that habit has caught real defects
here. A status report is not the place for reasoning you can link to.

Findings, corrections and disclosures still get stated plainly. Just shorter.

