# Issue 11: play it, and try to win

**Assigned to: wren.** Do this before issue 10. It is time-sensitive.

## Why you

The user's instruction is that they should not be the first person to play this
game. So somebody here has to, and it should not only be me.

You are the least disqualified. teal wrote the decision-making, which is the
thing most under test, and cannot meet it fresh. pike has watched more fights
than anyone and knows what every pixel means. You wrote the simulation, so you
know the mechanics and not the *feel*, which is the half this is about.

**Fresh eyes are a depleting resource and nothing tracks who has spent theirs.**
If you have already sat and watched fights for enjoyment rather than for
debugging, say so and I will find someone else. Nobody will think less of you: a
spent tester who reports anyway produces a data point that looks real and is not.

## What this is not

It is not "check our work". Adversarial review finds errors in what we built.
Someone trying to win finds errors in what we *believed*, and those are the ones
nobody has written down.

## Your goal, which is to win

**Win the floor 1 encounter with exactly one pawn surviving.** Not four, not
zero. One.

If that turns out to be impossible, get as close as you can and tell me the
closest you managed. Then try these, in order, and stop when you run out of
patience rather than when you run out of list:

- Win with four of the same class, for each class that can.
- Find the party that wins with the most health remaining, and the one that
  loses slowest.
- Find a seed where the outcome surprises you.

## How to play

```
godot --path . --resolution 1280x720
```

That is the real game: party select, pick up to four, type a seed, watch. Use
the real controls. Do not call the functions underneath, do not read the combat
log for state you could not have seen on screen, and **do not read the output of
`Tools/SampleFights.gd` before you play.** If you already know the answer you
cannot report a first impression, and a false first impression is worse than
none.

## What to report, in your block on the board

Not a pass or a fail. Write what happened, in this order:

1. **What you did and what happened.** The parties, the seeds, the outcomes.
2. **Whether you enjoyed any of it.** Honestly. "I was bored by the second
   fight" is the most useful sentence you could write and the hardest one to
   write about your own team's work.
3. **What you could not tell.** Any moment where you did not know why something
   happened, what a thing on screen meant, or who was winning.
4. **What you wanted to do and could not.** This is the whole point of an
   autobattler where the player is a coach. If you wanted to tell a pawn
   something and there was no way to, write it down.
5. **Anything you predicted that turned out wrong.**

Numbers where you have them, in the units the complaint is in. "It took three
tries" beats "it was hard".

## What would make stopping the right answer

Reporting that it is not fun. That is a real deliverable and it is the one with
every incentive against it: you built part of this, nothing in a normal workflow
ever asks whether the thing is any good, and the easy path is a tidy report of
mechanics working. The single most useful report of the run this process came
from was "I tried for hours and it does not work".
