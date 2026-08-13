# Issue 21: look at your pawns between fights

**Three parts, one per session. 21a and 21b can start now; 21c needs 21a.**

## The request, from the user

> "Between fights I could inspect the units. See what their plans of action are
> and what their available options for plans of action are. Ideally I can mouse
> over / click and see a description of the skills they're using and the
> conditions."

## Why this is bigger than it sounds, and worth doing now

`README.md` builds the whole game on the player being a coach who writes plans.
The slice deliberately shipped the interpreter with no editor, on the reasoning
that the fight itself had to be judged first. That was right. But it left the
game in a state where **the pawns are running plans the player cannot see**, and
where the one decision they do make — which four classes — is made with no
information about what those classes will actually do.

This is the read-only half of the coaching loop, and it is the half that makes
the plan editor obvious later rather than mysterious. It is also the cheapest
possible test of whether the plan system is legible at all: if a player cannot
*read* a plan, they will never write one.

**Read-only. No editing in this issue.** If it turns out reading naturally
invites editing, say so and I will scope that separately rather than letting it
grow here.

---

## 21a — the words · **teal**

**Files:** `Scripts/Content/**`, `Scripts/Plans/**`, `Tests/test_content_*.gd`.

Nothing in the game currently explains itself. Three gaps:

1. **`ActionDef.description` exists on the trunk now** (mine, added for this) and
   every action has it empty. Fill it in: one or two sentences per action, in a
   player's language, saying what it does and when it is worth using. **Not the
   numbers** — the screen reads those off the fields and they change every time
   you tune.
2. **Plan conditions and blocks have no descriptions at all.** `enemy_in_range`,
   `self_hp_below_fraction`, `target_lowest_hp_fraction_ally` and the rest are
   identifiers. Expose something like
   `PlanInterpreter.describe_op(op: StringName, args: Dictionary) -> String` that
   turns one into a readable line — ideally with the arguments folded in, so
   `enemy_in_range {range: 220}` reads as "an enemy is within 220" rather than as
   a name and a dictionary. Shape is yours; pike needs *a* function.
3. **The available options.** pike needs to show what a pawn *could* use, not
   only what it does. Today that is `CONDITION_OPS`, `TARGETING_OPS`,
   `ACTION_OPS` and `DURATION_OPS` plus the pawn's own `actions`. Expose it
   deliberately rather than having pike read your constants.

Per `README.md` blocks are meant to be found as loot and not shared between
pawns. Loot is out of scope, so for this slice everything is available to
everyone — **say that on the screen or it will read as a bug later.**

### Acceptance criteria
1. Every registered action has a non-empty description, asserted by a test that
   walks the real registry. And a *new* action added without one fails that test
   — check by adding one temporarily.
2. Every op in all four whitelists produces a readable line from
   `describe_op`, and an unknown op returns something that says so rather than
   crashing or returning empty. Both.

---

## 21b — the screen · **pike**

**Files:** `Scripts/UI/**`, `Scenes/**`, `Tests/test_ui_*.gd`, `Screenshots/**`.

An inspect view, reachable **between fights** — from party select is the obvious
place, and from the end-of-fight screen is probably the more useful one, since
that is when a player has just watched something confusing.

For a selected pawn: its class, its stats, its actions, and **its plans in
priority order, written out as sentences** — "When an enemy is within 220: target
the nearest enemy, then cast Geyser Blast." Plus what it could use but is not.

Hover or click reveals the detail. On a phone hover does not exist, so **tap has
to work and be the primary interaction** — anything hover-only is desktop-only.

This depends on teal's `describe_op` and descriptions. **Build against the
function signature and let the text be empty until 21a lands**; do not invent
descriptions in `Scripts/UI/`, because two sets of wording will diverge and
yours will be the one nobody updates.

### Acceptance criteria
1. A player can read every plan a pawn will run, in priority order, in sentences
   rather than identifiers. Screenshot at 1280x720 and at 844x390.
2. Reachable from party select **and** from the end of a fight, both
   screenshotted. Reachable by tap, not only hover.
3. **The cold-read test again, and it is the real one here:** show it to wren or
   teal and ask them to predict what one pawn will do in the first five seconds
   of a fight. Then run that fight and compare. Paste both. If they cannot
   predict it, the screen is not doing its job — and that is a finding about the
   plan system's legibility, which is worth more than the screen.
4. What a pawn *cannot* use is distinguishable from what it *can*, and the
   screen says everything is available in this slice rather than leaving it
   ambiguous.

---

## 21c — the numbers the screen needs · **wren**

**Files:** `Scripts/Combat/**`, `Tests/test_combat_*.gd`.

Only if pike finds they need derived values that are currently computed inside
`CombatSim.build` and thrown away — effective hp, effective attack power, the
scaled tick costs of an action for a specific pawn. A pawn's card should show
what that pawn will actually do, not what the base numbers say.

**Do not build this speculatively.** Wait until pike asks. If they never do, this
part does not exist.

---

## What would make stopping the right answer

If writing the plans out as sentences reveals that the preset plans are
incoherent — that a pawn's stated plan does not match what it visibly does — stop
and report that. It would be a defect in the interpreter or the presets rather
than the screen, and it is exactly the sort of thing that only becomes visible
when you try to explain it to somebody.
