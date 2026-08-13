# Issue 19: the moment a fight ends

**Assigned to: pike.** Small. Take it whenever it fits between 17 and 18 —
the first item is a one-liner and I would do that part today.

## Look at `Tools/preview/play_06_battle_end.png`

The climax of the only loop in the game. Four things.

**1. "Victory (197 ticks)".** Ticks are a developer unit. No player thinks in
them, and this is the single most visible piece of internal language anywhere in
the game. `CG.TICKS_PER_SECOND` is right there — "Victory in 6.6s" or just
"Victory". This is the one-line fix and it is worth doing on its own.

**2. The result is a label in a toolbar.** "Victory" sits inline between the
seed and the Pause button, in the same row, at the same weight as everything
else. It is the payoff of the entire fight and it looks like a status field.

**3. Nothing says what it cost.** A player finishing a fight wants to know who
lived and how badly hurt they are. That is on screen in seven small bars and
nowhere as a summary. The team bars from issue 15 exist now and this frame
predates them — check whether they already answer it before building anything
new.

**4. There is no "again".** Restart and Change party are small HUD buttons that
have looked the same all fight. At the end of a fight they are the only two
things a player wants, and this is the moment to make them the obvious next step.

Also visible and lower priority: the death markers overlap the floating numbers
and the unit labels — "Cultist dies", a floating 2 and the Warrior's label are
on top of each other. Same family as the label collisions in issue 15 and
probably the same fix.

## Files you own

`Scripts/UI/**`, `Scenes/**`, `Tests/test_ui_*.gd`, `Screenshots/**`. If you want
a `Palette` entry, post the line.

## Acceptance criteria

1. **No developer units anywhere a player can see.** Not ticks, not resource
   ids, not action ids in a form like `warrior_strike`. Grep for it rather than
   looking: the log prints action ids today and that is the same problem in a
   quieter place. Check the win screen and the loss screen — a loss is the one
   people iterate on and it is the one nobody has screenshotted.
2. **The outcome is the most prominent thing on screen when a fight ends**, and
   is not when the fight is running. Screenshot both.
3. **A player can see what the win cost**, without counting bars.
4. **Restarting and changing party are one obvious action each at the end**, and
   still available mid-fight for anyone who wants them.

## What would make stopping the right answer

If you find the end screen wants to be a separate screen rather than a state of
the battle screen, say so before building it. That is a bigger change than this
issue implies and it should be a decision rather than a discovery.
