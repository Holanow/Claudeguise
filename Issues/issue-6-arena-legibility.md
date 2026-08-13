# Issue 6: make the arena a place, and close criterion 8

**Assigned to: pike.** Small, entirely inside your own files, and startable now.

## Where this came from

Looking at your five screenshots from issue 3. The units read well and the log
reads well, and the space they are standing in does not exist: there is no floor,
no boundary, and nothing that says how far apart two pawns are. `Palette` has
carried `ARENA_FLOOR` and `ARENA_EDGE` since the skeleton and nothing has ever
drawn either — **that is my gap, not yours.** I defined tokens and never wrote an
issue that used them.

It matters more here than it would in most games. The combat is free 2D
positioning, so whether a ranged pawn is keeping its distance, whether a melee
pawn is stuck walking, whether the party is spread or clumped — all of that is
the thing being judged, and none of it is legible against an empty background.

## Outcome

A fight looks like it is happening somewhere. Distance and position are readable
at a glance, and a fight that went badly because the party was badly positioned
looks different from one that went badly because the numbers were wrong.

## Files you own

- `Scripts/UI/**`
- `Scenes/**`
- `Tests/test_ui_*.gd`
- `Screenshots/**`

Same exclusions as issue 3. `Palette` is mine: if you want a colour that is not
there, post the exact line on the board and I will add it, usually within
minutes. Do not put a colour literal in `Scripts/UI/`.

## Scope

**1. Draw the arena.** A floor filling the play area in `Palette.ARENA_FLOOR`
and a boundary in `Palette.ARENA_EDGE`, matching the bounds the simulation
actually uses — `CG.ARENA_HALF_WIDTH` and `CG.ARENA_HALF_HEIGHT` either side of
the origin. It must agree with `_layout_arena`, not be a second guess at the same
rectangle.

**2. Give the eye a sense of scale.** Something that makes distance readable. A
faint grid, a centre line, distance rings around the focused unit — your call.
Whatever it is, keep it quieter than the units: this is the floor, not the
subject.

**3. Close criterion 8 from issue 3 with a real measurement.** You deferred it
honestly because your fixtures sat idle forever and there was nothing to time.
`CombatSim` is real now, and issue 4 landed on top of it, so you can build a
fixture where two units attack each other and the fight actually ends — wren's
`Tests/test_combat_sim.gd` has the pattern for driving one without content.
Time it and assert wall-clock elapsed matches ticks divided by
`CG.TICKS_PER_SECOND`.

**Do not build:** animation, particles, sprites, camera movement, or anything
that needs an asset file.

## Acceptance criteria

Two cases each.

1. **The drawn arena and the simulated arena are the same rectangle.** A unit at
   exactly `(CG.ARENA_HALF_WIDTH, CG.ARENA_HALF_HEIGHT)` renders on the boundary,
   not outside it and not well inside it. And a unit at the origin renders at the
   centre of the drawn floor. One case alone passes with a rectangle of the wrong
   size but the right centre.
2. **It survives a resize.** Both of the above hold at 1280x720 and at 900x600.
   Screenshot both.
3. **Criterion 8, measured.** Wall-clock seconds from `FIGHT_START` to
   `FIGHT_END` match ticks over `CG.TICKS_PER_SECOND` within a small tolerance,
   on a fight that actually resolves. Then the same with frames deliberately
   dropped — a long stall in one frame must be caught up, not lost. Paste both
   numbers.
4. **The floor stays the floor.** With units, bars, labels, floaters and log all
   on screen, the arena decoration is still visibly quieter than the units.
   Screenshot a busy moment and a near-empty one; the second is where an
   over-bright grid stops being obvious and starts looking fine.

## What would make stopping the right answer

If you try a grid, rings and a plain boundary and conclude none of them help
read a fight, say that and ship only the boundary. "I tried three and they all
made it noisier" is a real result and I would rather have it than a decorated
screen nobody can read.

## Before you ask for review

`Tools\gate.ps1` green, `main` merged in, collected test count up, screenshots
taken after your last commit.
