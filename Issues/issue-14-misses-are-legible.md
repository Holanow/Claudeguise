# Issue 14: a caster that never connects

**Three parts. teal has the important one. wren and pike have a few lines each.**

## What I found, and how

I read a whole fight through `Tools/PlaytestLog.gd`, which prints only what the
event stream contains — the same thing the battle view reads, nothing more. Seed
`0000002A`, the four-class party, floor 1.

```
geysermancer   fired   6   landed   1
siege_master   fired   2   landed   2
priest         fired   6   landed   6
abomination    fired   1   landed   1
```

**The Geysermancer fired six times and connected once.** Nothing on screen or in
the log said why. As a player this reads as "my caster is broken", which is the
worst possible reading because the simulation is working exactly as specified.

## The cause

`geyser_scald` has `range_units = 200`. Its preset plan's only condition is
`self_resource_at_least: {amount: 40}` — **no range check at all** — and its
targeting block is `target_lowest_hp_fraction_enemy`, which picks the weakest
enemy rather than the nearest one, and the weakest is very often the far one.

`geyser_blast` has range 200 and its plan's condition is
`enemy_in_range: {range: 260}`, so it commits at up to 260 with a 200-range
action and misses everything between.

`siege_master`'s two plans have conditions of 240 and 260 against actions of 240
and 260, which match — and siege_master landed 2 of 2.

So: **a plan's condition range and its action's range are two independent
numbers, and nothing checks that they agree.** `PlanInterpreter` never asks
whether the action can reach the target it was told to use.

This is the shape I flagged on the board earlier and it keeps proving true: the
defects left are not inside anyone's files. teal owns both numbers, neither is
wrong on its own, and nothing compares them.

---

## 14a — plans do not order impossible shots · **teal**

**Files:** `Scripts/Content/**`, `Scripts/Plans/**`.

Fix the numbers, but fix the class of bug rather than the two instances:
`PlanInterpreter` should not return a `use_action` intent when the focused
target is beyond that action's `range_units`. Either fall through to the next
plan, or return a move-into-range intent — your call, and say which you chose
and why.

The numbers alone would be a fix for today and the same bug will be back the
first time anyone adds an action.

### Acceptance criteria
1. A plan whose condition range exceeds its action's range does not produce a
   shot that misses; and a plan whose ranges agree still fires normally. Both.
2. Re-run `Tools/SampleFights.gd` and the fired-versus-landed counts. Every
   class lands the large majority of what it fires. Paste before and after.
3. A test that walks **every preset plan** and asserts its action can be reached
   under the condition that fires it. Walk the real plans from `PresetPlans`,
   not a list typed in the test.

---

## 14b — the simulation says when a shot missed · **wren**

**Files:** `Scripts/Combat/**`, `Tests/test_combat_*.gd`.

`CG.EventKind.MISS` is on the trunk now, added by me and documented there.
Emit it in `_fire_action` when `_resolve_targets` comes back empty, carrying the
source, the intended target and the action id.

Small, additive, and it does not change a single outcome — only what the event
stream says about them.

### Acceptance criteria
1. An action that lands on nothing emits exactly one `MISS`; an action that hits
   emits none. Both.
2. Issue 1's replay test still passes: a `MISS` moves no hp.

---

## 14c — a miss looks like a miss · **pike**

**Files:** `Scripts/UI/**`, `Tests/test_ui_*.gd`.

Show it. A log line, and something on the unit or the target. "X's Y fires" with
silence after it is the thing that made this read as a broken game.

### Acceptance criteria
1. A missed action produces a visibly different log line from a landed one, and
   from an action that dealt zero damage through mitigation. Those three are
   different events and a player should be able to tell them apart.
2. Screenshot a fight containing a miss, at phone size.

---

## What would make stopping the right answer

If teal finds that forbidding out-of-range plan actions makes the casters
passive — standing still because no plan can fire — that is a finding worth more
than the fix, and it points at `DefaultBehavior` needing to catch the fall
rather than at the plans being wrong.
