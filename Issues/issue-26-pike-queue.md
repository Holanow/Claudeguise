# Issue 26: pike's queue, written down where pike can see it

**Assigned to: pike.** Four items, in order. This issue exists because the
previous four items lived in merge messages, issue addenda and board
announcements — which is to say, in my head. pike reported "nothing queued in
`Scripts/UI`", and from where they were standing that was true.

## 1. Draw the terrain (13c), and you are not blocked on it

`CombatState.terrain` is on the trunk: untyped `Array`, empty by default. Build
against a hand-made array of `Terrain.Feature` — `Terrain.make(kind, rect)` and
`Terrain.hazard(rect, damage, type)` are both there and tested.

**You have done this before and it worked:** the entire battle screen was built
against hand-made `CombatState` fixtures months of project-hours before
`CombatSim` produced a real one. When teal's 13b lands you swap the source. If
the screen notices the difference, you reached past the shape, and finding that
out now is worth more than waiting.

Wall, pillar, hazard and pit have to be distinguishable from each other at phone
size, and a pit must not look like a wall — they behave like exact opposites, one
blocking movement and not sight, the other the reverse.

## 2. The combat log still overlays the arena

Open since the issue 15 merge, where I let it through and said so. The log draws
over the arena's lower third, which makes the boundary ambiguous and means a unit
standing there is behind text. Units mostly fight in the middle, which is why it
has survived this long.

## 3. Labels collide in a crowded fight

Issue 15's remaining half. In a scrum, unit names, floating numbers and death
markers land on top of each other — `fight_04.png` had "Cultist dies", a floating
2 and a unit label occupying the same pixels. This got better when the party
stopped spawning in a stack, and it is not solved.

## 4. Issue 21b criterion 3, the cold read

The one that tells us whether the plan system is legible at all. Show your
inspect screen to wren or teal, with no other context, and ask them to predict
what one pawn will do in the first five seconds of a fight. Then run that fight
and compare.

**If they cannot predict it, that is a finding about the plan system rather than
about your screen**, and it is worth more than the screen — because a plan editor
over a plan nobody can read would be a worse feature than no editor, and that
decision is waiting on this answer.

## When this is empty

Say so, and I will open the gate on `Issues/NEXT-after-the-slice.md` rather than
leave you watching the board. Items A and B there — the item system and the plan
editor — are largely yours when it opens.
