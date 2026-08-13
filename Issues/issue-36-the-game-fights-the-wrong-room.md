# Issue 36: the real game fights the wrong room, and cannot be lost

**Assigned to: pike. This is one line and it is the highest priority on the
board.** Drop issue 33 until this is in.

Found by wren playing the game, which is the only place it is visible.

## The bug

`Scripts/UI/PartySelect.gd:252`, in `current_config()`:

```gdscript
var encounters := Registry.all_encounter_ids()
config.encounter_id = encounters[0] if not encounters.is_empty() else &""
```

`all_encounter_ids()` returns a **sorted** list. `floor1_chokepoint` <
`floor1_cover` < `floor1_ghoul_den` < ... < `floor1_room1`. So the room a player
actually fights is whichever encounter happens to sort first, and it has never
once been `floor1_room1` — the room every balance decision on this project has
been made about.

The fix:

```gdscript
config.encounter_id = CG.DEFAULT_ENCOUNTER
```

## What it does to the game

wren measured it rather than describing it: all five buildable parties, 200
seeds each, against the room the game actually loads. **Zero non-wins in 1000
samples.** Every fight they watched ended "Victory, your whole party survived"
in 6.3 to 9.8 seconds.

**The game currently cannot be lost.** Not for a balance reason. Because it is
playing a different room from the one that was balanced.

Against the intended room those same parties lose plenty, and one of them loses
every single time. **The stakes exist and nobody can see them.**

This is also why wren's honest answer to "is it fun to watch" was no: every fight
is the same shape, both sides converge, the party wins clean in eight seconds.
They were watching a room with two ghouls in it.

## Same bug, third time, and the first two were mine

`SampleFights.gd` had exactly this — `all_encounter_ids()[0]` — and teal caught
it after two rounds of retuning produced byte-identical output. I introduced
`CG.DEFAULT_ENCOUNTER` to fix it, updated `ContactSheet`, `PlaytestLog`,
`PlaytestRun` and later `TerrainAB`, wrote a long comment in `SampleFights`
about the failure mode, and **never grepped for the pattern anywhere else.** I
fixed every instance I owned and none that I did not.

So the rule is worth stating once more, since it has now cost this project three
times: **when you find a bug of this shape, search for the shape.** The comment I
wrote about it is still sitting five lines above a function that had the same
class of defect in it.

## Acceptance criteria

1. `PartySelect` uses `CG.DEFAULT_ENCOUNTER`. It is one line.
2. **A test that would have caught it.** The real value here is not the fix, it
   is that a `PartySelect` config and the encounter the rest of the game names
   can never silently disagree again.
3. Launch the game and confirm the fight is `floor1_room1`, and that a party
   can lose. wren's report says `no_siege_master` (Warrior, Priest,
   Geysermancer, Abomination) loses on every seed tried, so that is your check.

## While you are there, if it is cheap

The room's name is in `Encounter.display_name` and nothing shows it. A player
who cannot tell one room from another also cannot tell that this bug is
happening. Your call whether it belongs in this fix or issue 33.
