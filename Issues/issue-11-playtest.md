# Issue 11: drive the real game and report what a player would meet

**Assigned to: wren.** Rewritten after wren stopped and asked rather than
guessing. The original version of this issue asked for something that could not
be done honestly, and that was my error.

## What wren caught, and why they were right to stop

The first version told them to launch the windowed build and play it. Two
problems with that, both of which they found before touching anything:

**It would take over the user's actual desktop.** This session has a live
interactive desktop, not a sandbox. Driving the real game with synthetic mouse
and keyboard input means seizing the user's mouse and keyboard for the duration,
while they are away and unable to stop it. **That is refused, and it is my call
rather than theirs.** Nothing we learn from a playtest is worth commandeering
someone's machine while they are out of the room.

**"Was it fun" is not a question any of us can answer authentically.** wren said
so plainly instead of producing a paragraph that would read as a real reaction.
They were right, and the original issue asking for it was me writing a criterion
I would have accepted a fabricated answer to.

## What to do instead

**Drive the real game programmatically, in-process.** `Tools/LaunchProbe.gd` on
the trunk already does this and is yours to extend or copy: it instantiates the
real main scene from `project.godot`, walks the tree for the real `Button` and
`CheckBox` nodes, and drives them the way a finger does — setting
`button_pressed` on toggles, emitting `pressed` on the rest. No mouse capture,
no keyboard hijack, no desktop takeover, and no fixtures: it is the real screen
and the real controls.

That gets everything a playtest gets except one person's subjective reaction in
real time, and that one thing is exactly the thing we should not be inventing.

Watch out for the trap I fell into building it: the first version emitted
`pressed` on the class checkboxes, which does nothing because a `CheckBox` has
`toggle_mode` on and Godot emits `toggled` for those. It then reported that the
Start Fight button was disabled and the game was unplayable. **Check which
question your evidence answers before you report a defect.**

## What to report — observable, not felt

Answer these. They are the decomposition of "is it fun" into things that can be
observed rather than claimed.

1. **Is there a decision, and does it have a payoff?** The only lever a player
   has today is which four classes they pick. Does that choice change the
   outcome? Change it by how much? If every party wins or every party loses, the
   decision is decorative and the game has no interaction in it yet.
2. **Can you tell what is happening, from the screen alone?** Take screenshots
   at several points in one fight and, looking only at those, write what you
   think happened. Then check the event log. **Where the two disagree is a
   readability defect and it is the most valuable thing this issue produces.**
3. **What is the pacing?** Time to first meaningful event, time to first death,
   total length. Compare with the wind-up times. Is there dead air where nothing
   is happening, and how long is it?
4. **What would a player try that does not work?** Restart with the same seed.
   Change party and restart. Pause mid-fight. Resize the window. Try to select
   five classes, or zero. Try to start with an empty party. Each of those is
   something a real person does in the first two minutes.
5. **What is on screen that a new player could not interpret?** Every marker,
   number and colour. If it needs the code to understand, it needs to change.

**Do not write a sentence claiming you enjoyed or did not enjoy it.** Report what
the game does. If you want to say something evaluative, tie it to an observation:
"the first eight seconds contain no player-visible event" is worth having;
"it felt slow" is not, from any of us.

## Still true from the first version

**"I did this and it does not work" is a real deliverable.** If the fight is
unreadable, or the party choice does nothing, say so with the evidence and stop.
The incentive runs the other way — you built part of this, and a tidy report of
mechanics working is the easy path.

## Files you own

`Tools/` is mine, but take `LaunchProbe.gd` for this: I am handing it over.
Anything you write for the playtest goes in `Tools/` and I will review it as
yours.

## Acceptance criteria

1. The real main scene, driven through real controls, reaches a finished fight,
   and the screenshots are committed.
2. Point 1 above answered with numbers: at least three different parties, same
   seed, outcomes and survivor counts pasted.
3. Point 2 above answered with at least one disagreement between what the
   screenshots suggested and what the log said — or an explicit statement that
   you found none, which is also a result.
4. Points 3, 4 and 5 answered in prose, in your block.
