# Issue 5: the shape of floor 1

**QUEUED. Not assigned to anyone yet.** I assign this by name when a session
frees up. Do not self-assign, and do not start it because you finished
something and it looked free — with one issue and two idle sessions, "whoever
gets there first" produces a race, and the politeness that resolves the race
then produces a deadlock where both stand down. Ask me and I will name someone.

## Where this came from

The user, directly: *"if you end up with spare engineering hours on this one,
you can start working towards a full first floor."* That is the exact scope —
spare hours, and floor 1 only. It does not displace the slice. If your current
issue is open, this is not your work.

**Read this before you start:** the slice's question is whether the combat is
fun. A floor is eight rooms of a combat nobody has judged yet. So this issue
deliberately builds the *structure* and not the content, and if the answer to
the combat question comes back badly, the structure survives and the content
would not have.

## Outcome

A party clears a room, sees what is next, chooses where to go, and arrives in
the next room with the same pawns carrying the same damage. Eight rooms, a
miniboss, a boss, and a floor that is the same shape on the way back down as it
was on the way up.

## Files you own

- `Scripts/Floor/**` — new, all of it
- `Tests/test_floor_*.gd`

## Files you must not touch

- `Scripts/Content/**` — teal's. **This is the one that matters here.** Room
  contents, enemy rosters, what a treasure room contains: all teal's. You build
  the room graph and the room *types*; teal fills them. A `FloorRoom` says "this
  is an enemy room with difficulty 3", never which enemies.
- `Scripts/Combat/**` — wren's. A fight is `CombatSim.build` and `step`, exactly
  as today. If a floor needs the simulation to do something new, that is an
  issue for wren, not an edit by you.
- `Scripts/UI/**` and `Scenes/**` — pike's. You will want a map screen. You do
  not build it. Expose the state and let pike draw it.
- `Scripts/Core/**`, `Tools/**`, `Tests/run_tests.gd` and the other gate files,
  `project.godot` — mine.

That leaves you building a headless model of a floor with tests, and nothing
visible. That is intentional and it is why this is good spare-hours work: it
collides with nobody.

## Scope

**Build:**

- A floor as a graph of rooms with connections, generated from a seed.
  `README.md`: floor 1 has 8 rooms. The room types are named there — Enemy, Big
  Enemy, Trap, Treasure, Library, Cell, Miniboss, Boss.
- Generation that is deterministic from the seed, for the same reason
  everything else is.
- **Layout preserved on ascent and descent**, per `README.md`. The floor is
  generated once and the return trip walks the same graph. This is a constraint
  on the data model, so build it in now rather than discovering it later.
- Party state that persists between rooms: which pawns, their damage, their
  resources. A pawn that finished a room at 3 hp starts the next one at 3 hp
  unless something heals it.
- Whatever a room needs to say to be run as a fight, without naming content.

**Do not build:** the other six floors, the shops between floors, loot tables,
the map screen, or any enemy. Trap and Library and Cell rooms exist as *types*
with no behaviour; a room whose behaviour is not built should say so rather
than pretending to be an empty enemy room.

## Acceptance criteria

Two cases each.

1. **The same seed gives the same floor.** Two generations from one seed have
   identical rooms, types and connections. Two different seeds do not. Paste
   both room lists.
2. **Every room is reachable, and the boss is last.** From the entrance, every
   room can be reached; and the boss room cannot be reached without passing the
   miniboss branch point. Check both across at least twenty seeds and paste the
   count, because a generator that produces a good floor on the seed you happened
   to test is the normal failure here.
3. **Descent and ascent see the same floor.** Walk down, walk back up, and the
   rooms and connections match by identity, not by count. Then confirm a floor
   walked twice in one direction also matches, so the test is not passing on a
   symmetry it did not earn.
4. **Damage persists between rooms, and death sticks.** A pawn that ends a room
   at 3 hp enters the next at 3 hp; a pawn that died is still dead in the next
   room. The second half is what stops the party quietly resetting.
5. **Room counts match the design.** Floor 1 has 8 rooms, exactly one boss and
   exactly one miniboss, across twenty seeds. Paste the distribution of the
   other types too: if every floor is six enemy rooms and nothing else, the
   generator is technically passing and the floor is boring.

## What would make stopping the right answer

If you conclude a room graph is the wrong model — that floor 1 wants a
corridor, or a hand-authored layout, or something else — say so before building
it. `README.md` says procedurally generated and it is a design document, not a
specification I will defend.

And if the combat question comes back "no", this issue is cancelled rather than
finished. That is a fine outcome for it.

## Before you ask for review

`Tools\gate.ps1` green, `main` merged in, collected test count up. No screenshot
to take, because nothing here is visible; say that rather than leaving it
unmentioned.
