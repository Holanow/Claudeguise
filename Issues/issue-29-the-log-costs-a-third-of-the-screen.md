# Issue 29: the combat log costs a third of the screen

**Assigned to: pike.** After issue 28's line-of-sight work settles, and only if
you agree it is worth it — see the last section.

## The tradeoff we just made

Issue 26 item 2 fixed a real problem: the log was drawing over the arena's lower
third and hiding three of seven units. It is fixed by giving the log its own
space below the arena.

The cost is that the arena is now about a quarter of the screen. A 16:9 arena
fitted into what remains after a HUD strip and a log panel comes out around
660x365 in a 1280x720 window, with wide empty margins either side.

**That is a real regression against "everything needs to be larger and more
readable", which is a standing instruction from the user.** It is also the right
call as made: a smaller arena where you can see everything beats a larger one
where three of seven units are behind text. But those are not the only two
options and we have only tried them because they were the two in front of us.

## Options nobody has tried

Offered as starting points. You have looked at this screen more than anyone.

- **Fewer lines.** The log currently shows around ten. Three or four might carry
  the same information, since a player reads the newest line and glances at
  history. The rest is scrollback nobody scrolls.
- **A translucent panel behind the text only**, rather than a solid band the
  arena has to avoid. The original problem was text over units with no
  background, not the log existing.
- **Beside rather than below.** The window is wider than it is tall and the arena
  is 16:9; there is horizontal room that the arena cannot use anyway. Those
  empty side margins are exactly the space a log column would cost nothing to
  occupy.
- **Collapsible.** A player who wants to read the fight rather than watch it can
  open it. This one has a real cost — a hidden log is a log nobody learns to
  read — so I would try it last.

The side option is the one I would try first, purely on the geometry: the arena
cannot use the width and the log can.

## Acceptance criteria

1. The arena is measurably larger than it is now at 1280x720, and **no unit is
   ever behind log text**. Both, screenshotted. The second is the thing we just
   bought and it must not be sold back.
2. It holds at 844x390 landscape phone, which is the standing target.
3. The newest log line is still the most visible thing in the log — whatever the
   layout, a player should not have to hunt for what just happened.

## What would make stopping the right answer

**If you try the alternatives and the current layout is genuinely the best of
them, say so and close this.** A quarter-screen arena that shows everything is a
legitimate answer, and I would rather have your judgement after trying three
things than a change made because I filed an issue. You have said "the current
version is right" about a criterion of mine once tonight already and you were
correct that time.
