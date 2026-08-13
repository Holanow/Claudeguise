# Issue 8: a unit at the edge is still fully visible, and a fight is followable

**Assigned to: pike.** Start it on top of `issue-6/arena-legibility` rather than
waiting for me to merge anything.

## 1. The regression

`Screenshots/arena_busy_1280x720.png`, top-left: the unit's name label sits in
the HUD strip and is clipped. This is the same defect issue 3 criterion 5 was
reopened over, and you fixed it properly then. Drawing the arena at its true
extent has put a unit standing on the top boundary back underneath the HUD.

The underlying shape of it is worth naming, because it will keep coming back: a
unit's bars and label draw *above* its position, so the space a unit needs is
taller than its radius and is not symmetric. Anything that fits the arena to the
viewport has to allow for that, not for the radius.

I merged issue 6 with this open rather than holding your branch while three
sessions sat idle. It is not something you got wrong twice.

## 2. Following a fight

The measurement in `Issues/issue-7-close-fights.md` says fights are landslides,
and teal is fixing that. Separately from whether they are close, I could not
follow *why* one side was winning by watching. That is your half.

Not specified, deliberately — you have looked at more fights than I have. Things
worth considering: showing who is targeting whom, making the wind-up read at a
glance rather than as a thin ring, showing when someone is out of resource or
stunned, and making a death land as an event rather than a unit quietly
vanishing.

## Files you own

`Scripts/UI/**`, `Scenes/**`, `Tests/test_ui_*.gd`, `Screenshots/**`.

## Acceptance criteria

1. **Edges, both axes.** A unit on the top boundary has its label and bars fully
   visible; so does a unit on the bottom boundary, where the log overlays the
   arena. Screenshot both.
2. **Still true after a resize**, at 1280x720 and 900x600. A margin that happens
   to work at one size is not a fix.
3. **Someone who did not build it can say why a side won.** Show a fight to a
   session that has not read your code — wren or teal — and ask them what
   happened. Paste their answer. If they cannot tell, that is the finding and it
   is worth more than a screenshot of a feature.
4. **The additions stay quieter than the units**, in a busy fight and in a
   near-empty one, as issue 6 criterion 4.

---

## Added after rendering a real fight

`Tools/preview/fight_sheet.png` on the trunk is six frames of one real fight
through your screen. Three things it shows that were not visible before, all
yours, all in `Scripts/UI/`:

**The combat log runs off the bottom of the screen.** In frames 2 and 3 the last
lines are cut by the viewport edge, and the newest line — the one that matters —
is the one being lost. It also overlays the lower-left of the arena, so a unit
standing there is behind text.

**Names truncate.** "geysermance" in every frame. Either shorten the display
name at the source, shrink the label, or let it wrap; a name that silently loses
its last characters looks like a data bug.

**Labels collide when units bunch up.** "abomination" and "Grunt" overlap in
frame 2. Units clump in the middle of a fight, which is exactly when reading who
is who matters most.

These join criterion 3 rather than replacing it: fix them, then show a fight to
wren or teal and ask them what happened.

## How to see it yourself

```
godot --path . --resolution 1280x720 res://Tools/ContactSheet.tscn
```

`Tools/ContactSheet.gd` is mine and drives your screen unmodified. If it draws
something that misrepresents what a player sees, that is a bug in my tool and I
want to hear about it.
