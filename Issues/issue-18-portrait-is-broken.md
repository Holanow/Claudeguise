# Issue 18: the battle screen falls apart on a phone

**Assigned to: pike.** After issue 17.

## The evidence

`Tools/preview/play_07_resized_390x844.png`, from wren's playtest. They resized
to a phone-portrait viewport, which is exactly the thing the user asked us to
imagine, and the screen comes apart:

- The HUD line is microscopic and runs off the right edge, so the party, the
  seed and three of the four controls are cut off or unreadable.
- The arena becomes a letterboxed strip in the upper third.
- Roughly half the screen below the arena is empty.
- The combat log is a block of tiny text jammed against the bottom edge.

None of that is a surprise. Everything so far has been designed and screenshotted
at 1280x720 and the layout has no idea portrait exists. It is worth having as an
issue rather than a shrug because the user named the target directly.

## A decision I am making, and you should push back if you disagree

**The design target is a phone held in landscape**, not portrait.

The reason is the arena. `CG.ARENA_HALF_WIDTH` and `ARENA_HALF_HEIGHT` are 480
and 270 — a 16:9 battlefield — and a fight in free 2D wants width. Squeezing
that into a 9:19 portrait viewport either shrinks it to a strip, which is what
happens today, or requires a different arena shape, which is a `Scripts/Core`
change and would invalidate every spawn position and range teal has tuned.

So: **landscape is what has to be good. Portrait has to not be broken.** Those
are different bars and I mean them as different bars.

I am not certain this is right. It is my call from the arena's aspect ratio and
nothing else, and if you have looked at more of this than I have and think
portrait is the real target, say so and I will take it to the user.

## Scope

1. **Landscape phone, properly.** A short, wide viewport around 844x390. The
   arena fills it, the HUD fits, the log does not eat the arena, and everything
   is legible at that size. This is the one that has to be good.
2. **Portrait, not broken.** At 390x844 nothing runs off an edge, nothing is
   unreadable, and the controls are all reachable. It may letterbox and it may
   look unremarkable. It must not look like a bug.
3. **`Palette.TOUCH_TARGET_MIN` is 48** and every control has to meet it at both
   sizes. On a phone this is the difference between playable and not, and it
   cannot be seen in a screenshot — measure it.

## Acceptance criteria

Two cases each.

1. Screenshots at 844x390 and 390x844, both committed. In neither does anything
   run off an edge or overlap something else.
2. The arena is the largest thing on screen in landscape; in portrait it is at
   least half the height. Both measured, not eyeballed.
3. Every control is at least `TOUCH_TARGET_MIN` on its short side at both sizes.
   Assert it in a test rather than looking at it: a control that is 47 pixels
   looks fine and fails a thumb.
4. A fight is followable at 844x390 — repeat issue 15's cold-read exercise at
   that size with wren or teal and paste what they say.

## What would make stopping the right answer

If landscape phone turns out to need a different HUD rather than a smaller one,
say so before building it. That is a design conversation and it is cheaper than
a scaled-down desktop layout that nobody can use.
