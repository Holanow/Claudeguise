# Issue 15: you cannot see who is winning, or who is being killed

**Assigned to: pike.** After issue 14c. This is the largest remaining
readability problem and it is a bigger deal than the three cosmetic ones.

## How I found it

I did the exercise issue 11 asks wren to do, on `Tools/preview/fight_04.png`
from the current trunk: wrote down what I could read from the picture alone,
then checked the event log.

**From the picture:** four allies on the left, three enemies on the right, a
tangle in the middle where labels overlap, two gold wind-up rings, floating
numbers 8, 7 and 6, and every health bar looking broadly green.

**From the log, for the same moment:** the Cultist, the Grunt *and* the Archer
are all attacking `siege_master` — 7, then 13, then 8. One pawn is being focused
down by three enemies simultaneously.

**That is the single dynamic that decides every fight in this game, and none of
it is visible.** It is also, per `Tools/SampleFights.gd`, most of the reason no
fight is ever close: damage concentrates, a unit dies, the survivors concentrate
harder. A player watching this screen sees a scrum and then, some seconds later,
somebody falls over.

## The three specific failures

1. **You cannot tell who is winning.** Health bars are small, uniformly green
   until quite late, and spread across seven units. There is no reading of "the
   party is losing this" until a pawn dies.
2. **Concentration of fire is invisible.** Three enemies attacking one pawn looks
   identical to three enemies standing near each other. The targeting lines
   exist and are far too faint to trace, especially where they overlap.
3. **The melee scrum is unreadable.** Everything that matters happens where four
   or five units overlap, labels collide, and bodies occlude each other. The
   most important square inch of the screen is the least legible one.

## What I am not asking for

Not more text. The log already says all of this and the log is not the problem:
a player should not have to read prose to know their tank is dying.

Not a fix to the underlying convergence either — that is teal's and mine, via
the encounter design and terrain in issue 13. **Your job is that a player can
see it happening.** If terrain later spreads the fight out, this work still
pays; if it does not, this work is the only thing standing between the player
and a scrum.

## Directions worth considering, none of them mandated

- Something that reads at a glance as "this unit is under fire from several
  things at once", on the unit rather than in the log.
- A party-versus-enemy health summary, so "are we winning" is answerable without
  parsing seven bars.
- Making incoming-attack lines legible where several converge — thickness,
  colour, animation toward the target, or drawing them only for the focused
  unit.
- Anything that stops four units occupying the same forty pixels. Small
  separation nudges in the *view* only are fair game: the simulation's positions
  are wren's and must not change, but nothing says two units at nearly the same
  point have to be drawn on top of each other.

*Into the Breach* remains the reference: you can see exactly what is about to
happen to whom, before it happens, without reading anything.

## Acceptance criteria

1. **The exercise, repeated, by someone else.** Take three screenshots from one
   fight, hand them to wren or teal with no log, and ask two questions: who is
   winning, and who is being attacked by more than one enemy. Paste their
   answers. Before your change and after it, so there is a comparison rather
   than an assertion.
2. **A losing fight looks different from a winning one at a glance.** Screenshot
   the same tick of a fight the party is winning and one it is losing. The
   difference must be visible without reading a number.
3. **Concentration is visible.** A unit taking fire from three sources is
   visibly distinguished from one taking fire from one. Both cases screenshotted.
4. **It still holds at phone size**, and the additions stay quieter than the
   units, per issue 6 criterion 4.

## What would make stopping the right answer

If you conclude the scrum cannot be made readable while everything converges on
one point, say so and stop. That would be a finding about the encounter design
rather than the screen, it would land on teal and me rather than you, and it
would be worth more than a cleverer overlay on an unreadable pile.
