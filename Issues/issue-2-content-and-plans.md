# Issue 2: five classes, one room of enemies, and pawns that decide

**Assigned to: teal.** Not "whoever picks it up". You.

## Outcome

Every class in `README.md` exists and plays differently. A pawn with no player
input fights competently on its own. The one encounter in the slice is worth
fighting more than once.

You own the numbers. When the answer to "is this combat fun" comes back as no,
this is where it gets fixed.

## Files you own

- `Scripts/Content/**` — including `Registry.gd` and everything in `Modules/`
- `Scripts/Plans/**`
- `Tests/test_content_*.gd` and `Tests/test_plans_*.gd`

## Files you must not touch

- `Scripts/Core/**` — frozen contract, rook's
- `Scripts/Combat/**` — wren's
- `Scripts/UI/**` and `Scenes/**` — pike's
- `Tests/run_tests.gd`, `Tests/TestCase.gd`, `Tests/test_skeleton.gd`,
  `Tests/test_scenes.gd`, `Tools/**`, `project.godot` — rook's
- `Tests/test_stubs_expire.gd` — delete your four lines as you implement them
  (`PlanInterpreter`, `DefaultBehavior`, `Balance`), and nothing else.

## Scope, precisely

**Build:**

- All five classes from the table in `README.md`: Warrior, Priest,
  Geysermancer, Siege Master, Abomination. The attribute columns are blank in
  that table. Filling them in is your job, not a lookup.
- `Balance` in full. Every formula turning attributes into hp, resource, move
  speed, attack power, mitigation, action timing and the WIS block budget.
- Enough actions that each class has a recognisable shape. A Warrior that only
  auto-attacks is not a Warrior.
- `DefaultBehavior`, which is the most important thing in this issue. See below.
- `PlanInterpreter`, with enough block types for the preset plans below.
- Two preset plans per class, shipped on the pawn. No editor, no UI: issue 3
  displays them read-only.
- One encounter: a room of enemies for a four-pawn party, tuned to be winnable
  and losable.

**Do not build:** the plan editor, equipment generation, loot tables, shops,
floors beyond this one room, or the remaining six floors of enemies. All
deferred, deliberately.

## The default behaviour is the product

`README.md` says a player should not have to touch the plan system until they
beat the final boss. That means for this slice, and for most of the real game,
`DefaultBehavior` **is** the combat. Give it the attention that implies. A
default that walks at the nearest enemy and mashes one button will make the
whole slice read as boring, and the honest conclusion "the combat is not fun"
would be wrong: what was not fun was one function.

Ranged classes should keep their distance. Healers should heal someone who needs
it. Tanks should be where the damage is. None of this needs to be clever, and
all of it needs to exist.

## Working alongside wren

Your two halves meet at `Intent` and nowhere else. Write `PlanInterpreter.decide`
and `DefaultBehavior.decide` to read `CombatState` and return an `Intent`; do not
write to a `CombatUnit` except `focus_id`. You can test both against hand-built
`CombatState`s without `CombatSim` working at all, and you should start there
rather than waiting for issue 1 to land.

An unknown block `op` must fail loudly. A skipped block reads to a player as the
plan silently not working, which is the hardest kind of bug to report.

## Acceptance criteria

Two cases each, on purpose.

1. **Classes differ measurably.** Run the same enemy group against a party of
   four Warriors and against a party of four Priests, same seed. The fights
   differ in outcome or in length by a wide margin, and you paste both numbers.
   Then do it for two more pairs.
2. **The default behaviour uses range.** A ranged pawn's median distance to its
   target over a fight is materially greater than a melee pawn's, measured, both
   numbers pasted. Not "it looks right".
3. **A healer heals.** In a fight where an ally drops below half, a Priest emits
   at least one `HEAL` targeting that ally. In a fight where nobody is hurt, it
   emits none and does something else useful instead. The second half is the one
   that catches a healer that spams heals into full-health allies.
4. **Preset plans fire and are visible in the log.** A plan-driven action carries
   its `source_plan`; a default-driven one carries `&""`. Assert both.
5. **An unknown block op fails loudly.** A plan with a nonsense `op` produces an
   error naming the op and the plan, not a silently skipped block. And a plan
   with only valid ops produces no error at all, so the check is not just
   shouting at everything.
6. **The encounter is winnable and losable.** Run it across twenty seeds with a
   reasonable party. Paste the win count. If it is 20 or 0, it is not tuned yet.

## What would make stopping the right answer

If you conclude the encounter cannot be made interesting without a mechanic that
is out of scope — terrain, traps, more than one room — write that down with what
you tried, and stop. That is a finding about the design, and it is worth more
than a shipped fight nobody enjoys.

## Before you ask for review

`Tools\gate.ps1` green, `main` merged in, collected test count up. State in the
PR which of your numbers are guesses and which you measured across seeds.
